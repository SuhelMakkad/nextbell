import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextbell/core/application/app_services.dart';
import 'package:nextbell/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/Manrope.ttf').readAsBytesSync(),
        ),
      ),
    );
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
    'agenda, task and settings navigation renders; reminder sheet is usable',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = (await tester.runAsync(() async {
        final s = AppServices.create(demo: true);
        await s.ready;
        return s;
      }))!;
      final state = await tester.runAsync(() => service.db.snapshot());
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: [
              servicesProvider.overrideWithValue(service),
              snapshotProvider.overrideWith((ref) => Stream.value(state!)),
            ],
            child: const NextbellApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A little ahead.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await capture(tester, key, 'today');
      }
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      expect(find.text('Small things.\nMore headspace.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await capture(tester, key, 'tasks');
      }
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('Make it yours.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await capture(tester, key, 'settings');
      }
      await tester.tap(find.text('Alarms & reminders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default reminders'));
      await tester.pumpAndSettle();
      expect(find.text('Your default reminders'), findsOneWidget);
      await tester.tap(find.text('15m'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await capture(tester, key, 'reminders');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(service.dispose);
    },
  );
  testWidgets('large text and reduced motion stay usable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final service = (await tester.runAsync(() async {
      final s = AppServices.create(demo: true);
      await s.ready;
      return s;
    }))!;
    final state = await tester.runAsync(() => service.db.snapshot());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider.overrideWithValue(service),
          snapshotProvider.overrideWith((ref) => Stream.value(state!)),
        ],
        child: const NextbellApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(service.dispose);
  });
  testWidgets('dark agenda and shared-source settings render', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = (await tester.runAsync(() async {
      final s = AppServices.create(demo: true);
      await s.ready;
      final initial = await s.db.snapshot();
      await s.saveSettings(initial.settings.copyWith(theme: 'dark'));
      return s;
    }))!;
    final state = await tester.runAsync(() => service.db.snapshot());
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            servicesProvider.overrideWithValue(service),
            snapshotProvider.overrideWith((ref) => Stream.value(state!)),
          ],
          child: const NextbellApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
      await capture(tester, key, 'today-dark');
    }
    await tester.tap(find.byTooltip('Accounts & calendars'));
    await tester.pumpAndSettle();
    expect(find.text('Bring your days together.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
      await capture(tester, key, 'calendars-dark');
    }
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(service.dispose);
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/previews');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
