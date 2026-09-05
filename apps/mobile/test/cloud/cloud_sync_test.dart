import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/data/app_database.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell/features/cloud/application/cloud_sync.dart';
import 'package:nextbell/features/cloud/data/cloud_api.dart';
import 'package:nextbell/features/reminders/data/alarm_scheduler.dart';

import '../core/alarm_scheduler_test.dart' show FakeHost;
import '../core/sync_coordinator_test.dart' show account, source, event;

class CloudHost extends FakeHost {
  bool cloudEnabled = true;
  @override
  Future<void> configureCloudDevice(
    bool alarmsEnabled,
    bool urgentNotices,
  ) async {
    cloudEnabled = alarmsEnabled;
  }
}

class Transport implements CloudTransport {
  late Future<Json> Function(String method, String path, Json? body) handle;
  final calls = <String>[];
  @override
  Future<Json> send(String method, String path, [Json? body]) async {
    calls.add('$method $path');
    return handle(method, path, body);
  }
}

void main() {
  late AppDatabase db;
  late CloudSync sync;
  late Transport api;
  late CloudHost host;
  late NativeAlarmScheduler alarms;
  final device = <String, dynamic>{
    'id': 'phone',
    'alarmsEnabled': true,
    'version': 1,
  };
  Json manifest({
    List<Json> collections = const [],
    List<Json> preferences = const [],
  }) => {
    'revision': 4,
    'collections': collections,
    'preferences': preferences,
    'devices': [device],
    'serverTime': DateTime.utc(2026, 9, 5).toIso8601String(),
  };
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = Transport();
    host = CloudHost();
    alarms = NativeAlarmScheduler(
      db,
      host,
      clock: () => DateTime.utc(2026, 9, 6, 14),
    );
    sync = CloudSync(db, api, alarms, host);
    api.handle = (method, path, body) async =>
        path.startsWith('sync?') ? manifest() : {};
    await db.put('cloudSession', 'main', {'uid': 'me'});
    await db.put('cloudDevice', 'main', device);
    await db.put('cloudRemoteDevice', 'phone', device);
    await db.put('account', 'a', account.toJson());
    await db.put('source', 's', source('s').toJson(), owner: 'a');
    await db.replace('entry', 's', [event('s', 'meeting').toJson()]);
  });
  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    await sync.waitForIdle();
    await db.close();
  });
  test(
    'failed later page leaves all old content and cursor untouched',
    () async {
      api.handle = (method, path, body) async {
        if (path == 'sync') return {};
        if (path.startsWith('sync?')) {
          return manifest(
            collections: [
              {
                'key': 'k',
                'kind': 'entry',
                'owner': 's',
                'generation': 'g',
                'deleted': false,
              },
            ],
          );
        }
        if (path == 'collections/k/g') {
          return {
            'rows': [
              {'data': event('s', 'new').toJson()},
            ],
            'next': 'new',
          };
        }
        throw const CloudFailure('offline', 'Offline');
      };
      await sync.run();
      expect((await db.snapshot()).entries.single.id, 'meeting');
      expect(await db.getOne('cloudCursor', 'main'), isNull);
    },
  );
  test('turning calendar off cancels immediately even while offline', () async {
    await alarms.reconcile();
    expect(host.scheduled, hasLength(2));
    api.handle = (_, _, _) async =>
        throw const CloudFailure('offline', 'Offline');
    await sync.edit('source', 's', {'mode': 'off'});
    await sync.runAfterCurrent();
    expect(host.scheduled, isEmpty);
    expect((await db.snapshot()).source('s')!.mode, SourceMode.off);
    expect(await db.list('cloudOutbox'), hasLength(1));
  });
  test(
    'offline device switch survives restart and stale server download',
    () async {
      api.handle = (_, _, _) async =>
          throw const CloudFailure('offline', 'Offline');
      await sync.setDevice(device, false);
      await sync.runAfterCurrent();
      expect((await db.snapshot()).deviceAlarmsEnabled, false);
      expect(host.scheduled, isEmpty);
      api.handle = (method, path, body) async {
        if (method == 'PATCH') {
          throw const CloudFailure('device_conflict', 'Changed elsewhere');
        }
        return path.startsWith('sync?') ? manifest() : {};
      };
      final restarted = CloudSync(db, api, alarms, host);
      await restarted.run();
      expect((await db.snapshot()).deviceAlarmsEnabled, false);
      expect((await db.list('cloudOutbox')).single['error'], isNotNull);
      expect(host.cloudEnabled, false);
    },
  );
  test(
    'fetched metadata retains cloud reminder choices and source health',
    () async {
      api.handle = (method, path, body) async {
        if (path.startsWith('sync?')) {
          return manifest(
            collections: [
              {
                'key': 'sources',
                'kind': 'source',
                'owner': 'a',
                'generation': 'g',
              },
              {
                'key': 'entries',
                'kind': 'entry',
                'owner': 's',
                'generation': 'g',
                'syncedAt': '2026-09-05T10:00:00Z',
                'error': 'Refresh delayed',
              },
            ],
            preferences: [
              {
                'key': stableId(['source', 's']),
                'kind': 'source',
                'targetId': 's',
                'version': 1,
                'value': {
                  'mode': 'showOnly',
                  'reminderMinutes': [30],
                },
                'deleted': false,
              },
            ],
          );
        }
        if (path == 'collections/sources/g') {
          return {
            'rows': [
              {'data': source('s', mode: SourceMode.off).toJson()},
            ],
            'next': null,
          };
        }
        if (path == 'collections/entries/g') {
          return {
            'rows': [
              {'data': event('s', 'meeting').toJson()},
            ],
            'next': null,
          };
        }
        return {};
      };
      await sync.run();
      final s = (await db.snapshot()).source('s')!;
      expect(s.mode, SourceMode.showOnly);
      expect(s.reminderMinutes, [30]);
      expect(s.error, 'Refresh delayed');
      expect(s.lastSync, DateTime.utc(2026, 9, 5, 10));
      expect(host.scheduled, isEmpty);
      expect((await db.getOne('cloudCursor', 'main'))?['revision'], 4);
    },
  );
  test(
    'confirmed deletion clears schedules and cached credentials references',
    () async {
      await alarms.reconcile();
      api.handle = (_, _, _) async =>
          throw const CloudFailure('account_deleted', 'Deleted');
      await sync.run();
      expect(host.scheduled, isEmpty);
      expect(host.cloudEnabled, false);
      expect((await db.snapshot()).accounts, isEmpty);
      expect(await db.getOne('cloudSession', 'main'), isNull);
    },
  );
  test(
    'duplicate sync keeps local dismissals and requests server refresh',
    () async {
      await alarms.reconcile();
      final dismissed = host.scheduled.keys.first;
      await db.put('handled', dismissed, {'id': dismissed});
      await sync.run();
      await sync.run();
      expect(host.scheduled.containsKey(dismissed), false);
      expect(api.calls.where((c) => c == 'POST sync'), hasLength(1));
    },
  );
  test(
    'a late download cannot restore private data after local sign-out',
    () async {
      api.handle = (method, path, body) async {
        if (path.startsWith('sync?')) {
          return manifest(
            collections: [
              {'key': 'k', 'kind': 'entry', 'owner': 's', 'generation': 'g'},
            ],
          );
        }
        if (path == 'collections/k/g') {
          await db.delete(db.records).go();
          return {
            'rows': [
              {'data': event('s', 'private').toJson()},
            ],
            'next': null,
          };
        }
        return {};
      };
      await sync.run();
      expect((await db.snapshot()).entries, isEmpty);
      expect(await db.getOne('cloudCursor', 'main'), isNull);
    },
  );
}
