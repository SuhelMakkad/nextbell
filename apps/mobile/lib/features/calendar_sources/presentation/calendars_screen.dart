import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/application/app_services.dart';
import '../../../core/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../reminders/presentation/offset_editor.dart';

class CalendarsScreen extends ConsumerWidget {
  const CalendarsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(snapshotProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts & calendars'),
        actions: [
          IconButton(
            tooltip: 'Refresh discovery',
            onPressed: () => perform(
              context,
              ref.read(servicesProvider).sync.run,
              success: 'Calendar discovery refreshed.',
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
              children: [
                Text(
                  'Bring your days together.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your calendars and the ones shared with you. Choose what appears here, and what deserves a bell.',
                ),
                const SizedBox(height: 20),
                if (state.alarmError != null)
                  Notice(
                    state.alarmError!,
                    onTap: () => context.push('/alarm-settings'),
                  ),
                if (state.backgroundError != null)
                  Notice(state.backgroundError!),
                if (state.demo)
                  const Notice(
                    'This is a demo. Explore the controls; no Google data or device alarms will change.',
                  ),
                for (final account in state.accounts) ...[
                  SectionHeading(
                    account.name,
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Account options',
                      onSelected: (value) async {
                        if (value == 'tasks') {
                          await perform(
                            context,
                            () => ref
                                .read(servicesProvider)
                                .enableTasks(account.id),
                          );
                          return;
                        }
                        if (value == 'reconnect') {
                          await perform(
                            context,
                            () => ref
                                .read(servicesProvider)
                                .connect(accountId: account.id),
                          );
                        }
                        if (value == 'remove' &&
                            context.mounted &&
                            await confirm(
                              context,
                              'Remove this account?',
                              'Its Nextbell events, tasks, settings, and alarms will be removed. Other phones update when connected. Google content stays unchanged.',
                              action: 'Remove',
                            )) {
                          if (context.mounted) {
                            await perform(
                              context,
                              () => ref
                                  .read(servicesProvider)
                                  .removeAccount(account.id),
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        if (ref.read(servicesProvider).cloud != null)
                          const PopupMenuItem(
                            value: 'tasks',
                            child: Text('Enable Google Tasks'),
                          ),
                        PopupMenuItem(
                          value: 'reconnect',
                          child: Text('Reconnect Google'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from Nextbell'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      account.email,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (account.error != null) ...[
                    Notice(account.error!),
                    const SizedBox(height: 12),
                  ],
                  for (final source in state.sources.where(
                    (s) => s.accountId == account.id,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _SourceCard(source: source, state: state),
                    ),
                  if (state.taskLists.any(
                    (l) => l.accountId == account.id,
                  )) ...[
                    const SizedBox(height: 10),
                    Text(
                      'TASK LISTS',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final list in state.taskLists.where(
                            (l) => l.accountId == account.id,
                          ))
                            SwitchListTile.adaptive(
                              title: Text(list.title),
                              subtitle: Text(
                                list.error ?? 'Alarm times are set per task.',
                              ),
                              value: list.selected,
                              onChanged: (v) => perform(
                                context,
                                () => ref
                                    .read(servicesProvider)
                                    .selectTaskList(list, v),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                AsyncButton(
                  label: 'Add a Google account',
                  outlined: true,
                  icon: Icons.add_rounded,
                  onPressed: () => ref.read(servicesProvider).connect(),
                ),
                const SizedBox(height: 24),
                const Notice(
                  'Missing a calendar? Add or subscribe to it in Google Calendar first, then refresh here. Shared calendars don’t always appear in your Google list automatically.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Changes here only affect Nextbell. Google sharing permissions, calendar visibility, and existing Google reminders stay the same.',
                ),
                if (!state.settings.onboarded) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.push('/alarm-settings'),
                    child: const Text('Continue to alarm setup →'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SourceCard extends ConsumerStatefulWidget {
  const _SourceCard({required this.source, required this.state});
  final CalendarSource source;
  final AppSnapshot state;
  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool saving = false;
  int delight = 0;
  Future<void> change(SourceMode? mode) async {
    if (mode == null || mode == widget.source.mode || saving) return;
    if (mode == SourceMode.alarm && widget.source.availabilityOnly) {
      if (!await confirm(
        context,
        'Ring for busy periods?',
        'This calendar shares times only. A busy block may combine several meetings. Nextbell will ring before the block starts without a meeting title or join link.',
        action: 'Enable busy alarms',
      )) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => saving = true);
    final ok = await perform(
      context,
      () => ref.read(servicesProvider).setSourceMode(widget.source, mode),
    );
    if (mounted) {
      setState(() {
        saving = false;
        if (ok && mode == SourceMode.alarm) delight++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(s.color).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    s.availabilityOnly
                        ? Icons.timelapse_rounded
                        : Icons.calendar_month_rounded,
                    color: Color(s.color),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (s.mode == SourceMode.alarm)
                  BellDelight(
                    trigger: delight,
                    size: 20,
                    color: AppColors.indigo,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill(s.accessLabel, color: Color(s.color)),
                if (s.primary) const Pill('Primary'),
                if (s.primary && !widget.state.settings.onboarded)
                  const Pill('Suggested'),
                if (s.hidden)
                  const Pill(
                    'Hidden in Google',
                    icon: Icons.visibility_off_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SourceMode>(
              key: ValueKey('${s.id}-${s.mode}'),
              initialValue: s.mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'In Nextbell'),
              items: const [
                DropdownMenuItem(value: SourceMode.off, child: Text('Off')),
                DropdownMenuItem(
                  value: SourceMode.showOnly,
                  child: Text('Show only'),
                ),
                DropdownMenuItem(
                  value: SourceMode.alarm,
                  child: Text('Show and alarm'),
                ),
              ],
              onChanged: saving || !s.available ? null : change,
            ),
            AnimatedSize(
              duration: Motion.duration(context, Motion.standard),
              curve: Curves.easeOutCubic,
              child: s.mode == SourceMode.alarm
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Calendar reminders'),
                        subtitle: Text(
                          s.reminderMinutes == null
                              ? 'App defaults · ${formatOffsets(widget.state.settings.minutes)}'
                              : formatOffsets(s.reminderMinutes!),
                        ),
                        trailing: const Icon(Icons.tune_rounded, size: 20),
                        onTap: () async {
                          final result = await showOffsetEditor(
                            context,
                            title: '${s.name} reminders',
                            current: s.reminderMinutes,
                            inherited: widget.state.settings.minutes,
                          );
                          if (result != null && context.mounted) {
                            await perform(
                              context,
                              () => ref
                                  .read(servicesProvider)
                                  .setCalendarOffsets(s, result.minutes),
                            );
                          }
                        },
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (s.availabilityOnly)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Busy periods only. Titles and individual meeting details aren’t shared.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (s.lastSync != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Refreshed ${DateFormat.MMMd().add_jm().format(s.lastSync!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (s.mode == SourceMode.alarm && !widget.state.demo)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${widget.state.alarms.where((a) => a.sourceIds.contains(s.id)).length} native alarms scheduled · See alarm settings for coverage and any limits.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (s.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  s.error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Reset ${s.name} reminders?',
                    'Restore inherited defaults and remove this calendar’s series and occurrence overrides. Its visibility mode stays the same.',
                  )) {
                    if (context.mounted) {
                      await perform(
                        context,
                        () => ref.read(servicesProvider).resetCalendar(s),
                      );
                    }
                  }
                },
                child: const Text('Reset calendar reminders'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
