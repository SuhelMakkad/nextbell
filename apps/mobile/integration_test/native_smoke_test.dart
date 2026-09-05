import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextbell/core/application/app_services.dart';
import 'package:nextbell/main.dart';
import 'package:nextbell_platform/nextbell_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native bridge responds and demo agenda works on a real engine', (
    tester,
  ) async {
    final host = NextbellHostApi();
    final permissions = await host.permissions();
    expect(permissions.alarms, isA<bool>());
    expect(await host.accounts(), isA<List<NativeAccount>>());
    expect(await host.alarms(), isA<List<NativeAlarm>>());
    final services = AppServices.create(demo: true);
    await services.ready;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const NextbellApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A little ahead.'), findsOneWidget);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    expect(find.text('Small things.\nMore headspace.'), findsOneWidget);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Make it yours.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await services.dispose();
  });
}
