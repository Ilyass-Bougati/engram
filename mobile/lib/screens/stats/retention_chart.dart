import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../api/models.dart';
import '../../format.dart';
import '../../theme.dart';

// The web's RetentionChart.tsx: a column per month for the past year, the share of reviews not
// rated Again. Tap a column for its numbers, the touch version of the web's tooltip.

const _height = 180.0;
const _left = 40.0;
const _bottom = 24.0;
const _top = 20.0;

DateTime _monthDate(String month) {
  final parts = month.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1]);
}

String _remembered(Retention r) {
  final number = NumberFormat.decimalPattern();
  return '${number.format(r.remembered)} of ${number.format(r.reviews)} remembered';
}

/// One line about a month: "March 2026 · 82% · 410 of 500 remembered".
String monthRetentionText(MonthRetention month) {
  final name = DateFormat.yMMMM().format(_monthDate(month.month));
  return month.reviews == 0
      ? '$name · no reviews'
      : '$name · ${percent(month.remembered, month.reviews)} · ${_remembered(month)}';
}

class RetentionChart extends StatefulWidget {
  const RetentionChart({super.key, required this.months});

  final List<MonthRetention> months;

  @override
  State<RetentionChart> createState() => _RetentionChartState();
}

class _RetentionChartState extends State<RetentionChart> {
  late int _selected = _latest;

  int get _latest => widget.months.lastIndexWhere((month) => month.reviews > 0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final months = widget.months;
    final selected = _selected >= 0 && _selected < months.length ? months[_selected] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'Retention by month for the past year. '
              '${months.map(monthRetentionText).join('. ')}.',
          image: true,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final band = math.max(0.0, width - _left) / months.length;
              return GestureDetector(
                onTapUp: (details) {
                  final index = ((details.localPosition.dx - _left) / band).floor();
                  if (index >= 0 && index < months.length) setState(() => _selected = index);
                },
                child: CustomPaint(
                  size: Size(width, _height),
                  painter: _RetentionPainter(
                    months: months,
                    colors: c,
                    latest: _latest,
                    selected: _selected,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (selected != null)
          Text(
            monthRetentionText(selected),
            style: TextStyle(
              fontSize: 14,
              color: c.inkMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _RetentionPainter extends CustomPainter {
  _RetentionPainter({
    required this.months,
    required this.colors,
    required this.latest,
    required this.selected,
  });

  final List<MonthRetention> months;
  final EngramColors colors;
  final int latest;
  final int selected;

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required Color color,
    TextAlign align = TextAlign.center,
    FontWeight? weight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: sansFamily,
          fontSize: 12,
          color: color,
          fontWeight: weight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right || TextAlign.end => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final band = math.max(0.0, width - _left) / months.length;
    final column = math.min(24.0, band * 0.6);
    const baseline = _height - _bottom;
    double y(double share) => baseline - share * (baseline - _top);
    // Every other month label when the bands get narrow.
    final labelEvery = band < 36 ? 2 : 1;
    final line = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    for (final share in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(_left, y(share)), Offset(width, y(share)), line);
      _text(
        canvas,
        '${(share * 100).round()}%',
        Offset(_left - 8, y(share)),
        color: colors.inkMuted,
        align: TextAlign.right,
      );
    }
    final monthFormat = DateFormat.MMM();
    for (final (index, month) in months.indexed) {
      final x = _left + index * band;
      final share = month.reviews == 0 ? 0.0 : month.remembered / month.reviews;
      if (month.reviews > 0) {
        final top = y(share);
        final radius = math.min(4.0, math.min(column / 2, baseline - top));
        final rect = Rect.fromLTRB(x + (band - column) / 2, top, x + (band + column) / 2, baseline);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
          ),
          Paint()..color = index == selected || selected < 0 ? colors.pine : colors.chart[1],
        );
      }
      if (index == latest || (index == selected && month.reviews > 0)) {
        _text(
          canvas,
          percent(month.remembered, month.reviews),
          Offset(x + band / 2, y(share) - 10),
          color: colors.ink,
          weight: FontWeight.w500,
        );
      }
      if (index % labelEvery == (months.length - 1) % labelEvery) {
        _text(
          canvas,
          monthFormat.format(_monthDate(month.month)),
          Offset(x + band / 2, _height - 8),
          color: colors.inkMuted,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RetentionPainter old) =>
      old.months != months || old.colors != colors || old.selected != selected;
}
