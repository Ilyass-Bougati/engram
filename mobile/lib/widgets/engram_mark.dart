import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Two stacked cards: the deck behind, the card you're on in front. The web app's EngramMark,
/// drawn on a 24×24 grid. Decorative: it carries no semantics.
class EngramMark extends StatelessWidget {
  const EngramMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _MarkPainter(context.colors)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.colors);

  final EngramColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    const radius = Radius.circular(2.5);
    canvas
      ..save()
      ..translate(13.75, 10.5)
      ..rotate(10 * math.pi / 180)
      ..translate(-13.75, -10.5);
    final back = RRect.fromRectAndRadius(const Rect.fromLTWH(7.5, 2.75, 12.5, 15.5), radius);
    canvas
      ..drawRRect(back, Paint()..color = colors.pineSoft)
      ..drawRRect(
        back,
        Paint()
          ..color = colors.pine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      )
      ..restore()
      ..drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(4, 5.5, 12.5, 15.5), radius),
        Paint()..color = colors.pine,
      );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.colors != colors;
}
