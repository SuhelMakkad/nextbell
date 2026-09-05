import '../../../core/models.dart';

/// Pure planning: all temporal arithmetic is on instants, never display times.
class ReminderPlanner {
  const ReminderPlanner();

  List<int> effectiveOffsets(
    AgendaEntry entry,
    CalendarSource source,
    List<ReminderOverride> overrides,
    AppSettings settings,
  ) {
    final rules = {for (final r in overrides) r.id: r.minutes};
    if (entry is CalendarEvent) {
      return rules[entry.id] ??
          rules[entry.seriesKey] ??
          source.reminderMinutes ??
          settings.minutes;
    }
    return source.reminderMinutes ?? settings.minutes;
  }

  List<AlarmSpec> plan(
    AppSnapshot state,
    DateTime now, {
    Set<String> handled = const {},
  }) {
    final planned = <String, AlarmSpec>{};
    if (state.demo || !state.deviceAlarmsEnabled) return [];
    for (final entry in state.entries) {
      final source = state.source(entry.sourceId);
      if (source == null ||
          !source.available ||
          source.mode != SourceMode.alarm) {
        continue;
      }
      if (entry is CalendarEvent && (entry.allDay || entry.declined)) continue;
      for (final minutes in effectiveOffsets(
        entry,
        source,
        state.overrides,
        state.settings,
      ).toSet()) {
        final when = entry.start.toUtc().subtract(Duration(minutes: minutes));
        if (!when.isAfter(now.toUtc())) continue;
        final id = stableId([entry.canonicalId, when.toIso8601String()]);
        if (handled.contains(id)) continue;
        final existing = planned[id];
        planned[id] = AlarmSpec(
          id: id,
          entryId: existing?.entryId ?? entry.id,
          title: existing?.title ?? entry.title,
          subtitle: minutes == 0
              ? 'Starting now'
              : '$minutes min before · ${source.name}',
          fireAt: when,
          sourceIds: {...?existing?.sourceIds, source.id}.toList(),
          snoozeMinutes: state.settings.snoozeMinutes,
        );
      }
    }
    final selectedLists = state.taskLists
        .where((l) => l.selected)
        .map((l) => l.id)
        .toSet();
    for (final task in state.tasks) {
      if (!selectedLists.contains(task.listId) ||
          task.completed ||
          task.pendingCompletion ||
          task.alarmAt == null ||
          !task.alarmAt!.isAfter(now.toUtc())) {
        continue;
      }
      final id = stableId([
        'task',
        task.id,
        task.alarmAt!.toUtc().toIso8601String(),
      ]);
      if (handled.contains(id)) continue;
      planned[id] = AlarmSpec(
        id: id,
        entryId: task.id,
        title: task.title,
        subtitle: 'Your task reminder',
        fireAt: task.alarmAt!.toUtc(),
        sourceIds: [task.listId],
        snoozeMinutes: state.settings.snoozeMinutes,
      );
    }
    return planned.values.toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }
}
