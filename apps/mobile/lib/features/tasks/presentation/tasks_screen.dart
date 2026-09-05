import '../../../l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/application/app_services.dart';
import '../../../core/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(snapshotProvider).value;
    if (state == null) return const Center(child: CircularProgressIndicator());
    final selected = state.taskLists
        .where((l) => l.selected)
        .map((l) => l.id)
        .toSet();
    final items = state.tasks
        .where((t) => selected.contains(t.listId))
        .toList();
    final open = items.where((t) => !t.completed).toList();
    final done = items.where((t) => t.completed).toList();
    return RefreshIndicator(
      onRefresh: ref.read(servicesProvider).sync.run,
      child: ListView(
        key: const PageStorageKey('tasks'),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).tasksHeadline,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              IconButton(
                tooltip: 'Choose task lists',
                onPressed: () => context.push('/calendars'),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('A place for everything you want to remember.'),
          const SizedBox(height: 22),
          const Notice(
            'Google shares task dates, but not times. Add an alarm here for a heads-up when you need it.',
            icon: Icons.lightbulb_outline_rounded,
          ),
          SectionHeading(
            'To make time for',
            trailing: Pill('${open.length} tasks'),
          ),
          if (items.isEmpty)
            EmptyState(
              title: 'A fresh page',
              message: 'Choose a Google task list in Settings to bring your tasks here.',
              action: TextButton(
                onPressed: () => context.push('/calendars'),
                child: const Text('Choose task lists'),
              ),
            ),
          for (final t in open)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskCard(key: ValueKey(t.id), task: t),
            ),
          if (done.isNotEmpty) ...[
            const SectionHeading('A little accomplished'),
            for (final t in done)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TaskCard(key: ValueKey(t.id), task: t),
              ),
          ],
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({super.key, required this.task});
  final TaskItem task;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: () => context.push('/task/${task.id}'),
        leading: Semantics(
          label: task.completed ? 'Completed' : 'Complete ${task.title}',
          button: !task.completed,
          child: IconButton(
            onPressed: task.completed
                ? null
                : () => perform(
                    context,
                    () => ref.read(servicesProvider).completeTask(task),
                  ),
            icon: AnimatedSwitcher(
              duration: Motion.duration(context, Motion.delight),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: child,
              ),
              child: Icon(
                task.completed
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: ValueKey(task.completed),
                color: task.completed
                    ? const Color(0xff299e84)
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: task.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: task.pendingCompletion
            ? const Text('Pending Google sync')
            : task.alarmAt != null
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '♧ ${DateFormat.MMMd().add_jm().format(task.alarmAt!.toLocal())}',
                ),
              )
            : task.dueDate != null
            ? Text('Due ${task.dueDate}')
            : const Text('No alarm set'),
        trailing: const Icon(Icons.chevron_right_rounded, size: 19),
      ),
    ),
  );
}

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref
        .watch(snapshotProvider)
        .value
        ?.tasks
        .where((t) => t.id == id)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('A little to-do')),
      body: task == null
          ? const EmptyState(
              title: 'Task unavailable',
              message: 'It may have been removed or its list turned off.',
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                if (task.notes?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 18),
                  Text(task.notes!),
                ],
                if (task.dueDate != null) ...[
                  const SizedBox(height: 20),
                  Pill(
                    'Google date · ${task.dueDate}',
                    icon: Icons.calendar_today_outlined,
                  ),
                ],
                const SizedBox(height: 28),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(20),
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.indigo,
                    ),
                    title: const Text('Your alarm'),
                    subtitle: Text(
                      task.alarmAt == null
                          ? 'No alarm set'
                          : DateFormat.yMMMd().add_jm().format(
                              task.alarmAt!.toLocal(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This time belongs to Nextbell. It stays tied to the same instant when you travel, and doesn’t change Google’s task date.',
                ),
                const SizedBox(height: 24),
                AsyncButton(
                  label: task.alarmAt == null
                      ? 'Give it a time'
                      : 'Change alarm time',
                  icon: Icons.schedule_rounded,
                  onPressed: task.completed
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final initial = task.alarmAt?.toLocal();
                          final chosen = await showDatePicker(
                            context: context,
                            initialDate: initial != null && initial.isAfter(now)
                                ? initial
                                : now,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: DateTime(now.year + 5),
                          );
                          if (chosen == null || !context.mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                              initial ?? now.add(const Duration(hours: 1)),
                            ),
                          );
                          if (time == null) return;
                          await ref
                              .read(servicesProvider)
                              .setTaskAlarm(
                                task,
                                DateTime(
                                  chosen.year,
                                  chosen.month,
                                  chosen.day,
                                  time.hour,
                                  time.minute,
                                ),
                              );
                        },
                ),
                if (task.alarmAt != null)
                  TextButton(
                    onPressed: () => perform(
                      context,
                      () => ref.read(servicesProvider).setTaskAlarm(task, null),
                    ),
                    child: const Text('Remove alarm'),
                  ),
                const SizedBox(height: 16),
                if (!task.completed)
                  AsyncButton(
                    label: 'Mark complete',
                    outlined: true,
                    icon: Icons.check_rounded,
                    onPressed: () =>
                        ref.read(servicesProvider).completeTask(task),
                  ),
                if (task.pendingCompletion)
                  const Notice(
                    'Completed on this phone. We’ll update Google when the connection is available.',
                  ),
              ],
            ),
    );
  }
}
