import 'package:nextbell_platform/nextbell_platform.dart';

import '../models.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../../features/reminders/data/alarm_scheduler.dart';

final demoAccount = ConnectedAccount(
  id: 'demo',
  email: 'alex@example.com',
  name: 'Alex',
);
List<CalendarSource> demoSources() => [
  CalendarSource(
    id: 'work',
    accountId: 'demo',
    calendarId: 'work',
    name: 'Work',
    accessRole: 'owner',
    primary: true,
    mode: SourceMode.alarm,
  ),
  CalendarSource(
    id: 'team',
    accountId: 'demo',
    calendarId: 'team',
    name: 'Product team',
    accessRole: 'reader',
    color: 0xff299e84,
    mode: SourceMode.alarm,
  ),
  CalendarSource(
    id: 'studio',
    accountId: 'demo',
    calendarId: 'studio',
    name: 'Studio availability',
    accessRole: 'freeBusyReader',
    color: 0xffdf924a,
    mode: SourceMode.showOnly,
  ),
];
List<AgendaEntry> demoEntries() {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day, now.hour + 1).toUtc();
  return [
    CalendarEvent(
      id: 'design',
      sourceId: 'work',
      start: first,
      end: first.add(const Duration(minutes: 45)),
      title: 'Design sync',
      providerId: 'design',
      calendarId: 'work',
      iCalUid: 'design@example.com',
      seriesId: 'weekly-design',
      description: 'A little space to share ideas, explore the details, and make the next thing better.',
      location: 'The design room',
    ),
    CalendarEvent(
      id: 'coffee',
      sourceId: 'team',
      start: first.add(const Duration(hours: 2)),
      end: first.add(const Duration(hours: 2, minutes: 30)),
      title: 'Coffee & catch-up',
      providerId: 'coffee',
      calendarId: 'team',
      iCalUid: 'coffee@example.com',
      description: 'Bring your favorite cup. Leave with a fresh perspective.',
    ),
    BusyBlock(
      id: 'studio-block',
      sourceId: 'studio',
      start: first.add(const Duration(hours: 3)),
      end: first.add(const Duration(hours: 4)),
      calendarId: 'studio',
      calendarName: 'Studio availability',
    ),
    CalendarEvent(
      id: 'wrap',
      sourceId: 'work',
      start: first.add(const Duration(hours: 5)),
      end: first.add(const Duration(hours: 5, minutes: 30)),
      title: 'Weekly wrap-up',
      providerId: 'wrap',
      calendarId: 'work',
      iCalUid: 'wrap@example.com',
    ),
  ];
}

List<TaskItem> demoTasks() => [
  TaskItem(
    id: 'notes',
    listId: 'personal-tasks',
    providerId: 'notes',
    title: 'Send the project notes',
    notes: 'A quick recap for everyone who helped.',
    alarmAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
  ),
  const TaskItem(
    id: 'package',
    listId: 'personal-tasks',
    providerId: 'package',
    title: 'Pick up a package',
  ),
  const TaskItem(
    id: 'book',
    listId: 'personal-tasks',
    providerId: 'book',
    title: 'Make time for a good book',
  ),
];
const demoList = TaskListSource(
  id: 'personal-tasks',
  accountId: 'demo',
  providerId: 'personal',
  title: 'My tasks',
  selected: true,
);

Future<void> seedDemo(AppDatabase db) async {
  await db.put('account', demoAccount.id, demoAccount.toJson());
  for (final s in demoSources()) {
    await db.put('source', s.id, s.toJson(), owner: s.accountId);
  }
  for (final e in demoEntries()) {
    await db.put('entry', e.id, e.toJson(), owner: e.sourceId);
  }
  await db.put('taskList', demoList.id, demoList.toJson(), owner: 'demo');
  for (final t in demoTasks()) {
    await db.put('task', t.id, t.toJson(), owner: t.listId);
  }
  await db.put('settings', 'main', const AppSettings(onboarded: true).toJson());
  await db.health({
    'demo': true,
    'lastSync': DateTime.now().toUtc().toIso8601String(),
  });
}

class DemoAccountRepository implements AccountRepository {
  @override
  Future<void> restore() async {}
  @override
  Future<ConnectedAccount> connect({String? accountId}) async => demoAccount;
  @override
  Future<String> accessToken(String accountId) async =>
      throw StateError('Demo never accesses Google.');
  @override
  Future<void> remove(String accountId) async {}
}

class DemoGateway
    implements CalendarSourceRepository, CalendarRepository, TaskRepository {
  final _entries = demoEntries();
  final _completed = <String>{};
  @override
  Future<List<CalendarSource>> discover(ConnectedAccount account) async =>
      demoSources();
  @override
  Future<List<AgendaEntry>> events(
    ConnectedAccount a,
    CalendarSource s,
    DateTime from,
    DateTime to,
  ) async => _entries.where((e) => e.sourceId == s.id).toList();
  @override
  Future<AvailabilityResult> busy(
    ConnectedAccount a,
    List<CalendarSource> s,
    DateTime from,
    DateTime to,
  ) async => AvailabilityResult({
    for (final source in s)
      source.id: _entries
          .whereType<BusyBlock>()
          .where((e) => e.sourceId == source.id)
          .toList(),
  });
  @override
  Future<List<TaskListSource>> lists(ConnectedAccount account) async => [
    demoList,
  ];
  @override
  Future<List<TaskItem>> tasks(ConnectedAccount a, TaskListSource l) async =>
      demoTasks()
          .map((t) => t.copyWith(completed: _completed.contains(t.id)))
          .toList();
  @override
  Future<void> complete(
    ConnectedAccount a,
    TaskListSource l,
    TaskItem t,
  ) async {
    _completed.add(t.id);
  }
}

class DemoAlarmScheduler implements AlarmScheduler {
  DemoAlarmScheduler(this.db);
  final AppDatabase db;
  @override
  Future<NativePermissions> permissions() async =>
      NativePermissions(alarms: false, notifications: false, fullScreen: false);
  @override
  Future<NativePermissions> requestPermissions() => permissions();
  @override
  Future<void> cancelSources(Set<String> ids) async {}
  @override
  Future<void> reconcile() async {}
  @override
  Future<void> testAlarm() async =>
      throw StateError('Leave the demo to test a real alarm.');
}
