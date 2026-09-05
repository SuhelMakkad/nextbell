// Emulator/device prerequisites (for this app only): grant exact-alarm and
// notification access in system settings, or use the adb commands in VALIDATION.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native alarm fires and can be canceled without Flutter presentation',
    (tester) async {
      final host = NextbellHostApi();
      expect(
        (await host.permissions()).alarms,
        true,
        reason: 'Grant exact-alarm access on the test device first.',
      );
      final now = DateTime.now();
      final id = stableId(['delivery-test', now.microsecondsSinceEpoch]);
      try {
        await host.scheduleAlarm(
          NativeAlarm(
            id: id,
            entryId: 'test',
            title: 'Nextbell delivery test',
            subtitle: 'Temporary development alarm',
            fireAtMillis: now
                .add(const Duration(seconds: 4))
                .millisecondsSinceEpoch,
            snoozeMinutes: 5,
            sourceIds: [],
          ),
        );
        expect((await host.alarms()).any((a) => a.id == id), true);
        await Future<void>.delayed(const Duration(seconds: 7));
        expect((await host.alarms()).any((a) => a.id == id && a.ringing), true);
      } finally {
        await host.cancelAlarms([id]);
        final actions = await host.pendingActions();
        await host.acknowledgeActions(
          actions.where((a) => a.alarmId == id).map((a) => a.id).toList(),
        );
      }
      expect((await host.alarms()).any((a) => a.id == id), false);
    },
  );
}
