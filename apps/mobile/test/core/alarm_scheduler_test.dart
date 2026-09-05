import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/data/app_database.dart';
import 'package:nextbell/core/data/repositories.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell/features/reminders/data/alarm_scheduler.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

import 'sync_coordinator_test.dart' show account, source, event;

class FakeHost extends NextbellHostApi {
  final scheduled = <String, NativeAlarm>{};
  final actions = <NativeAlarmAction>[];
  final accountsResult = <NativeAccount>[];
  int calls = 0;
  int? capacity;
  bool allowed = true;
  bool failCancellation = false;
  @override
  Future<List<NativeAccount>> accounts() async => accountsResult;
  @override
  Future<List<NativeAlarm>> alarms() async => scheduled.values.toList();
  @override
  Future<List<NativeAlarmAction>> pendingActions() async => actions.toList();
  @override
  Future<void> acknowledgeActions(List<String> ids) async =>
      actions.removeWhere((a) => ids.contains(a.id));
  @override
  Future<NativePermissions> permissions() async =>
      NativePermissions(alarms: allowed, notifications: true, fullScreen: true);
  @override
  Future<void> cancelAlarms(List<String> ids) async {
    if (failCancellation) throw PlatformException(code: 'native_failure');
    for (final id in ids) {
      scheduled.remove(id);
    }
  }

  @override
  Future<void> scheduleAlarm(NativeAlarm alarm) async {
    if (capacity != null &&
        !scheduled.containsKey(alarm.id) &&
        scheduled.length >= capacity!) {
      throw PlatformException(code: 'capacity');
    }
    calls++;
    scheduled[alarm.id] = alarm;
  }
}

