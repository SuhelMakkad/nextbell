import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/application/app_services.dart';

const backgroundTask = 'com.suhel.nextbell.sync';
bool _registered = false;
Future<void> registerBackgroundSync() async {
  if (_registered || (!Platform.isAndroid && !Platform.isIOS)) return;
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundTask,
    backgroundTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
  _registered = true;
}

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final services = AppServices.create();
    try {
      await services.ready;
      await services.sync.run();
      return true;
    } catch (_) {
      return false;
    } finally {
      await services.dispose();
    }
  });
}
