import '../../../l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/application/app_services.dart';
import '../../../core/config/public_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../reminders/presentation/offset_editor.dart';
import '../../agenda/presentation/event_detail_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(snapshotProvider).value;
    if (state == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          AppLocalizations.of(context).settingsHeadline,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text('Your calendars. Your timing. Your kind of calm.'),
        const SectionHeading('Connected to your day'),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            leading: const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.indigo,
            ),
            title: const Text('Accounts & calendars'),
            subtitle: Text(
              '${state.accounts.length} accounts · ${state.sources.length} calendars',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/calendars'),
          ),
        ),
        const SectionHeading('A rhythm that fits'),
        if (ref.read(servicesProvider).cloud != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_rounded),
              title: const Text('Devices & sync'),
              subtitle: const Text(
                'Cloud updates, offline changes, and alarm coverage',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/devices'),
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(AppLocalizations.of(context).alarmsAndReminders),
                subtitle: Text(formatOffsets(state.settings.minutes)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/alarm-settings'),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                subtitle: const Text(
                  'Animations follow your Reduce Motion setting',
                ),
                trailing: DropdownButton<String>(
                  value: state.settings.theme,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('System')),
                    DropdownMenuItem(value: 'light', child: Text('Light')),
                    DropdownMenuItem(value: 'dark', child: Text('Dark')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      perform(
                        context,
                        () => ref
                            .read(servicesProvider)
                            .saveSettings(state.settings.copyWith(theme: v)),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SectionHeading('Good to know'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Privacy & how it works'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/about'),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(state.demo ? 'Leave demo' : 'Explore the demo'),
                subtitle: const Text('Sample data, no real alarms'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  ref.read(demoModeProvider.notifier).set(!state.demo);
                  context.go('/today');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        const Center(child: BrandMark(size: 30)),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'A little ahead of what’s next.\nVersion 1.0.0',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});
  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
  int delight = 0;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(snapshotProvider).value;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final service = ref.read(servicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).alarmsAndReminders),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Just the right\nheads-up.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.indigo.withValues(alpha: .1),
                ),
                child: BellDelight(
                  trigger: delight,
                  size: 38,
                  color: AppColors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  title: const Text('Default reminders'),
                  subtitle: Text(formatOffsets(state.settings.minutes)),
                  trailing: const Icon(Icons.tune_rounded),
                  onTap: () async {
                    final result = await showOffsetEditor(
                      context,
                      title: 'Your default reminders',
                      current: state.settings.minutes,
                      inherited: const [10, 5],
                      allowInherit: false,
                    );
                    if (result != null && context.mounted) {
                      await perform(
                        context,
                        () => service.saveSettings(
                          state.settings.copyWith(minutes: result.minutes),
                        ),
                      );
                    }
                  },
                ),
                const Divider(indent: 20, endIndent: 20),
                ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  title: const Text('Snooze for'),
                  trailing: DropdownButton<int>(
                    value: state.settings.snoozeMinutes,
                    underline: const SizedBox(),
                    items: [
                      for (final m in [1, 3, 5, 10, 15])
                        DropdownMenuItem(value: m, child: Text('$m min')),
                    ],
                    onChanged: (m) {
                      if (m != null) {
                        perform(
                          context,
                          () => service.saveSettings(
                            state.settings.copyWith(snoozeMinutes: m),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Calendar, series, and individual event settings can override these defaults. Changing a default updates future alarms that inherit it.',
          ),
          const SectionHeading('Ready when you are'),
          if (state.demo)
            const Notice(
              'Demo mode never schedules alarms. Leave the demo to test a real alarm.',
            )
          else ...[
            FutureBuilder(
              future: service.alarms.permissions(),
              builder: (context, snapshot) {
                final p = snapshot.data;
                return Card(
                  child: Column(
                    children: [
                      _PermissionRow(
                        'Alarms',
                        p?.alarms,
                        () => perform(
                          context,
                          () => service.host.openSettings('alarms'),
                        ),
                      ),
                      _PermissionRow(
                        'Notifications',
                        p?.notifications,
                        () => perform(
                          context,
                          () => service.host.openSettings('notifications'),
                        ),
                      ),
                      _PermissionRow(
                        'Lock-screen presentation',
                        p?.fullScreen,
                        () => perform(
                          context,
                          () => service.host.openSettings('fullscreen'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            AsyncButton(
              label: 'Allow alarms',
              icon: Icons.notifications_active_outlined,
              onPressed: () async {
                await service.alarms.requestPermissions();
                await service.alarms.reconcile();
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 10),
            AsyncButton(
              label: 'Test an alarm in 10 seconds',
              outlined: true,
              icon: Icons.play_arrow_rounded,
              onPressed: () async {
                await service.alarms.testAlarm();
                if (context.mounted) {
                  setState(() => delight++);
                  showMessage(
                    context,
                    'Your test alarm will ring in 10 seconds.',
                  );
                }
              },
            ),
          ],
          if (state.alarmError != null) ...[
            const SizedBox(height: 16),
            Notice(state.alarmError!),
          ],
          const SectionHeading('On this phone'),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(20),
              title: Text('${state.alarms.length} alarms scheduled'),
              subtitle: Text(
                state.alarms.isEmpty
                    ? 'Enabled future reminders will appear here.'
                    : 'Last scheduled alarm: ${DateFormat.MMMd().add_jm().format(state.alarms.last.fireAt.toLocal())}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          AsyncButton(
            label: 'Check & repair schedules',
            outlined: true,
            icon: Icons.refresh_rounded,
            onPressed: service.alarms.reconcile,
          ),
          const SizedBox(height: 20),
          const Notice(
            'Downloaded alarms can ring offline. Changes in Google arrive when Nextbell syncs; background refresh timing is controlled by your phone.',
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () async {
              if (await confirm(
                context,
                'Reset all reminder settings?',
                'Restore 10- and 5-minute defaults, a 5-minute snooze, and remove calendar, series, and occurrence overrides. Calendar selections and task alarm times stay as they are.',
              )) {
                if (context.mounted) {
                  await perform(context, service.resetAllReminders);
                }
              }
            },
            child: const Text('Reset reminder settings'),
          ),
          if (!state.settings.onboarded) ...[
            const SizedBox(height: 20),
            AsyncButton(
              label: 'Let’s meet the day →',
              onPressed: () async {
                await service.finishOnboarding();
                if (context.mounted) context.go('/today');
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow(this.title, this.allowed, this.open);
  final String title;
  final bool? allowed;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    onTap: open,
    trailing: Icon(
      allowed == true ? Icons.check_circle_rounded : Icons.open_in_new_rounded,
      color: allowed == true
          ? const Color(0xff299e84)
          : Theme.of(context).colorScheme.outline,
      size: 22,
    ),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & how it works')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const BrandMark(),
        const SectionHeading('Your time is personal.'),
        const Text(
          'Nextbell reads the calendars and task lists you select using your Google permissions. The Android private beta synchronizes this data through Nextbell cloud; the iOS prototype connects directly to Google. Completing a task updates it in Google. Calendar content, sharing, and Google reminder settings are never edited.',
        ),
        const SectionHeading('On your phone'),
        const Text(
          'The Android beta stores selected Google data, reminder rules and device sync health in Nextbell cloud, with an offline copy on your phone. Server Google tokens are encrypted; sign-in uses Firebase Authentication. Snooze and Dismiss stay on this phone. The iOS prototype keeps credentials in Keychain. There are no ads or analytics. Alarm titles may appear on your lock screen.',
        ),
        const SectionHeading('You’re in control'),
        const Text(
          'Remove a connected account in Settings to remove its Nextbell data and cancel its alarms. In the Android beta, Devices & sync also provides sign-out and cloud account deletion. Other phones apply removal when they reconnect. You can revoke Google access separately in your Google account. Demo data is temporary and never schedules real alarms.',
        ),
        TextButton(
          onPressed: () => perform(
            context,
            () => openExternal('https://myaccount.google.com/permissions'),
          ),
          child: const Text('Manage Google access ↗'),
        ),
        const SectionHeading('About reliability'),
        const Text(
          'Native alarms can fire with the app closed or offline, subject to phone settings. Sync is a separate process: last-minute Google changes may arrive late while the app is closed. Open Nextbell regularly to refresh and check scheduling coverage. Android force-stop disables app work until you reopen it. AlarmKit controls the iPhone alarm experience.',
        ),
        const SizedBox(height: 24),
        const SectionHeading('Help & policies'),
        for (final link in nextbellWebsiteLinks.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(link.key),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => perform(context, () => openExternal(link.value)),
          ),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Nextbell',
            applicationVersion: '1.0.0',
          ),
          child: const Text('Open-source licenses'),
        ),
      ],
    ),
  );
}