void main() {
  late AppDatabase db;
  late FakeHost host;
  late NativeAlarmScheduler scheduler;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    host = FakeHost();
    scheduler = NativeAlarmScheduler(
      db,
      host,
      clock: () => DateTime.utc(2026, 9, 6, 14),
    );
    await db.put('account', 'a', account.toJson());
    await db.put('source', 's', source('s').toJson(), owner: 'a');
    await db.replace('entry', 's', [event('s', 'meeting').toJson()]);
  });
  tearDown(() => db.close());
  test('repeat sync does not duplicate native schedules', () async {
    await scheduler.reconcile();
    await scheduler.reconcile();
    expect(host.scheduled.length, 2);
    expect(host.calls, 2);
    expect((await db.snapshot()).alarms.length, 2);
  });
  test('dismissal is durable, acknowledged after commit, and preserves next reminder', () async {
    await scheduler.reconcile();
    final id = host.scheduled.keys.first;
    host.scheduled.remove(id);
    host.actions.add(
      NativeAlarmAction(
        id: 'action',
        alarmId: id,
        kind: 'dismiss',
        atMillis: DateTime.utc(2026, 9, 6, 14, 50).millisecondsSinceEpoch,
      ),
    );
    await scheduler.reconcile();
    expect(host.scheduled.length, 1);
    expect(host.actions, isEmpty);
    await NativeAlarmScheduler(
      db,
      host,
      clock: () => DateTime.utc(2026, 9, 6, 14),
    ).reconcile();
    expect(host.scheduled.containsKey(id), false);
    expect(await db.getOne('handled', id), isNotNull);
  });
  test('snooze coinciding with next reminder is coalesced', () async {
    await scheduler.reconcile();
    final first = host.scheduled.values.first;
    final last = host.scheduled.values.last;
    host.scheduled.remove(first.id);
    host.actions.add(
      NativeAlarmAction(
        id: 'action',
        alarmId: first.id,
        kind: 'snooze',
        atMillis: first.fireAtMillis,
      ),
    );
    host.scheduled['snooze'] = NativeAlarm(
      id: 'snooze',
      entryId: first.entryId,
      title: first.title,
      subtitle: 'Snoozed',
      fireAtMillis: last.fireAtMillis,
      snoozeMinutes: 5,
      sourceIds: first.sourceIds,
      parentId: first.id,
    );
    await scheduler.reconcile();
    expect(host.scheduled.keys, [last.id]);
  });
  test(
    'independent snooze survives; switching source off cancels it too',
    () async {
      await scheduler.reconcile();
      final first = host.scheduled.values.first;
      host.scheduled['snooze'] = NativeAlarm(
        id: 'snooze',
        entryId: first.entryId,
        title: first.title,
        subtitle: 'Snoozed',
        fireAtMillis: first.fireAtMillis + 120000,
        snoozeMinutes: 5,
        sourceIds: first.sourceIds,
        parentId: first.id,
      );
      await scheduler.reconcile();
      expect(host.scheduled.containsKey('snooze'), true);
      await db.put(
        'source',
        's',
        source('s', mode: SourceMode.off).toJson(),
        owner: 'a',
      );
      await scheduler.cancelSources({'s'});
      expect(host.scheduled, isEmpty);
      await scheduler.reconcile();
      expect((await db.snapshot()).alarms, isEmpty);
    },
  );
  test(
    'capacity reports actual earliest coverage and unresolved error',
    () async {
      host.capacity = 1;
      await scheduler.reconcile();
      final state = await db.snapshot();
      expect(state.alarms.length, 1);
      expect(state.alarms.single.fireAt, DateTime.utc(2026, 9, 6, 14, 50));
      expect(state.alarmError, contains('limit'));
    },
  );
  test(
    'permission revocation does not claim cached schedules are covered',
    () async {
      await scheduler.reconcile();
      host.allowed = false;
      await scheduler.reconcile();
      expect((await db.snapshot()).alarms, isEmpty);
      expect((await db.snapshot()).alarmError, isNotNull);
    },
  );
  test(
    'resetting occurrence, series and calendar restores inherited defaults',
    () async {
      final reminders = ReminderRepository(db);
      await reminders.setOverride('meeting', 's', [30]);
      await scheduler.reconcile();
      expect(host.scheduled.length, 1);
      await reminders.resetOverride('meeting');
      await scheduler.reconcile();
      expect(host.scheduled.length, 2);
      await reminders.setOverride('meeting', 's', []);
      await scheduler.reconcile();
      expect(host.scheduled, isEmpty);
      await reminders.resetSource('s');
      await scheduler.reconcile();
      expect(host.scheduled.length, 2);
    },
  );
  test(
    'removed account cannot be restored by stale native account snapshot',
    () async {
      host.accountsResult.add(
        NativeAccount(id: 'a', email: 'me@example.com', name: 'Me'),
      );
      await db.markAccountRemoved('a');
      await db.remove('account', 'a');
      await NativeAccountRepository(db, host).restore();
      expect((await db.snapshot()).accounts, isEmpty);
    },
  );
  test(
    'earlier reminders displace later native schedules at capacity',
    () async {
      host.capacity = 1;
      await db.put(
        'settings',
        'main',
        const AppSettings(minutes: [5]).toJson(),
      );
      await scheduler.reconcile();
      expect(
        host.scheduled.values.single.fireAtMillis,
        DateTime.utc(2026, 9, 6, 14, 55).millisecondsSinceEpoch,
      );
      await db.put(
        'settings',
        'main',
        const AppSettings(minutes: [10, 5]).toJson(),
      );
      await scheduler.reconcile();
      expect(
        host.scheduled.values.single.fireAtMillis,
        DateTime.utc(2026, 9, 6, 14, 50).millisecondsSinceEpoch,
      );
    },
  );
  test(
    'handled state stays committed when later native reconciliation fails',
    () async {
      host.actions.add(
        NativeAlarmAction(
          id: 'action',
          alarmId: 'dismissed',
          kind: 'dismiss',
          atMillis: 1,
        ),
      );
      host.failCancellation = true;
      await expectLater(
        scheduler.reconcile(),
        throwsA(isA<PlatformException>()),
      );
      expect(host.actions, isEmpty);
      expect(await db.getOne('handled', 'dismissed'), isNotNull);
      expect((await db.snapshot()).alarmError, isNotNull);
    },
  );
  test('failed cancellation remains visibly unresolved', () async {
    host.failCancellation = true;
    await expectLater(
      scheduler.cancelSources({'s'}),
      throwsA(isA<PlatformException>()),
    );
    expect((await db.snapshot()).alarmError, contains('could not be canceled'));
  });
}
