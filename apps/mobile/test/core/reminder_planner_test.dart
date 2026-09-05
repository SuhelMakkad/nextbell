import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell/features/reminders/domain/reminder_planner.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  const planner = ReminderPlanner();
  final start = DateTime.utc(2026, 9, 5, 15);
  final now = DateTime.utc(2026, 9, 5, 10);
  const source = CalendarSource(
    id: 'source',
    accountId: 'a',
    calendarId: 'calendar',
    name: 'Shared',
    accessRole: 'reader',
    mode: SourceMode.alarm,
  );
  CalendarEvent event({
    String id = 'event',
    String sourceId = 'source',
    DateTime? at,
    bool declined = false,
    String? allDay,
  }) => CalendarEvent(
    id: id,
    sourceId: sourceId,
    start: at ?? start,
    end: (at ?? start).add(const Duration(hours: 1)),
    title: 'Meeting',
    providerId: id,
    calendarId: 'calendar',
    iCalUid: 'shared-event',
    seriesId: 'series',
    declined: declined,
    allDayDate: allDay,
  );
  AppSnapshot state({
    List<CalendarSource> sources = const [source],
    List<AgendaEntry>? entries,
    List<ReminderOverride> overrides = const [],
  }) => AppSnapshot(
    sources: sources,
    entries: entries ?? [event()],
    overrides: overrides,
  );

  test('3 PM rings at 2:50 and 2:55', () {
    expect(planner.plan(state(), now).map((a) => a.fireAt), [
      DateTime.utc(2026, 9, 5, 14, 50),
      DateTime.utc(2026, 9, 5, 14, 55),
    ]);
  });
  test(
    'occurrence > series > calendar > app, including explicitly disabled',
    () {
      final calendar = source.copyWith(reminderMinutes: [30]);
      final series = ReminderOverride(
        id: event().seriesKey!,
        sourceId: source.id,
        minutes: [20],
      );
      const occurrence = ReminderOverride(
        id: 'event',
        sourceId: 'source',
        minutes: [2],
      );
      expect(
        planner.effectiveOffsets(event(), calendar, [], const AppSettings()),
        [30],
      );
      expect(
        planner.effectiveOffsets(event(), calendar, [
          series,
        ], const AppSettings()),
        [20],
      );
      expect(
        planner.effectiveOffsets(event(), calendar, [
          series,
          occurrence,
        ], const AppSettings()),
        [2],
      );
      expect(
        planner.plan(
          state(
            overrides: [
              const ReminderOverride(
                id: 'event',
                sourceId: 'source',
                minutes: [],
              ),
            ],
          ),
          now,
        ),
        isEmpty,
      );
    },
  );
  test('source modes and lost access are hard gates', () {
    for (final s in [
      source.copyWith(mode: SourceMode.off),
      source.copyWith(mode: SourceMode.showOnly),
      source.copyWith(available: false),
    ]) {
      expect(planner.plan(state(sources: [s]), now), isEmpty);
    }
  });
  test('all-day and declined events do not ring; watched events do', () {
    expect(
      planner.plan(
        state(
          entries: [
            event(allDay: '2026-09-05'),
            event(id: 'declined', declined: true),
          ],
        ),
        now,
      ),
      isEmpty,
    );
    expect(planner.plan(state(), now), hasLength(2));
  });
  test('shared copies coalesce only by real identity and instant', () {
    const second = CalendarSource(
      id: 'other',
      accountId: 'b',
      calendarId: 'calendar',
      name: 'Work copy',
      accessRole: 'reader',
      mode: SourceMode.alarm,
    );
    final alarms = planner.plan(
      state(
        sources: [source, second],
        entries: [
          event(),
          event(id: 'copy', sourceId: 'other'),
        ],
      ),
      now,
    );
    expect(alarms, hasLength(2));
    expect(alarms.first.sourceIds.toSet(), {'source', 'other'});
  });
  test('anonymous busy blocks do not merge with meetings at the same time', () {
    final busy = BusyBlock(
      id: 'busy',
      sourceId: 'source',
      start: start,
      end: start.add(const Duration(hours: 2)),
      calendarId: 'calendar',
      calendarName: 'Team',
    );
    expect(planner.plan(state(entries: [event(), busy]), now), hasLength(4));
  });
  test('handled and expired reminders are not recreated', () {
    final planned = planner.plan(state(), now);
    expect(
      planner.plan(state(), now, handled: {planned.first.id}),
      hasLength(1),
    );
    expect(
      planner.plan(state(), DateTime.utc(2026, 9, 5, 14, 52)),
      hasLength(1),
    );
    expect(planner.plan(state(), start), isEmpty);
  });
  test('travel and DST use actual instants, not wall-clock strings', () {
    tzdata.initializeTimeZones();
    final ny = tz.getLocation('America/New_York');
    final london = tz.getLocation('Europe/London');
    final before = tz.TZDateTime(ny, 2026, 3, 6, 15).toUtc();
    final after = tz.TZDateTime(ny, 2026, 3, 9, 15).toUtc();
    expect(before.hour, 20);
    expect(after.hour, 19);
    final alarms = planner.plan(
      state(entries: [event(at: after)]),
      DateTime.utc(2026, 3, 9),
    );
    expect(alarms.first.fireAt, DateTime.utc(2026, 3, 9, 18, 50));
    expect(
      tz.TZDateTime.from(
        alarms.first.fireAt,
        london,
      ).difference(tz.TZDateTime.from(after, london)).inMinutes,
      -10,
    );
  });
  test(
    'task alarms require selection, an explicit time, and an incomplete task',
    () {
      const list = TaskListSource(
        id: 'list',
        accountId: 'a',
        providerId: 'list',
        title: 'Tasks',
        selected: true,
      );
      final task = TaskItem(
        id: 'task',
        listId: 'list',
        providerId: 'task',
        title: 'Send notes',
        alarmAt: start,
      );
      expect(
        planner.plan(AppSnapshot(taskLists: [list], tasks: [task]), now),
        hasLength(1),
      );
      expect(
        planner.plan(
          AppSnapshot(
            taskLists: [list],
            tasks: [task.copyWith(pendingCompletion: true)],
          ),
          now,
        ),
        isEmpty,
      );
      expect(planner.plan(AppSnapshot(tasks: [task]), now), isEmpty);
    },
  );
}
