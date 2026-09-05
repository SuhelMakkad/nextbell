import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../sync/application/background_sync.dart';
import '../data/cloud_api.dart';

@pragma('vm:entry-point')
Future<void> cloudMessage(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!CloudConfig.enabled || !CloudConfig.configured) return;
  if (!const ['sync', 'urgent_change'].contains(message.data['type'])) return;
  await CloudConfig.initialize();
  await registerBackgroundSync();
  await Workmanager().registerOneOffTask(
    'com.suhel.nextbell.cloudRefresh',
    backgroundTask,
    existingWorkPolicy: ExistingWorkPolicy.append,
    constraints: Constraints(networkType: NetworkType.connected),
    expedited: message.data['type'] == 'urgent_change',
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
  );
}

Future<void> initializeCloudMessages() async {
  if (!CloudConfig.enabled || !CloudConfig.configured) return;
  await CloudConfig.initialize();
  FirebaseMessaging.onBackgroundMessage(cloudMessage);
  FirebaseMessaging.instance.onTokenRefresh.listen(
    (_) => cloudMessage(const RemoteMessage(data: {'type': 'sync'})),
  );
}
