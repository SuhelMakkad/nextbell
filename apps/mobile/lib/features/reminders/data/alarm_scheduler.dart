import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

import '../../../core/models.dart';
import '../../../core/data/app_database.dart';
import '../domain/reminder_planner.dart';

abstract interface class AlarmScheduler {
  Future<NativePermissions> permissions();
  Future<NativePermissions> requestPermissions();
  Future<void> reconcile();
  Future<void> cancelSources(Set<String> ids);
  Future<void> testAlarm();
}

class NativeAlarmScheduler implements AlarmScheduler {
  NativeAlarmScheduler(this.db, this.host, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final AppDatabase db;
  final NextbellHostApi host;
  final DateTime Function() clock;
  final planner = const ReminderPlanner();
  Future<void> _tail = Future.value();
  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<NativePermissions> permissions() => host.permissions();
  @override
  Future<NativePermissions> requestPermissions() => host.requestPermissions();

  Future<void> _ingestActions() async {
    final actions = await host.pendingActions();
    await db.transaction(() async {
      for (final action in actions) {
        await db.put('handled', action.alarmId, {
          'id': action.alarmId,
          'kind': action.kind,
          'at': DateTime.fromMillisecondsSinceEpoch(
            action.atMillis,
            isUtc: true,
          ).toIso8601String(),
        });
      }
    });
    await host.acknowledgeActions(actions.map((a) => a.id).toList());
  }

  @override
  Future<void> reconcile() => _serial(() async {
    try {
      // Commit handled state before acknowledgement, independently of scheduling.
      await _ingestActions();
      await db.transaction(() async {
        final state = await db.snapshot();
        final handled = (await db.list('handled'))
            .map((r) => r['id'] as String)
            .toSet();
        final expected = planner.plan(state, clock(), handled: handled);
        final parents = {
          for (final a in planner.plan(state, DateTime.utc(1970))) a.id: a,
        };
        final desired = {for (final a in expected) a.id: _native(a)};
        final existing = await host.alarms();
        for (final alarm in existing.where((a) => a.ringing)) {
          if (parents.containsKey(alarm.parentId ?? alarm.id) ||
              alarm.entryId == 'test') {
            desired[alarm.id] = alarm;
          }
        }
        // Snoozes are native and must survive app termination and reconciliation.
        for (final alarm in existing.where((a) => a.parentId != null)) {
          final parent = parents[alarm.parentId];
          if (parent == null ||
              alarm.fireAtMillis <= clock().millisecondsSinceEpoch) {
            continue;
          }
          final collision = desired.values.any(
            (a) =>
                a.entryId == parent.entryId &&
                a.fireAtMillis == alarm.fireAtMillis,
          );
          if (!collision) {
            desired[alarm.id] = NativeAlarm(
              id: alarm.id,
              entryId: parent.entryId,
              title: parent.title,
              subtitle: 'Snoozed reminder',
              fireAtMillis: alarm.fireAtMillis,
              snoozeMinutes: state.settings.snoozeMinutes,
              sourceIds: parent.sourceIds,
              parentId: alarm.parentId,
            );
          }
        }
        // A user-triggered test alarm survives sync until it fires.
        for (final alarm in existing.where(
          (a) =>
              a.entryId == 'test' &&
              a.fireAtMillis > clock().millisecondsSinceEpoch,
        )) {
          desired[alarm.id] = alarm;
        }
        final remove = existing
            .where((a) => !desired.containsKey(a.id))
            .map((a) => a.id)
            .toList();
        await host.cancelAlarms(remove);
        final permission = await host.permissions();
        final scheduled = <AlarmSpec>[];
        String? issue;
        if (!permission.alarms) {
          // Do not present a cached plan as successfully scheduled after revocation.
          issue = 'Allow alarms in Settings to schedule your reminders.';
        } else {
          final byId = {for (final a in existing) a.id: a};
          final ordered = desired.values.toList()
            ..sort((a, b) => a.fireAtMillis.compareTo(b.fireAtMillis));
          for (final alarm in ordered) {
            try {
              final previous = byId[alarm.id];
              if (!alarm.ringing &&
                  (previous == null ||
                      jsonEncode(previous.encode()) !=
                          jsonEncode(alarm.encode()))) {
                try {
                  await host.scheduleAlarm(alarm);
                } on PlatformException catch (e) {
                  if (e.code != 'capacity') rethrow;
                  // Make room for an earlier reminder when existing later alarms fill the OS.
                  final later =
                      byId.values
                          .where(
                            (a) =>
                                !a.ringing &&
                                a.fireAtMillis > alarm.fireAtMillis &&
                                !scheduled.any((s) => s.id == a.id),
                          )
                          .toList()
                        ..sort(
                          (a, b) => b.fireAtMillis.compareTo(a.fireAtMillis),
                        );
                  if (later.isEmpty) rethrow;
                  await host.cancelAlarms([later.first.id]);
                  byId.remove(later.first.id);
                  await host.scheduleAlarm(alarm);
                }
              }
              scheduled.add(_spec(alarm));
            } on PlatformException catch (e) {
              if (e.code == 'handled') {
                await db.put('handled', alarm.id, {
                  'id': alarm.id,
                  'kind': 'handled',
                });
                continue;
              }
              issue = e.code == 'capacity'
                  ? 'Your phone’s alarm limit is reached. The earliest reminders are scheduled; open Nextbell to extend coverage.'
                  : 'Some alarms could not be scheduled. Check alarm permissions and try again.';
              if (e.code == 'capacity') break;
            }
          }
          if (!permission.notifications || !permission.fullScreen) {
            issue ??= 'Check notification and full-screen access for the complete alarm experience.';
          }
        }
        await db.replace('alarm', 'device', scheduled.map((a) => a.toJson()));
        await db.health({'alarmError': issue});
      });
    } catch (_) {
      await db.health({
        'alarmError': 'Could not verify native alarms. Check device settings, then retry.',
      });
      rethrow;
    }
  });

  @override
  Future<void> cancelSources(Set<String> ids) => _serial(() async {
    try {
      await db.transaction(() async {
        final alarms = await host.alarms();
        final remove = alarms
            .where((a) => a.sourceIds.any(ids.contains))
            .map((a) => a.id)
            .toList();
        await host.cancelAlarms(remove);
        for (final id in remove) {
          await db.remove('alarm', id);
        }
      });
    } catch (_) {
      await db.health({
        'alarmError':
            'Some alarms could not be canceled. Open alarm settings to repair.',
      });
      rethrow;
    }
  });
  @override
  Future<void> testAlarm() => _serial(() async {
    final now = clock().toUtc();
    final alarm = NativeAlarm(
      id: stableId(['test', now.toIso8601String()]),
      entryId: 'test',
      title: 'Hello from Nextbell',
      subtitle: 'A little heads-up for what’s next.',
      fireAtMillis: now.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
      snoozeMinutes: 5,
      sourceIds: [],
    );
    try {
      await host.scheduleAlarm(alarm);
    } on PlatformException catch (e) {
      if (e.code != 'capacity') rethrow;
      final later =
          (await host.alarms())
              .where((a) => !a.ringing && a.fireAtMillis > alarm.fireAtMillis)
              .toList()
            ..sort((a, b) => b.fireAtMillis.compareTo(a.fireAtMillis));
      if (later.isEmpty) rethrow;
      final deferred = later.first;
      await host.cancelAlarms([deferred.id]);
      try {
        await host.scheduleAlarm(alarm);
      } catch (_) {
        try {
          await host.scheduleAlarm(deferred);
        } catch (_) {
          await db.remove('alarm', deferred.id);
          await db.health({
            'alarmError': 'Some alarms could not be restored. Check and repair schedules.',
          });
        }
        rethrow;
      }
      await db.remove('alarm', deferred.id);
      await db.health({
        'alarmError': 'The earliest reminders are scheduled. Open Nextbell to extend coverage as alarms fire.',
      });
    }
    await db.put('alarm', alarm.id, _spec(alarm).toJson(), owner: 'device');
  });

  NativeAlarm _native(AlarmSpec a) => NativeAlarm(
    id: a.id,
    entryId: a.entryId,
    title: a.title,
    subtitle: a.subtitle,
    fireAtMillis: a.fireAt.millisecondsSinceEpoch,
    snoozeMinutes: a.snoozeMinutes,
    sourceIds: a.sourceIds,
  );
  AlarmSpec _spec(NativeAlarm a) => AlarmSpec(
    id: a.id,
    entryId: a.entryId,
    title: a.title,
    subtitle: a.subtitle,
    fireAt: DateTime.fromMillisecondsSinceEpoch(a.fireAtMillis, isUtc: true),
    sourceIds: a.sourceIds,
    snoozeMinutes: a.snoozeMinutes,
  );
}
