import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/data/app_database.dart';
import 'package:nextbell/core/data/repositories.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell/features/sync/application/sync_coordinator.dart';
import 'package:nextbell/features/reminders/data/alarm_scheduler.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

const account = ConnectedAccount(id: 'a', email: 'me@example.com', name: 'Me');
CalendarSource source(
  String id, {
  String role = 'reader',
  SourceMode mode = SourceMode.alarm,
}) => CalendarSource(
  id: id,
  accountId: account.id,
  calendarId: '$id@example.com',
  name: id,
  accessRole: role,
  mode: mode,
);
CalendarEvent event(String sourceId, String id) => CalendarEvent(
  id: id,
  sourceId: sourceId,
  start: DateTime.utc(2026, 9, 6, 15),
  end: DateTime.utc(2026, 9, 6, 16),
  title: id,
  providerId: id,
  calendarId: sourceId,
);
const taskList = TaskListSource(
  id: 'list',
  accountId: 'a',
  providerId: 'remote',
  title: 'Tasks',
  selected: true,
);

class FakeAuth implements AccountRepository {
  @override
  Future<void> restore() async {}
  @override
  Future<ConnectedAccount> connect({String? accountId}) async => account;
  @override
  Future<String> accessToken(String accountId) async => 'test-token';
  @override
  Future<void> remove(String accountId) async {}
}

class FakeAlarms implements AlarmScheduler {
  final canceled = <String>{};
  int reconciliations = 0;
  @override
  Future<void> cancelSources(Set<String> ids) async {
    canceled.addAll(ids);
  }

  @override
  Future<void> reconcile() async {
    reconciliations++;
  }

  @override
  Future<void> testAlarm() async {}
  @override
  Future<NativePermissions> permissions() async =>
      NativePermissions(alarms: true, notifications: true, fullScreen: true);
  @override
  Future<NativePermissions> requestPermissions() => permissions();
}

class FakeGateway
    implements CalendarSourceRepository, CalendarRepository, TaskRepository {
  List<CalendarSource> calendars = [];
  List<TaskListSource> taskLists = [];
  List<TaskItem> items = [];
  final eventData = <String, List<AgendaEntry>>{};
  final busyData = <String, List<BusyBlock>>{};
  final eventErrors = <String, SyncFailure>{};
  SyncFailure? listError, completionError;
  Future<void> Function()? beforeEvents, beforeDiscover, beforeTasks;
  int completions = 0;
  @override
  Future<List<CalendarSource>> discover(ConnectedAccount account) async {
    await beforeDiscover?.call();
    return calendars;
  }

  @override
  Future<List<AgendaEntry>> events(
    ConnectedAccount account,
    CalendarSource source,
    DateTime from,
    DateTime to,
  ) async {
    await beforeEvents?.call();
    if (eventErrors[source.id] case final e?) throw e;
    return eventData[source.id] ?? [];
  }

  @override
  Future<AvailabilityResult> busy(
    ConnectedAccount account,
    List<CalendarSource> sources,
    DateTime from,
    DateTime to,
  ) async => AvailabilityResult(busyData);
  @override
  Future<List<TaskListSource>> lists(ConnectedAccount account) async {
    if (listError case final e?) throw e;
    return taskLists;
  }

  @override
  Future<List<TaskItem>> tasks(
    ConnectedAccount account,
    TaskListSource list,
  ) async {
    await beforeTasks?.call();
    return items;
  }

  @override
  Future<void> complete(
    ConnectedAccount account,
    TaskListSource list,
    TaskItem task,
  ) async {
    if (completionError case final e?) throw e;
    completions++;
    items = items
        .map((t) => t.id == task.id ? t.copyWith(completed: true) : t)
        .toList();
  }
}

