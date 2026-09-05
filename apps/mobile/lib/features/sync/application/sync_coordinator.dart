import 'dart:async';

import '../../../core/models.dart';
import '../../../core/data/app_database.dart';
import '../../../core/data/repositories.dart';
import '../../reminders/data/alarm_scheduler.dart';

class SyncCoordinator {
  SyncCoordinator(
    this.db,
    this.auth,
    this.sources,
    this.calendars,
    this.tasks,
    this.alarms, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final AppDatabase db;
  final AccountRepository auth;
  final CalendarSourceRepository sources;
  final CalendarRepository calendars;
  final TaskRepository tasks;
  final AlarmScheduler alarms;
  final DateTime Function() clock;
  Future<void>? _running;
  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);
  Future<void> waitForIdle() async {
    await _running;
  }

  Future<bool> _present(String id) async =>
      !await db.accountRemoved(id) && await db.getOne('account', id) != null;
  Future<void> _withAccount(String id, Future<void> Function() action) =>
      db.transaction(() async {
        if (await _present(id)) await action();
      });

  Future<void> _run() async {
    final leaseId = stableId(['sync', clock().microsecondsSinceEpoch]);
    final acquired = await db.transaction(() async {
      if (date((await db.getOne('lease', 'sync'))?['expires'])
              ?.isAfter(clock()) ??
          false) {
        return false;
      }
      await db.put('lease', 'sync', {
        'id': leaseId,
        'expires': clock().add(const Duration(minutes: 10)).toIso8601String(),
      });
      return true;
    });
    if (!acquired) return;
    // Renew the lease while slow, paginated collections are in flight.
    final heartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(
        db
            .transaction(() async {
              if ((await db.getOne('lease', 'sync'))?['id'] == leaseId) {
                await db.put('lease', 'sync', {
                  'id': leaseId,
                  'expires': clock()
                      .add(const Duration(minutes: 10))
                      .toIso8601String(),
                });
              }
            })
            .catchError((Object _) {}),
      );
    });
    await db.health({'syncing': true, 'syncError': null});
    final errors = <String>[];
    try {
      try {
        await auth.restore();
      } catch (_) {
        errors.add('Some accounts need reconnecting.');
      }
      final now = clock().toUtc();
      for (final account in (await db.snapshot()).accounts) {
        if (!await _present(account.id)) continue;
        final accountErrors = <String>[];
        try {
          await _discoverCalendars(account);
          await _syncCalendars(
            account,
            now.subtract(const Duration(days: 7)),
            now.add(const Duration(days: 90)),
          );
        } catch (e) {
          accountErrors.add(_message(e));
        }
        // Calendar and task APIs fail independently (including revoked scopes).
        try {
          if (await _present(account.id)) {
            await _discoverTasks(account);
            await _syncTasks(account);
          }
        } catch (e) {
          accountErrors.add(_message(e));
        }
        errors.addAll(accountErrors);
        await _withAccount(
          account.id,
          () => db.put(
            'account',
            account.id,
            ConnectedAccount(
              id: account.id,
              email: account.email,
              name: account.name,
              error: accountErrors.isEmpty ? null : accountErrors.join(' '),
            ).toJson(),
          ),
        );
      }
      await alarms.reconcile();
      final state = await db.snapshot();
      if (state.sources.any((s) => s.error != null) ||
          state.taskLists.any((l) => l.error != null)) {
        errors.add('Some sources need attention in Accounts & Calendars.');
      }
      await db.health({
        'syncError': errors.isEmpty ? null : errors.toSet().join(' '),
        if (errors.isEmpty) 'lastSync': now.toIso8601String(),
      });
    } finally {
      heartbeat.cancel();
      await db.transaction(() async {
        if ((await db.getOne('lease', 'sync'))?['id'] == leaseId) {
          await db.health({'syncing': false});
          await db.remove('lease', 'sync');
        }
      });
    }
  }

  String _message(Object e) =>
      e is SyncFailure ? e.message : 'Could not finish syncing this source.';

  Future<void> _discoverCalendars(ConnectedAccount account) async {
    final discovered = await sources.discover(account);
    final cancel = <String>{};
    await _withAccount(account.id, () async {
      final old = (await db.snapshot()).sources
          .where((s) => s.accountId == account.id)
          .toList();
      final found = discovered.map((s) => s.id).toSet();
      for (final previous in old.where((s) => !found.contains(s.id))) {
        await db.put(
          'source',
          previous.id,
          previous
              .copyWith(
                available: false,
                error:
                    'This calendar is no longer in your Google calendar list.',
              )
              .toJson(),
          owner: account.id,
        );
        await db.deleteOwner(previous.id, kind: 'entry');
        cancel.add(previous.id);
      }
      for (final incoming in discovered) {
        final previous = old.where((s) => s.id == incoming.id).firstOrNull;
        final compatible = incoming.canReadEvents || incoming.availabilityOnly;
        final accessChanged =
            previous != null && previous.accessRole != incoming.accessRole;
        if (accessChanged || !compatible) {
          cancel.add(incoming.id);
          await db.deleteOwner(incoming.id, kind: 'entry');
        }
        final merged = CalendarSource(
          id: incoming.id,
          accountId: account.id,
          calendarId: incoming.calendarId,
          name: incoming.name,
          accessRole: incoming.accessRole,
          color: incoming.color,
          primary: incoming.primary,
          hidden: incoming.hidden,
          mode:
              (accessChanged || !compatible) &&
                  previous?.mode == SourceMode.alarm
              ? SourceMode.showOnly
              : previous?.mode ?? SourceMode.off,
          reminderMinutes: previous?.reminderMinutes,
          available: compatible,
          lastSync: previous?.lastSync,
          error: accessChanged
              ? 'Access changed. Review this calendar’s alarm mode.'
              : compatible
              ? null
              : 'Access unavailable.',
        );
        await db.put('source', merged.id, merged.toJson(), owner: account.id);
      }
    });
    if (cancel.isNotEmpty) await alarms.cancelSources(cancel);
  }

  Future<void> _discoverTasks(ConnectedAccount account) async {
    final lists = await tasks.lists(account);
    final cancel = <String>{};
    await _withAccount(account.id, () async {
      final current = (await db.snapshot()).taskLists
          .where((l) => l.accountId == account.id)
          .toList();
      final ids = lists.map((l) => l.id).toSet();
      for (final removed in current.where((l) => !ids.contains(l.id))) {
        cancel.add(removed.id);
        await db.deleteOwner(removed.id);
        await db.remove('taskList', removed.id);
      }
      for (final list in lists) {
        final prev = current.where((l) => l.id == list.id).firstOrNull;
        await db.put(
          'taskList',
          list.id,
          TaskListSource(
            id: list.id,
            accountId: account.id,
            providerId: list.providerId,
            title: list.title,
            selected: prev?.selected ?? false,
            lastSync: prev?.lastSync,
            error: prev?.error,
          ).toJson(),
          owner: account.id,
        );
      }
    });
    if (cancel.isNotEmpty) await alarms.cancelSources(cancel);
  }

  Future<void> _loseSource(CalendarSource source, String message) async {
    await _withAccount(source.accountId, () async {
      final row = await db.getOne('source', source.id);
      if (row == null) return;
      await db.put(
        'source',
        source.id,
        CalendarSource.fromJson(row)
            .copyWith(available: false, error: message)
            .toJson(),
        owner: source.accountId,
      );
      await db.deleteOwner(source.id, kind: 'entry');
    });
    await alarms.cancelSources({source.id});
  }

  Future<void> _syncCalendars(
    ConnectedAccount account,
    DateTime from,
    DateTime to,
  ) async {
    final selected = (await db.snapshot()).sources
        .where(
          (s) =>
              s.accountId == account.id &&
              s.available &&
              s.mode != SourceMode.off,
        )
        .toList();
    for (final source in selected.where((s) => !s.availabilityOnly)) {
      if (!await _present(account.id)) return;
      try {
        await _commitSource(
          source,
          await calendars.events(account, source, from, to),
        );
      } catch (e) {
        await _sourceError(source, e);
      }
    }
    final busySources = selected.where((s) => s.availabilityOnly).toList();
    if (busySources.isNotEmpty && await _present(account.id)) {
      try {
        final result = await calendars.busy(account, busySources, from, to);
        for (final source in busySources) {
          if (result.blocks.containsKey(source.id)) {
            await _commitSource(source, result.blocks[source.id]!);
          } else {
            await _sourceError(
              source,
              result.failures[source.id] ??
                  const SyncFailure(
                    'Google could not read availability. Cached times may be outdated.',
                  ),
            );
          }
        }
      } catch (e) {
        for (final source in busySources) {
          await _sourceError(source, e);
        }
      }
    }
  }

  Future<void> _commitSource(
    CalendarSource source,
    List<AgendaEntry> entries,
  ) => _withAccount(source.accountId, () async {
    final json = await db.getOne('source', source.id);
    if (json == null) return;
    final current = CalendarSource.fromJson(json);
    if (current.mode == SourceMode.off ||
        !current.available ||
        current.accessRole != source.accessRole) {
      return;
    }
    await db.replace('entry', source.id, entries.map((e) => e.toJson()));
    await db.put(
      'source',
      source.id,
      current.copyWith(lastSync: clock().toUtc(), clearError: true).toJson(),
      owner: source.accountId,
    );
  });

  Future<void> _sourceError(CalendarSource source, Object e) async {
    if (e is SyncFailure && e.accessLost) {
      await _loseSource(source, e.message);
    } else {
      await _withAccount(source.accountId, () async {
        final current = await db.getOne('source', source.id);
        if (current != null) {
          await db.put(
            'source',
            source.id,
            CalendarSource.fromJson(current)
                .copyWith(error: _message(e))
                .toJson(),
            owner: source.accountId,
          );
        }
      });
    }
  }

  Future<void> _syncTasks(ConnectedAccount account) async {
    // Flush completions even when the list was deselected after an offline edit.
    final lists = (await db.snapshot()).taskLists
        .where((l) => l.accountId == account.id)
        .toList();
    for (final list in lists) {
      if (!await _present(account.id)) return;
      try {
        final pending = (await db.list(
          'task',
          owner: list.id,
        )).map(TaskItem.fromJson).where((t) => t.pendingCompletion);
        for (final item in pending) {
          if (!await _present(account.id)) return;
          try {
            await tasks.complete(account, list, item);
            await _withAccount(account.id, () async {
              final row = await db.getOne('task', item.id);
              if (row != null) {
                await db.put(
                  'task',
                  item.id,
                  TaskItem.fromJson(row)
                      .copyWith(completed: true, pendingCompletion: false)
                      .toJson(),
                  owner: list.id,
                );
              }
            });
          } on SyncFailure catch (e) {
            if (!e.accessLost) rethrow;
            await db.remove('task', item.id);
          }
        }
        if (!list.selected) continue;
        final fetched = await tasks.tasks(account, list);
        await _withAccount(account.id, () async {
          final currentList = await db.getOne('taskList', list.id);
          if (currentList == null || currentList['selected'] != true) return;
          final old = {
            for (final j in await db.list('task', owner: list.id))
              j['id'] as String: TaskItem.fromJson(j),
          };
          final merged = [
            for (final task in fetched)
              task.copyWith(
                alarmAt: old[task.id]?.alarmAt,
                completed:
                    task.completed ||
                    (old[task.id]?.pendingCompletion ?? false),
                pendingCompletion:
                    !task.completed &&
                    (old[task.id]?.pendingCompletion ?? false),
              ),
          ];
          await db.replace('task', list.id, merged.map((t) => t.toJson()));
          await db.put('taskList', list.id, {
            ...currentList,
            'lastSync': clock().toUtc().toIso8601String(),
            'error': null,
          }, owner: account.id);
        });
      } catch (e) {
        await _withAccount(account.id, () async {
          final current = await db.getOne('taskList', list.id);
          if (current == null) return;
          if (e is SyncFailure && e.accessLost) {
            await db.deleteOwner(list.id);
            await db.put('taskList', list.id, {
              ...current,
              'selected': false,
              'error': _message(e),
            }, owner: account.id);
          } else {
            await db.put('taskList', list.id, {
              ...current,
              'error': _message(e),
            }, owner: account.id);
          }
        });
        if (e is SyncFailure && e.accessLost) {
          await alarms.cancelSources({list.id});
        }
      }
    }
  }
}
