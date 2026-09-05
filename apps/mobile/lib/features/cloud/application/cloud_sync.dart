import 'dart:async';
import 'dart:io';

import 'package:nextbell_platform/nextbell_platform.dart';

import '../../../core/data/app_database.dart';
import '../../../core/models.dart';
import '../../reminders/data/alarm_scheduler.dart';
import '../../reminders/domain/reminder_planner.dart';
import '../../sync/application/sync_engine.dart';
import '../data/cloud_api.dart';
import '../data/cloud_contracts.dart';

class CloudSync implements SyncEngine {
  CloudSync(this.db, this.api, this.alarms, this.host);
  final AppDatabase db;
  final CloudTransport api;
  final AlarmScheduler alarms;
  final NextbellHostApi host;
  Future<void>? _running;
  bool _refreshRequested = false;
  Object? _session;
  Future<void> _assertSession() async {
    final session = await db.getOne('cloudSession', 'main');
    if (session == null || (session['id'] ?? session['uid']) != _session) {
      throw const CloudFailure(
        'session_changed',
        'The signed-in account changed.',
      );
    }
  }

  Future<void> _updateOperation(Json operation, Json patch) =>
      db.transaction(() async {
        await _assertSession();
        final current = await db.getOne('cloudOutbox', operation['id']);
        if (current != null && current['createdAt'] == operation['createdAt']) {
          await db.put('cloudOutbox', operation['id'], {...current, ...patch});
        }
      });
  @override
  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);
  @override
  Future<void> waitForIdle() async {
    await _running;
  }

  @override
  Future<void> runAfterCurrent() async {
    await _running;
    _refreshRequested = true;
    await run();
  }

  bool _live(Json? lease) =>
      lease?['processId'] == pid &&
      (date(lease?['expires'])?.isAfter(DateTime.now()) ?? false);
  @override
  Future<void> recoverInterruptedSync() => db.transaction(() async {
    if (!_live(await db.getOne('lease', 'cloudSync'))) {
      await db.remove('lease', 'cloudSync');
      await db.health({'syncing': false});
    }
  });

  Future<void> edit(String kind, String targetId, Json? value) async {
    final key = stableId([kind, targetId]);
    await db.transaction(() async {
      final current = await db.getOne('cloudPreference', key);
      final pending =
          (await db.list(
            'cloudOutbox',
          )).where((o) => o['key'] == key).toList()..sort(
            (a, b) =>
                (a['createdAt'] as String).compareTo(b['createdAt'] as String),
          );
      final base = pending.isEmpty
          ? (current?['version'] ?? 0)
          : (pending.last['mutation'] as Json)['baseVersion'] + 1;
      final id = newMutationId();
      final record = {
        'id': id,
        'key': key,
        'operation': 'preference',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'mutation': {
          'mutationId': id,
          'baseVersion': base,
          'patch': {'kind': kind, 'targetId': targetId, 'value': value},
        },
      };
      await db.put('cloudOutbox', id, record);
      await _applyPatch(kind, targetId, value);
    });
    await alarms.reconcile();
    unawaited(runAfterCurrent());
  }

  Future<void> queueCompletion(TaskItem task) async {
    final id = newMutationId();
    await db.transaction(() async {
      await db.put('cloudOutbox', id, {
        'id': id,
        'operation': 'complete',
        'taskId': task.id,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.put(
        'task',
        task.id,
        task.copyWith(completed: true, pendingCompletion: true).toJson(),
        owner: task.listId,
      );
    });
    await alarms.reconcile();
    unawaited(runAfterCurrent());
  }

  Future<void> _applyPatch(String kind, String id, Json? value) async {
    switch (kind) {
      case 'settings':
        await db.put('settings', 'main', {
          ...?await db.getOne('settings', 'main'),
          ...?value,
        });
      case 'source':
        final source = await db.getOne('source', id);
        if (source != null) {
          await db.put('source', id, {
            ...source,
            ...?value,
          }, owner: source['accountId']);
          if (value?['mode'] == 'off') await db.deleteOwner(id, kind: 'entry');
        }
      case 'taskList':
        final list = await db.getOne('taskList', id);
        if (list != null) {
          await db.put('taskList', id, {
            ...list,
            ...?value,
          }, owner: list['accountId']);
          if (value?['selected'] == false) {
            await db.deleteOwner(id, kind: 'task');
          }
        }
      case 'override':
        if (value == null) {
          await db.remove('override', id);
        } else {
          await db.put('override', id, {
            'id': id,
            ...value,
          }, owner: value['sourceId']);
        }
      case 'taskAlarm':
        final task = await db.getOne('task', id);
        if (task != null) {
          await db.put('task', id, {...task, ...?value}, owner: task['listId']);
        }
    }
  }

  Future<void> _overlay() async {
    // Fetched source metadata never owns app preferences.
    for (final pref in await db.list('cloudPreference')) {
      await _applyPatch(
        pref['kind'],
        pref['targetId'],
        pref['deleted'] == true ? null : pref['value'] as Json,
      );
    }
    final pending = await db.list('cloudOutbox')
      ..sort(
        (a, b) =>
            (a['createdAt'] as String).compareTo(b['createdAt'] as String),
      );
    for (final operation in pending) {
      if (operation['operation'] == 'preference') {
        final patch = (operation['mutation'] as Json)['patch'] as Json;
        await _applyPatch(
          patch['kind'],
          patch['targetId'],
          patch['value'] as Json?,
        );
      } else if (operation['operation'] == 'complete' ||
          operation['operation'] == 'completionPending') {
        final task = await db.getOne('task', operation['taskId']);
        if (task != null && task['completed'] != true) {
          await db.put('task', task['id'], {
            ...task,
            'completed': true,
            'pendingCompletion': true,
          }, owner: task['listId']);
        }
      } else if (operation['operation'] == 'device') {
        final id = operation['deviceId'] as String;
        final device = await db.getOne('cloudRemoteDevice', id);
        if (device != null) {
          await db.put('cloudRemoteDevice', id, {
            ...device,
            'alarmsEnabled': operation['enabled'],
            'pending': true,
          });
        }
        final own = await db.getOne('cloudDevice', 'main');
        if (own?['id'] == id) {
          await db.put('cloudDevice', 'main', {
            ...own!,
            'alarmsEnabled': operation['enabled'],
            'pending': true,
          });
        }
      } else if (operation['operation'] == 'removeAccount') {
        final accountId = operation['accountId'] as String;
        final owners = [
          ...await db.list('source', owner: accountId),
          ...await db.list('taskList', owner: accountId),
        ].map((r) => r['id'] as String).toList();
        await db.remove('account', accountId);
        await db.deleteOwner(accountId);
        for (final owner in owners) {
          await db.deleteOwner(owner);
        }
      }
    }
  }

  Future<void> resolveConflict(String id, {required bool keepMine}) async {
    final failed = await db.getOne('cloudOutbox', id);
    if (failed == null) return;
    final key = failed['key'];
    final remote = failed['current'] as Json;
    final pending =
        (await db.list('cloudOutbox')).where((o) => o['key'] == key).toList()
          ..sort(
            (a, b) =>
                (a['createdAt'] as String).compareTo(b['createdAt'] as String),
          );
    Json? desired;
    for (final op in pending) {
      final patch = (op['mutation'] as Json)['patch'] as Json;
      desired = patch['value'] == null
          ? null
          : {...?desired, ...patch['value'] as Json};
    }
    await db.transaction(() async {
      for (final op in pending) {
        await db.remove('cloudOutbox', op['id']);
      }
      await db.put('cloudPreference', key, remote);
      await _applyPatch(
        remote['kind'],
        remote['targetId'],
        remote['deleted'] == true ? null : remote['value'] as Json,
      );
    });
    if (keepMine) await edit(remote['kind'], remote['targetId'], desired);
    await alarms.reconcile();
  }

  Future<void> _flush() async {
    final pending = await db.list('cloudOutbox')
      ..sort(
        (a, b) =>
            (a['createdAt'] as String).compareTo(b['createdAt'] as String),
      );
    final blocked = <String>{};
    for (final operation in pending) {
      if (await db.getOne('cloudOutbox', operation['id']) == null) continue;
      final key = operation['key'] as String?;
      if (operation['error'] != null) continue;
      if (operation['conflict'] == true) {
        if (key != null) blocked.add(key);
        continue;
      }
      if (key != null && blocked.contains(key)) continue;
      try {
        switch (operation['operation']) {
          case 'preference':
            final result = await api.send(
              'POST',
              'preferences',
              operation['mutation'] as Json,
            );
            await db.transaction(() async {
              await _assertSession();
              await db.put('cloudPreference', result['key'], result);
            });
          case 'device':
            final device = await api.send(
              'PATCH',
              'devices/${operation['deviceId']}',
              {
                'alarmsEnabled': operation['enabled'],
                'version': operation['version'],
              },
            );
            await db.transaction(() async {
              await _assertSession();
              await db.put('cloudRemoteDevice', device['id'], device);
              if ((await db.getOne('cloudDevice', 'main'))?['id'] ==
                  device['id']) {
                await db.put('cloudDevice', 'main', device);
              }
            });
          case 'removeAccount':
            await api.send('DELETE', 'accounts/${operation['accountId']}');
          case 'complete':
            await api.send('POST', 'tasks/${operation['taskId']}/complete', {
              'mutationId': operation['id'],
            });
            await _updateOperation(operation, {
              'operation': 'completionPending',
            });
            continue;
          case 'completionPending':
            final status = await api.send(
              'GET',
              'operations/${operation['id']}',
            );
            if (status['state'] == 'failed') {
              await _updateOperation(operation, {
                'error':
                    status['message'] ?? 'Task completion needs attention.',
              });
            }
            continue;
        }
        await db.transaction(() async {
          await _assertSession();
          final latest = await db.getOne('cloudOutbox', operation['id']);
          if (operation['operation'] == 'device' &&
              latest != null &&
              latest['createdAt'] != operation['createdAt']) {
            final remote = await db.getOne(
              'cloudRemoteDevice',
              operation['deviceId'],
            );
            await db.put('cloudOutbox', operation['id'], {
              ...latest,
              'version': remote?['version'] ?? operation['version'] + 1,
            });
          } else {
            await db.remove('cloudOutbox', operation['id']);
          }
        });
      } on CloudFailure catch (e) {
        if (e.code == 'conflict' && e.current != null) {
          await _updateOperation(operation, {
            'conflict': true,
            'current': e.current,
          });
          if (key != null) blocked.add(key);
        } else if ([
          'task_missing',
          'source_missing',
          'event_missing',
          'list_missing',
          'account_unavailable',
          'device_conflict',
        ].contains(e.code)) {
          await _updateOperation(operation, {'error': e.message});
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _download() async {
    final cursor = await db.getOne('cloudCursor', 'main');
    final manifest = CloudManifest.fromJson(
      await api.send('GET', 'sync?since=${cursor?['revision'] ?? 0}'),
    );
    final staged =
        <({String kind, String owner, List<Json> rows, Json metadata})>[];
    for (final collection in manifest.collections) {
      final rows = <Json>[];
      String? after;
      if (!collection.deleted) {
        do {
          final page = CloudPage.fromJson(
            await api.send(
              'GET',
              'collections/${collection.key}/${collection.generation}${after == null ? '' : '?after=${Uri.encodeQueryComponent(after)}'}',
            ),
          );
          for (final row in page.rows) {
            collection.validateRow(row);
            rows.add(row);
          }
          after = page.next;
        } while (after != null);
      }
      staged.add((
        kind: collection.kind.name,
        owner: collection.owner,
        rows: rows,
        metadata: collection.metadata,
      ));
    }
    await db.transaction(() async {
      await _assertSession();
      for (final collection in staged) {
        await db.replace(collection.kind, collection.owner, collection.rows);
      }
      final health = <String, Json>{
        for (final raw
            in ((await db.getOne('cloudHealth', 'main'))?['collections']
                    as List? ??
                []))
          (raw as Json)['key'] as String: raw,
      };
      for (final collection in staged) {
        health[collection.metadata['key']] = collection.metadata;
      }
      // A collection's successful fetch time is distinct from the phone's last download.
      for (final metadata in health.values) {
        final kind = metadata['kind'] == 'entry'
            ? 'source'
            : metadata['kind'] == 'task'
            ? 'taskList'
            : null;
        if (kind == null) continue;
        final source = await db.getOne(kind, metadata['owner']);
        if (source != null) {
          await db.put(kind, source['id'], {
            ...source,
            'lastSync': metadata['syncedAt'],
            'error': metadata['error'],
          }, owner: source['accountId']);
        }
      }
      for (final raw in manifest.preferences) {
        final preference = raw;
        await db.put('cloudPreference', preference['key'], preference);
      }
      for (final pending in await db.list('cloudOutbox')) {
        if (pending['operation'] != 'completionPending') continue;
        final task = await db.getOne('task', pending['taskId']);
        if (task == null ||
            (task['completed'] == true && task['pendingCompletion'] != true)) {
          await db.remove('cloudOutbox', pending['id']);
        }
      }
      final localDevice = await db.getOne('cloudDevice', 'main');
      await db.deleteKind('cloudRemoteDevice');
      for (final raw in manifest.devices) {
        final device = raw;
        await db.put('cloudRemoteDevice', device['id'], device);
        if (device['id'] == localDevice?['id']) {
          await db.put('cloudDevice', 'main', device);
        }
      }
      await db.put('cloudCursor', 'main', {'revision': manifest.revision});
      await db.put('cloudHealth', 'main', {
        'collections': health.values.toList(),
        'serverTime': manifest.serverTime.toUtc().toIso8601String(),
      });
      await _overlay();
      // A newly enabled source must have content fetched under that selection.
      // Preferences can reach a phone before the asynchronous Google job finishes.
      for (final pref in await db.list('cloudPreference')) {
        if (pref['kind'] != 'source' ||
            (pref['value'] as Json)['mode'] != 'alarm') {
          continue;
        }
        final metadata = health.values
            .where(
              (c) => c['kind'] == 'entry' && c['owner'] == pref['targetId'],
            )
            .firstOrNull;
        if (metadata == null ||
            (metadata['selectionVersion'] ?? 0) < (pref['version'] as int)) {
          await db.deleteOwner(pref['targetId'], kind: 'entry');
        }
      }
      await db.health({
        'lastSync': DateTime.now().toUtc().toIso8601String(),
        'syncError': null,
      });
    });
  }

  Future<void> _acknowledge() async {
    final device = await db.getOne('cloudDevice', 'main');
    final state = await db.snapshot();
    final settings = await db.getOne('settings', 'main');
    await host.configureCloudDevice(
      device?['alarmsEnabled'] ?? true,
      settings?['urgentNotices'] ?? true,
    );
    final permissions = await host.permissions();
    final native = await host.alarms();
    final handled = (await db.list('handled'))
        .map((r) => r['id'] as String)
        .toSet();
    final planned = const ReminderPlanner().plan(
      state,
      DateTime.now().toUtc(),
      handled: handled,
    );
    final actualIds = native.map((a) => a.id).toSet();
    final missing = planned.where((a) => !actualIds.contains(a.id)).firstOrNull;
    final revision = (await db.getOne('cloudCursor', 'main'))?['revision'] ?? 0;
    await api.send('POST', 'devices/health', {
      'deviceVersion': device?['pending'] == true ? 0 : device?['version'] ?? 0,
      'appliedRevision': revision,
      'scheduledRevision': revision,
      'scheduledCount': native.length,
      'earliestUnscheduled': missing?.fireAt.toIso8601String(),
      'alarms': permissions.alarms,
      'notifications': permissions.notifications,
      'fullScreen': permissions.fullScreen,
      'error': !permissions.alarms || !permissions.notifications
          ? 'permission'
          : state.alarmError != null
          ? 'scheduling'
          : missing != null
          ? 'capacity'
          : 'none',
    });
  }

  Future<void> setDevice(Json device, bool enabled) async {
    await db.transaction(() async {
      final id = 'device-${device['id']}';
      final pending = await db.getOne('cloudOutbox', id);
      await db.put('cloudOutbox', id, {
        'id': id,
        'operation': 'device',
        'deviceId': device['id'],
        'enabled': enabled,
        'version': pending?['version'] ?? device['version'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await _overlay();
    });
    await alarms.reconcile();
    unawaited(runAfterCurrent());
  }

  Future<void> discardFailed(String id) async {
    final operation = await db.getOne('cloudOutbox', id);
    await db.remove('cloudOutbox', id);
    // Re-download a full snapshot to restore fetched state under discarded edits.
    await db.remove('cloudCursor', 'main');
    if (operation?['operation'] == 'device') {
      final own = await db.getOne('cloudDevice', 'main');
      if (own?['id'] == operation?['deviceId']) {
        await db.put('cloudDevice', 'main', {...own!, 'pending': false});
      }
    }
    await runAfterCurrent();
  }

  Future<void> _run() async {
    final session = await db.getOne('cloudSession', 'main');
    if (session == null) return;
    _session = session['id'] ?? session['uid'];
    final id = newMutationId();
    final acquired = await db.transaction(() async {
      if (_live(await db.getOne('lease', 'cloudSync'))) return false;
      await db.put('lease', 'cloudSync', {
        'id': id,
        'processId': pid,
        'expires': DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc()
            .toIso8601String(),
      });
      return true;
    });
    if (!acquired) return;
    final heartbeat = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(
        db.transaction(() async {
          if ((await db.getOne('lease', 'cloudSync'))?['id'] == id) {
            await db.put('lease', 'cloudSync', {
              'id': id,
              'processId': pid,
              'expires': DateTime.now()
                  .add(const Duration(minutes: 10))
                  .toUtc()
                  .toIso8601String(),
            });
          }
        }),
      ),
    );
    await db.health({'syncing': true});
    try {
      await _flush();
      final lastRequest = date(
        (await db.getOne('cloudRefresh', 'main'))?['at'],
      );
      if (_refreshRequested ||
          lastRequest == null ||
          DateTime.now().difference(lastRequest) >=
              const Duration(minutes: 5)) {
        _refreshRequested = false;
        try {
          await api.send('POST', 'sync');
          await db.put('cloudRefresh', 'main', {
            'at': DateTime.now().toUtc().toIso8601String(),
          });
        } on CloudFailure catch (e) {
          if (e.code != 'rate_limited') rethrow;
        }
      }
      await _download();
      await alarms.reconcile();
      await _acknowledge();
    } on CloudFailure catch (e) {
      final session = await db.getOne('cloudSession', 'main');
      if (e.code == 'session_changed' ||
          (session?['id'] ?? session?['uid']) != _session) {
        return;
      }
      if (e.code == 'reset_cursor' || e.code == 'snapshot_expired') {
        await db.remove('cloudCursor', 'main');
      }
      if (e.code == 'account_deleted' ||
          e.code == 'device_removed' ||
          e.code == 'session_revoked') {
        await host.configureCloudDevice(false, false);
        await host.cancelAlarms(
          (await host.alarms()).map((a) => a.id).toList(),
        );
        await db.delete(db.records).go();
        await db.health({'cloudRequired': true, 'cloudSignedIn': false});
      } else {
        await db.health({'syncError': e.message});
      }
    } catch (_) {
      await db.health({
        'syncError': 'Cloud sync could not finish. Your downloaded alarms are still available.',
      });
    } finally {
      heartbeat.cancel();
      await db.transaction(() async {
        if ((await db.getOne('lease', 'cloudSync'))?['id'] == id) {
          await db.remove('lease', 'cloudSync');
        }
        await db.health({'syncing': false});
      });
    }
  }
}
