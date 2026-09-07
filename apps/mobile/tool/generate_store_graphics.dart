// flutter test tool/generate_store_graphics.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'generate_brand_assets.dart' as brand;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export Play icon and original feature graphic', () async {
    await ui.loadFontFromList(
      await File('assets/fonts/Manrope.ttf').readAsBytes(),
      fontFamily: 'Manrope',
    );
    const directory = 'build/store-graphics';
    await brand.icon('$directory/icon-512.png', 512);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    void box(double x, double y, double w, double h, int color, double radius) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(x, y, w, h),
          ui.Radius.circular(radius),
        ),
        ui.Paint()..color = ui.Color(color),
      );
    }

    void text(
      String value,
      double x,
      double y,
      double width,
      double size,
      int color,
      ui.FontWeight weight,
    ) {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: 'Manrope',
                fontSize: size,
                fontWeight: weight,
                height: 1.15,
              ),
            )
            ..pushStyle(ui.TextStyle(color: ui.Color(color)))
            ..addText(value);
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: width));
      canvas.drawParagraph(paragraph, ui.Offset(x, y));
    }

    box(0, 0, 1024, 500, 0xfff8f7fc, 0);
    canvas.drawCircle(
      const ui.Offset(890, 80),
      190,
      ui.Paint()..color = const ui.Color(0xffe8e4fb),
    );
    canvas.drawCircle(
      const ui.Offset(1000, 440),
      180,
      ui.Paint()..color = const ui.Color(0xffd8f2e8),
    );
    text('nextbell.', 64, 55, 350, 25, 0xff6658d9, ui.FontWeight.w800);
    text(
      'Room for\nwhat’s next.',
      60,
      122,
      540,
      64,
      0xff24223e,
      ui.FontWeight.w800,
    );
    text(
      'Calendar alarms, on your terms.',
      64,
      314,
      510,
      24,
      0xff55536b,
      ui.FontWeight.w500,
    );
    text(
      'Google Calendar · Tasks · Shared calendars',
      64,
      416,
      570,
      18,
      0xff55536b,
      ui.FontWeight.w500,
    );
    box(637, 132, 319, 254, 0xff2a2447, 34);
    text(
      'YOUR NEXT MEETING',
      665,
      160,
      260,
      15,
      0xffd7d0fc,
      ui.FontWeight.w700,
    );
    text('3:00 PM', 665, 202, 270, 48, 0xffffffff, ui.FontWeight.w700);
    text(
      'A little time to get ready.',
      665,
      267,
      270,
      17,
      0xffd7d0fc,
      ui.FontWeight.w500,
    );
    box(665, 311, 119, 47, 0xff4a416d, 22);
    box(797, 311, 129, 47, 0xffd8f2e8, 22);
    text('10m before', 678, 323, 103, 16, 0xffffffff, ui.FontWeight.w600);
    text('5m before', 816, 323, 105, 16, 0xff284f45, ui.FontWeight.w600);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 500);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/feature-graphic.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
}
