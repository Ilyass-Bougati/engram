// Draws the app icons from the web app's mark (frontend/public/favicon.svg) with the same painter
// the app uses. Not part of the test suite: run it after changing the mark, and commit the PNGs.
//
//   cd mobile && flutter test tool/generate_icons_test.dart
//
// Android 8+ uses the adaptive icon in android/app/src/main/res/mipmap-anydpi-v26 instead, which
// is vector XML with the same geometry; these PNGs are for iOS and for older Android versions.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engram_mobile/theme.dart';
import 'package:engram_mobile/widgets/engram_mark.dart';
import 'package:flutter_test/flutter_test.dart';

const _colors = EngramColors.light;

/// The middle of the mark as it looks (the back card is tilted), in its 24-unit grid.
const _markCenter = Offset(12.9, 11.0);

/// The mark's visual size, in grid units, and the share of the icon it fills.
const _markExtent = 20.0;
const _fill = 0.62;

/// A PNG without an alpha channel: App Store Connect rejects icons that have one, even when
/// every pixel is opaque, and dart:ui only encodes RGBA.
List<int> _rgbPng(ByteData rgba, int width, int height) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // no filter
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw
        ..addByte(rgba.getUint8(i))
        ..addByte(rgba.getUint8(i + 1))
        ..addByte(rgba.getUint8(i + 2));
    }
  }
  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    var crc = 0xFFFFFFFF;
    for (final byte in body) {
      crc ^= byte;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    crc ^= 0xFFFFFFFF;
    int b(int v, int shift) => (v >> shift) & 0xFF;
    final length = data.length;
    return [
      b(length, 24),
      b(length, 16),
      b(length, 8),
      b(length, 0),
      ...body,
      b(crc, 24),
      b(crc, 16),
      b(crc, 8),
      b(crc, 0),
    ];
  }

  int b(int v, int shift) => (v >> shift) & 0xFF;
  final header = [
    b(width, 24),
    b(width, 16),
    b(width, 8),
    b(width, 0),
    b(height, 24),
    b(height, 16),
    b(height, 8),
    b(height, 0),
    8,
    2,
    0,
    0,
    0,
  ];
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ...chunk('IHDR', header),
    ...chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes())),
    ...chunk('IEND', const []),
  ];
}

Future<void> _write(String path, int size, {double cornerRadius = 0}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();
  final paper = ui.Paint()..color = _colors.paperTop;
  if (cornerRadius == 0) {
    // iOS masks the corners itself and rejects icons with transparency.
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, s, s), paper);
  } else {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0, 0, s, s),
        ui.Radius.circular(s * cornerRadius),
      ),
      paper,
    );
  }
  final markSize = s * _fill / _markExtent * 24;
  final scale = markSize / 24;
  canvas.translate(s / 2 - _markCenter.dx * scale, s / 2 - _markCenter.dy * scale);
  paintEngramMark(
    canvas,
    markSize,
    front: _colors.pine,
    backFill: _colors.pineSoft,
    backStroke: _colors.pine,
  );
  final image = await recorder.endRecording().toImage(size, size);
  if (cornerRadius == 0) {
    final rgba = await image.toByteData();
    File(path).writeAsBytesSync(_rgbPng(rgba!, size, size));
  } else {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  }
}

void main() {
  test('generate app icons', () async {
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    const iosIcons = {
      '20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60, //
      '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87, //
      '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120, //
      '60x60@2x': 120, '60x60@3x': 180, //
      '76x76@1x': 76, '76x76@2x': 152, //
      '83.5x83.5@2x': 167, '1024x1024@1x': 1024,
    };
    for (final MapEntry(key: name, value: size) in iosIcons.entries) {
      await _write('$ios/Icon-App-$name.png', size);
    }
    const android = 'android/app/src/main/res';
    const androidIcons = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final MapEntry(key: density, value: size) in androidIcons.entries) {
      await _write('$android/mipmap-$density/ic_launcher.png', size, cornerRadius: 0.2);
    }
  });
}
