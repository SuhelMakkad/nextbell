import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/application/app_services.dart';
import '../../../core/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../reminders/presentation/offset_editor.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(snapshotProvider).value;
    final entry = state?.entries.where((e) => e.id == id).firstOrNull;
    final source = entry == null ? null : state?.source(entry.sourceId);
    if (entry == null || state == null || source == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          title: 'This moment has moved',
          message:
              'It may have been changed, removed, or its calendar turned off.',
        ),
      );
    }
    final event = entry is CalendarEvent ? entry : null;
    final service = ref.read(servicesProvider);
    Future<void> edit(String ruleId, {bool series = false}) async {
      final rule = state.overrides.where((r) => r.id == ruleId).firstOrNull;
      final seriesRule = state.overrides
          .where((r) => r.id == event?.seriesKey)
          .firstOrNull;
      final inherited =
          (!series ? seriesRule?.minutes : null) ??
          source.reminderMinutes ??
          state.settings.minutes;
      final result = await showOffsetEditor(
        context,
        title: series ? 'Entire series' : 'This moment',
        current: rule?.minutes,
        inherited: inherited,
      );
      if (result != null && context.mounted) {
        await perform(
          context,
          () => service.setOverride(ruleId, source.id, result.minutes),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your next moment')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(source.name, color: Color(source.color)),
              Pill(source.accessLabel),
            ],
          ),
          const SizedBox(height: 22),
          Text(entry.title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: AppColors.indigo),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event?.allDay == true
                              ? 'All day · ${event!.allDayDate}'
                              : DateFormat.yMMMEd().format(
                                  entry.start.toLocal(),
                                ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (event?.allDay != true) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat.jm().format(entry.start.toLocal())} – ${DateFormat.jm().format(entry.end.toLocal())}',
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Your phone’s timezone · ${DateTime.now().timeZoneName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (event?.location?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(event!.location!),
            ),
          if (event?.description?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: SelectableText(
                event!.description!
                    .replaceAll(RegExp('<[^>]*>'), '')
                    .replaceAll('&nbsp;', ' ')
                    .replaceAll('&amp;', '&'),
              ),
            ),
          if (event?.joinUrl != null) ...[
            const SizedBox(height: 24),
            AsyncButton(
              label: 'Join meeting',
              icon: Icons.videocam_outlined,
              onPressed: () => openExternal(event!.joinUrl!),
            ),
          ],
          const SectionHeading('A heads-up, your way'),
          if (entry is BusyBlock)
            const Notice(
              'This is a shared busy period, which may contain multiple meetings. It follows the calendar’s reminder defaults.',
            ),
          if (source.mode != SourceMode.alarm)
            Notice(
              'Alarms are paused for this calendar. Change its mode in Accounts & Calendars.',
              onTap: () => context.push('/calendars'),
            )
          else if (event?.allDay == true)
            const Notice(
              'All-day events appear in your agenda without automatic alarms.',
            )
          else if (event?.declined == true)
            const Notice(
              'You declined this invitation, so Nextbell won’t ring for it.',
            )
          else ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in service.offsetsFor(entry, state))
                  Pill(offsetLabel(m), icon: Icons.notifications_none_rounded),
              ],
            ),
            if (event != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        event.seriesId == null
                            ? 'This event'
                            : 'This occurrence',
                      ),
                      subtitle: Text(
                        state.overrides.any((r) => r.id == event.id)
                            ? 'Custom reminders'
                            : 'Using inherited defaults',
                      ),
                      trailing: const Icon(Icons.tune_rounded),
                      onTap: () => edit(event.id),
                    ),
                    if (event.seriesKey != null) ...[
                      const Divider(),
                      ListTile(
                        title: const Text('Entire series'),
                        subtitle: const Text(
                          'Set a rhythm for recurring meetings',
                        ),
                        trailing: const Icon(Icons.repeat_rounded),
                        onTap: () => edit(event.seriesKey!, series: true),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => context.push('/calendars'),
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('Calendar settings'),
          ),
          if (event?.webUrl != null)
            TextButton(
              onPressed: () =>
                  perform(context, () => openExternal(event!.webUrl!)),
              child: const Text('Open in Google Calendar'),
            ),
        ],
      ),
    );
  }
}

Future<void> openExternal(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const ['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw StateError('This link cannot be opened safely.');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('No app could open this link.');
  }
}
