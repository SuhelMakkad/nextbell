// Run: flutter test tool/generate_brand_assets.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<void> icon(String filename, int pixels) async {
  final recorder = ui.PictureRecorder();
  final c = ui.Canvas(recorder);
  c.scale(pixels / 1024);
  c.drawRect(
    const ui.Rect.fromLTWH(0, 0, 1024, 1024),
    ui.Paint()..color = const ui.Color(0xff6658d9),
  );
  c.translate(512, 500);
  c.rotate(-.16);
  final bell = ui.Path()
    ..moveTo(-222, 154)
    ..quadraticBezierTo(-222, 134, -200, 114)
    ..lineTo(-172, 80)
    ..lineTo(-172, -78)
    ..cubicTo(-172, -183, -110, -254, -34, -269)
    ..lineTo(-34, -288)
    ..quadraticBezierTo(-34, -326, 0, -326)
    ..quadraticBezierTo(34, -326, 34, -288)
    ..lineTo(34, -269)
    ..cubicTo(110, -254, 172, -183, 172, -78)
    ..lineTo(172, 80)
    ..lineTo(200, 114)
    ..quadraticBezierTo(222, 134, 222, 154)
    ..quadraticBezierTo(222, 178, 198, 178)
    ..lineTo(-198, 178)
    ..quadraticBezierTo(-222, 178, -222, 154)
    ..close();
  c.drawPath(bell, ui.Paint()..color = const ui.Color(0xffffffff));
  c.drawCircle(
    const ui.Offset(0, 219),
    43,
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  c.drawCircle(
    const ui.Offset(231, -230),
    53,
    ui.Paint()..color = const ui.Color(0xffc1ecdf),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(filename);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export original Nextbell icon at native sizes', () async {
    await icon('assets/brand/icon-1024.png', 1024);
    final android = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in android.entries) {
      await icon(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
      );
    }
    final base = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final json =
        jsonDecode(await File('$base/Contents.json').readAsString()) as Map;
    for (final spec in json['images'] as List) {
      if (spec['filename'] == null) continue;
      final size = double.parse((spec['size'] as String).split('x').first);
      final scale = double.parse((spec['scale'] as String).replaceAll('x', ''));
      await icon('$base/${spec['filename']}', (size * scale).round());
    }
  });
}
