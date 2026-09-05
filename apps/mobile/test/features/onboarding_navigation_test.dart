import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/application/app_services.dart';
import 'package:nextbell/core/models.dart';
import 'package:nextbell/main.dart';

void main() {
  const connected = AppSnapshot(
    accounts: [
      ConnectedAccount(
        id: 'personal',
        email: 'person@example.com',
        name: 'Person',
      ),
    ],
  );

  testWidgets('sign-in replaces welcome; setup Back returns to the agenda', (
    tester,
  ) async {
    final services = (await tester.runAsync(() async {
      final service = AppServices.create(demo: true);
      await service.ready;
      return service;
    }))!;
    final snapshots = StreamController<AppSnapshot>();
    final container = ProviderContainer(
      overrides: [
        servicesProvider.overrideWithValue(services),
        snapshotProvider.overrideWith((_) => snapshots.stream),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NextbellApp(),
      ),
    );
    snapshots.add(const AppSnapshot());
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);

    // Firebase sign-in can finish before the first Google source is connected.
    snapshots.add(const AppSnapshot(cloudRequired: true, cloudSignedIn: true));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/today/calendars',
    );
    expect(find.text('Continue with Google'), findsNothing);
    expect(tester.takeException(), isNull);

    // Google succeeds before the optional setup walkthrough is completed.
    snapshots.add(connected);
    await tester.pumpAndSettle();
    final router = container.read(routerProvider);
    expect(router.routeInformationProvider.value.uri.path, '/today/calendars');
    expect(find.text('Accounts & calendars'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);

    // Alarm setup is above calendars; Back from each must preserve the account.
    unawaited(router.push('/alarm-settings'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Accounts & calendars'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/today');
    expect(find.text('Continue with Google'), findsNothing);

    unawaited(router.push('/calendars'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/today');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    unawaited(snapshots.close());
    await tester.pump();
    await tester.runAsync(services.dispose);
  });

  testWidgets(
    'restored account opens the agenda even with unfinished onboarding',
    (tester) async {
      final services = (await tester.runAsync(() async {
        final service = AppServices.create(demo: true);
        await service.ready;
        return service;
      }))!;
      final container = ProviderContainer(
        overrides: [
          servicesProvider.overrideWithValue(services),
          snapshotProvider.overrideWith((_) => Stream.value(connected)),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NextbellApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/today',
      );
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Today').last, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(services.dispose);
    },
  );
}