void main() {
  late AppDatabase db;
  late FakeGateway gateway;
  late FakeAlarms alarms;
  late SyncCoordinator sync;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeGateway();
    alarms = FakeAlarms();
    sync = SyncCoordinator(
      db,
      FakeAuth(),
      gateway,
      gateway,
      gateway,
      alarms,
      clock: () => DateTime.utc(2026, 9, 5),
    );
    await db.put('account', account.id, account.toJson());
  });
  tearDown(() async {
    await sync.waitForIdle();
    await db.close();
  });
  Future<void> seed(
    CalendarSource s, [
    List<AgendaEntry> entries = const [],
  ]) async {
    gateway.calendars.add(s);
    await db.put('source', s.id, s.toJson(), owner: account.id);
    await db.replace('entry', s.id, entries.map((e) => e.toJson()));
  }

  test('new shared and hidden sources start off; rediscovery preserves preferences', () async {
    final shared = CalendarSource(
      id: 'shared',
      accountId: 'a',
      calendarId: 'team',
      name: 'Team',
      accessRole: 'reader',
      hidden: true,
    );
    gateway.calendars = [shared];
    await sync.run();
    expect((await db.snapshot()).sources.single.mode, SourceMode.off);
    await db.put(
      'source',
      shared.id,
      shared.copyWith(mode: SourceMode.alarm, reminderMinutes: [30]).toJson(),
      owner: 'a',
    );
    await sync.run();
    final s = (await db.snapshot()).sources.single;
    expect(s.hidden, true);
    expect(s.mode, SourceMode.alarm);
    expect(s.reminderMinutes, [30]);
  });
  test('failed collection retains cache while successful empty snapshot deletes cancellations', () async {
    await seed(source('bad'), [event('bad', 'old')]);
    await seed(source('good'), [event('good', 'canceled')]);
    gateway.eventErrors['bad'] = const SyncFailure('Offline');
    await sync.run();
    final state = await db.snapshot();
    expect(state.entries.map((e) => e.id), ['old']);
    expect(state.source('bad')!.error, 'Offline');
  });
  test('task list failure does not interrupt calendar updates', () async {
    await seed(source('good'));
    gateway.eventData['good'] = [event('good', 'new')];
    gateway.listError = const SyncFailure('Reconnect tasks');
    await sync.run();
    expect((await db.snapshot()).entries.single.id, 'new');
  });
  test(
    'permission downgrade clears private details and pauses alarms',
    () async {
      await seed(source('shared'), [event('shared', 'private title')]);
      gateway.calendars = [source('shared', role: 'freeBusyReader')];
      await sync.run();
      final state = await db.snapshot();
      expect(state.source('shared')!.mode, SourceMode.showOnly);
      expect(state.entries, isEmpty);
      expect(alarms.canceled, contains('shared'));
    },
  );
  test(
    'confirmed access loss clears cached details and cancels alarms',
    () async {
      await seed(source('lost'), [event('lost', 'private')]);
      gateway.eventErrors['lost'] = const SyncFailure('Gone', accessLost: true);
      await sync.run();
      expect((await db.snapshot()).entries, isEmpty);
      expect((await db.snapshot()).source('lost')!.available, false);
      expect(alarms.canceled, contains('lost'));
    },
  );
  test('busy block split replaces old block; failed neighboring source retains cache', () async {
    BusyBlock block(String s, int hour) => BusyBlock(
      id: '$s$hour',
      sourceId: s,
      start: DateTime.utc(2026, 9, 6, hour),
      end: DateTime.utc(2026, 9, 6, hour + 1),
      calendarId: s,
      calendarName: s,
    );
    await seed(source('busy', role: 'freeBusyReader'), [block('busy', 9)]);
    await seed(source('failed', role: 'freeBusyReader'), [block('failed', 9)]);
    gateway.busyData['busy'] = [block('busy', 10), block('busy', 12)];
    await sync.run();
    expect(
      (await db.snapshot()).entries.map((e) => e.id),
      unorderedEquals(['busy10', 'busy12', 'failed9']),
    );
    gateway.busyData['busy'] = [];
    await sync.run();
    expect((await db.snapshot()).entries.map((e) => e.id), ['failed9']);
  });
  test(
    'turning off during fetch cannot commit stale events or revert mode',
    () async {
      final s = source('watched');
      await seed(s);
      gateway.eventData[s.id] = [event(s.id, 'in flight')];
      gateway.beforeEvents = () => db.put(
        'source',
        s.id,
        s.copyWith(mode: SourceMode.off).toJson(),
        owner: 'a',
      );
      await sync.run();
      expect((await db.snapshot()).entries, isEmpty);
      expect((await db.snapshot()).sources.single.mode, SourceMode.off);
    },
  );
  test(
    'removal during discovery cannot resurrect account or its data',
    () async {
      await seed(source('watched'));
      gateway.beforeDiscover = () async {
        await db.markAccountRemoved('a');
        await db.remove('account', 'a');
        await db.deleteOwner('a');
      };
      await sync.run();
      final state = await db.snapshot();
      expect(state.accounts, isEmpty);
      expect(state.sources, isEmpty);
      expect(state.entries, isEmpty);
    },
  );
  test(
    'offline completion survives and is flushed even after deselection',
    () async {
      gateway.taskLists = [taskList];
      await db.put('taskList', taskList.id, taskList.toJson(), owner: 'a');
      final instant = DateTime.utc(2026, 9, 6, 16);
      final item = TaskItem(
        id: 't',
        listId: 'list',
        providerId: 'remote-t',
        title: 'Ship',
        alarmAt: instant,
        completed: true,
        pendingCompletion: true,
      );
      await db.put('task', 't', item.toJson(), owner: 'list');
      gateway.items = [
        item.copyWith(completed: false, pendingCompletion: false),
      ];
      gateway.completionError = const SyncFailure('Offline', transient: true);
      await sync.run();
      expect((await db.snapshot()).tasks.single.pendingCompletion, true);
      await db.put('taskList', 'list', {
        ...taskList.toJson(),
        'selected': false,
      }, owner: 'a');
      gateway.completionError = null;
      await sync.run();
      final t = (await db.snapshot()).tasks.single;
      expect(t.pendingCompletion, false);
      expect(t.completed, true);
      expect(t.alarmAt, instant);
      expect(gateway.completions, 1);
    },
  );
  test(
    'Google task date changes preserve explicitly chosen alarm instant',
    () async {
      gateway.taskLists = [taskList];
      await db.put('taskList', 'list', taskList.toJson(), owner: 'a');
      final at = DateTime.utc(2026, 9, 7, 12);
      await db.put(
        'task',
        't',
        TaskItem(
          id: 't',
          listId: 'list',
          providerId: 'p',
          title: 'Task',
          dueDate: '2026-09-06',
          alarmAt: at,
        ).toJson(),
        owner: 'list',
      );
      gateway.items = [
        const TaskItem(
          id: 't',
          listId: 'list',
          providerId: 'p',
          title: 'Task',
          dueDate: '2026-09-08',
        ),
      ];
      await sync.run();
      final t = (await db.snapshot()).tasks.single;
      expect(t.dueDate, '2026-09-08');
      expect(t.alarmAt, at);
    },
  );
  test('simultaneous refreshes share one running operation', () async {
    final gate = Completer<void>();
    int calls = 0;
    gateway.beforeDiscover = () async {
      calls++;
      await gate.future;
    };
    final first = sync.run();
    final second = sync.run();
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });
  test('access changes never enable an off calendar', () async {
    await seed(source('off', mode: SourceMode.off));
    gateway.calendars = [source('off', role: 'freeBusyReader')];
    await sync.run();
    expect((await db.snapshot()).sources.single.mode, SourceMode.off);
  });
}
