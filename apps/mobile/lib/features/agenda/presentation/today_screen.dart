import 'dart:async';

import '../../../l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/application/app_services.dart';
import '../../../core/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../reminders/presentation/offset_editor.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});
  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int day = 0;
  Timer? minuteTick;
  @override
  void initState() {
    super.initState();
    minuteTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    minuteTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(snapshotProvider);
    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const EmptyState(
        title: 'Let’s try that again',
        message: 'Restart Nextbell to reopen your local calendar.',
      ),
      data: (state) {
        final now = DateTime.now();
        final selected = DateTime(now.year, now.month, now.day + day);
        final entries = state.entries.where((e) {
          final source = state.source(e.sourceId);
          if (source == null ||
              !source.available ||
              source.mode == SourceMode.off) {
            return false;
          }
          if (e is CalendarEvent && e.allDay) {
            final start = DateTime.parse(e.allDayDate!);
            final end = DateTime.parse(
              e.endDate ?? e.allDayDate!,
            ).add(e.endDate == null ? const Duration(days: 1) : Duration.zero);
            return !selected.isBefore(start) && selected.isBefore(end);
          }
          return e.start.toLocal().isBefore(
                selected.add(const Duration(days: 1)),
              ) &&
              e.end.toLocal().isAfter(selected);
        }).toList()..sort((a, b) => a.start.compareTo(b.start));
        final upcoming =
            state.entries
                .where(
                  (e) =>
                      e.start.isAfter(now) &&
                      !(e is CalendarEvent && (e.allDay || e.declined)) &&
                      state.source(e.sourceId)?.mode != SourceMode.off &&
                      (state.source(e.sourceId)?.available ?? false),
                )
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start));
        return RefreshIndicator(
          onRefresh: ref.read(servicesProvider).sync.run,
          child: ListView(
            key: const PageStorageKey('agenda'),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            children: [
              Row(
                children: [
                  const BrandMark(),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Accounts & calendars',
                    onPressed: () => context.push('/calendars'),
                    icon: CircleAvatar(
                      radius: 19,
                      backgroundColor: AppColors.mint,
                      child: Text(
                        state.accounts.firstOrNull?.name.characters.firstOrNull
                                ?.toUpperCase() ??
                            'N',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xff356657),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                DateFormat('EEEE, MMMM d').format(now).toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).agendaHeadline,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 7),
              Text(AppLocalizations.of(context).agendaSubtitle),
              const SizedBox(height: 24),
              if (state.demo) ...[
                Notice(
                  'Demo preview · Sample data. No alarms are scheduled.',
                  icon: Icons.auto_awesome_outlined,
                  onTap: () => ref.read(demoModeProvider.notifier).set(false),
                ),
                const SizedBox(height: 16),
              ],
              if (state.alarmError != null) ...[
                Notice(
                  state.alarmError!,
                  onTap: () => context.push('/alarm-settings'),
                ),
                const SizedBox(height: 16),
              ],
              if (state.syncError != null) ...[
                Notice(
                  state.syncError!,
                  onTap: () => context.push('/calendars'),
                ),
                const SizedBox(height: 16),
              ],
              if (upcoming.isNotEmpty)
                Entrance(
                  child: _NextCard(entry: upcoming.first, state: state),
                )
              else
                Card(
                  child: EmptyState(
                    title: 'A little breathing room',
                    message: 'Your next moment will appear here.',
                    action: TextButton(
                      onPressed: () => context.push('/calendars'),
                      child: const Text('Choose calendars'),
                    ),
                  ),
                ),
              SectionHeading(
                'On your calendar',
                trailing: Text(
                  '${entries.length} ${entries.length == 1 ? 'moment' : 'moments'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: day > -7 ? () => setState(() => day--) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() => day = 0),
                      child: Text(
                        day == 0
                            ? 'Today'
                            : DateFormat('EEE, MMM d').format(selected),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    onPressed: day < 89 ? () => setState(() => day++) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              if (entries.isEmpty)
                const EmptyState(
                  title: 'Nothing on the calendar',
                  message: 'Room for whatever comes next.',
                )
              else
                ...entries.indexed.map(
                  (pair) => Padding(
                    key: ValueKey(pair.$2.id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Entrance(
                      key: ValueKey(pair.$2.id),
                      index: pair.$1,
                      child: AnimatedSize(
                        duration: Motion.duration(context, Motion.standard),
                        child: EventCard(entry: pair.$2, state: state),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state.syncing
                          ? Icons.sync_rounded
                          : Icons.cloud_done_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        state.syncing
                            ? 'Refreshing your day…'
                            : state.lastSync == null
                            ? 'Pull down to refresh'
                            : 'Last synced ${DateFormat.jm().format(state.lastSync!.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NextCard extends ConsumerWidget {
  const _NextCard({required this.entry, required this.state});
  final AgendaEntry entry;
  final AppSnapshot state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = entry.start.difference(DateTime.now()).inMinutes;
    final offsets = ref.read(servicesProvider).offsetsFor(entry, state);
    return PressFeedback(
      child: Material(
        color: const Color(0xff282145),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () => context.push('/event/${entry.id}'),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text(
                        'NEXT UP',
                        style: TextStyle(
                          color: Color(0xffded8ff),
                          fontSize: 10,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.north_east_rounded,
                      color: Color(0xffcfc6ff),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.6,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${DateFormat.jm().format(entry.start.toLocal())}  ·  ${minutes < 60 ? 'in $minutes min' : 'in ${minutes ~/ 60}h ${minutes % 60}m'}',
                  style: const TextStyle(
                    color: Color(0xffc6bfdc),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 23),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (offsets.isEmpty)
                      const Text(
                        'Show only · no alarm',
                        style: TextStyle(
                          color: Color(0xffc6bfdc),
                          fontSize: 12,
                        ),
                      )
                    else
                      ...offsets.map(
                        (m) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.notifications_none_rounded,
                                color: Color(0xffcfc6ff),
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                offsetLabel(m),
                                style: const TextStyle(
                                  color: Color(0xffe4deff),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EventCard extends ConsumerWidget {
  const EventCard({super.key, required this.entry, required this.state});
  final AgendaEntry entry;
  final AppSnapshot state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = state.source(entry.sourceId)!;
    final allDay = entry is CalendarEvent && (entry as CalendarEvent).allDay;
    final reminder = ref.read(servicesProvider).offsetsFor(entry, state);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/event/${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(source.color),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 13),
              SizedBox(
                width: 55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allDay
                          ? 'All day'
                          : DateFormat('h:mm').format(entry.start.toLocal()),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (!allDay)
                      Text(
                        DateFormat('a').format(entry.start.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      source.name,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (entry is BusyBlock)
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                          'Availability only',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xffa4773c),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (reminder.isNotEmpty && !allDay)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
