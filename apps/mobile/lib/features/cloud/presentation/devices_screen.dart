import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/application/app_services.dart';
import '../../../core/models.dart';
import '../../../core/widgets/common.dart';
import '../data/cloud_api.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});
  String time(dynamic value) => value == null
      ? 'Not reported yet'
      : DateFormat.MMMd().add_jm().format(
          DateTime.parse(value as String).toLocal(),
        );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(snapshotProvider).value;
    final service = ref.read(servicesProvider);
    final cloud = service.cloud;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices & sync'),
        actions: [
          IconButton(
            tooltip: 'Refresh cloud status',
            onPressed: () => perform(context, service.sync.runAfterCurrent),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: cloud == null || state == null
          ? const Center(
              child: Text('Cloud sync is available in the Android beta.'),
            )
          : StreamBuilder<List<Json>>(
              stream: service.db
                  .select(service.db.records)
                  .watch()
                  .asyncMap(
                    (_) async => [
                      {
                        'devices': await service.db.list('cloudRemoteDevice'),
                        'pending': await service.db.list('cloudOutbox'),
                        'own': await service.db.getOne('cloudDevice', 'main'),
                        'settings': await service.db.getOne('settings', 'main'),
                      },
                    ],
                  ),
              builder: (context, snapshot) {
                final data = snapshot.data?.firstOrNull;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final devices = (data['devices'] as List).cast<Json>();
                final pending = (data['pending'] as List).cast<Json>();
                final own = data['own'] as Json?;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Together, wherever\nyour day goes.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Each phone rings independently. Snooze and Dismiss apply to that phone. Offline phones receive changes when they reconnect.',
                    ),
                    const SizedBox(height: 16),
                    if (state.syncError != null) Notice(state.syncError!),
                    Text(
                      'This phone last synced: ${time(state.lastSync?.toIso8601String())}',
                    ),
                    if (pending.isNotEmpty)
                      Notice(
                        '${pending.length} changes are waiting to finish syncing.',
                      ),
                    for (final operation in pending.where(
                      (p) => p['conflict'] == true,
                    ))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'This setting changed on another phone.',
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => perform(
                                      context,
                                      () => cloud.resolveConflict(
                                        operation['id'],
                                        keepMine: false,
                                      ),
                                    ),
                                    child: const Text('Use the cloud setting'),
                                  ),
                                  FilledButton(
                                    onPressed: () => perform(
                                      context,
                                      () => cloud.resolveConflict(
                                        operation['id'],
                                        keepMine: true,
                                      ),
                                    ),
                                    child: const Text('Keep my change'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final operation in pending.where(
                      (p) => p['error'] != null,
                    ))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(operation['error'] as String),
                              TextButton(
                                onPressed: () => perform(
                                  context,
                                  () => cloud.discardFailed(operation['id']),
                                ),
                                child: const Text('Discard change and refresh'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SectionHeading('Your phones'),
                    for (final device in devices)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${device['name']}${device['id'] == own?['id'] ? ' · this phone' : ''}',
                                ),
                                subtitle: Text(
                                  'Last contact: ${time(device['lastSeen'])}',
                                ),
                                value: device['id'] == own?['id']
                                    ? (own?['alarmsEnabled'] ?? true)
                                    : device['alarmsEnabled'],
                                onChanged: (enabled) => perform(
                                  context,
                                  () => cloud.setDevice(device, enabled),
                                ),
                              ),
                              if (device['pending'] == true)
                                const Text(
                                  'This change is waiting to reach the cloud.',
                                ),
                              if (device['health'] != null) ...[
                                if ((device['health']
                                        as Json)['deviceVersion'] !=
                                    device['version'])
                                  const Notice(
                                    'Waiting for this phone to apply its latest alarm setting.',
                                  ),
                                Text(
                                  '${(device['health'] as Json)['scheduledCount']} alarms scheduled',
                                ),
                                Text(
                                  'Downloaded revision ${(device['health'] as Json)['appliedRevision']} · scheduled revision ${(device['health'] as Json)['scheduledRevision']}',
                                ),
                                if ((device['health'] as Json)['error'] !=
                                    'none')
                                  Notice(
                                    'Needs attention: ${(device['health'] as Json)['error']}',
                                  ),
                                if ((device['health']
                                        as Json)['earliestUnscheduled'] !=
                                    null)
                                  Text(
                                    'First uncovered reminder: ${time((device['health'] as Json)['earliestUnscheduled'])}',
                                  ),
                              ] else
                                const Text(
                                  'Waiting for the phone to report its alarm status.',
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SectionHeading('Stay up to date'),
                    Card(
                      child: SwitchListTile.adaptive(
                        title: const Text('Upcoming meeting changes'),
                        subtitle: const Text(
                          'Quiet notices for moved or canceled meetings with an alarm in the next hour.',
                        ),
                        value:
                            (data['settings'] as Json?)?['urgentNotices'] ??
                            true,
                        onChanged: (enabled) => perform(
                          context,
                          () => cloud.edit('settings', 'main', {
                            'urgentNotices': enabled,
                          }),
                        ),
                      ),
                    ),
                    const SectionHeading('Your account'),
                    const Text(
                      'Selected Google data and reminder settings sync securely through Nextbell. Your alarms are stored on each phone and work offline.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign out of this phone'),
                      onPressed: () async {
                        if (await confirm(
                              context,
                              'Sign out of this phone?',
                              'Local data will be cleared and this phone’s alarms canceled. Cloud data stays in your Nextbell account.',
                              action: 'Sign out',
                            ) &&
                            context.mounted) {
                          await perform(context, () async {
                            await cloud.api.send('DELETE', 'devices/current');
                            await service.resetForCloud();
                            await FirebaseAuth.instance.signOut();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Nextbell account'),
                      onPressed: () async {
                        if (await confirm(
                              context,
                              'Delete your Nextbell account?',
                              'This deletes your cloud settings and connected Google data from Nextbell. Other phones clear their data when they reconnect. Your Google accounts and Google events stay unchanged.',
                              action: 'Delete account',
                            ) &&
                            context.mounted) {
                          await perform(context, () async {
                            await (service.auth as CloudAccountRepository)
                                .signIn(reauthenticate: true);
                            await cloud.api.send('DELETE', 'me');
                            await FirebaseAuth.instance.signOut();
                            await service.resetForCloud();
                          });
                        }
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}
