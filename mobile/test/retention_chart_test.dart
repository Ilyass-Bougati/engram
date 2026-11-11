import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/screens/stats/retention_chart.dart';
import 'package:engram_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final months = [
    for (var m = 1; m <= 12; m++)
      MonthRetention(
        month: '2026-${m.toString().padLeft(2, '0')}',
        reviews: m == 4 ? 0 : 100,
        remembered: m * 7,
      ),
  ];

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(width: 360, child: RetentionChart(months: months)),
      ),
    ),
  );

  testWidgets('starts on the latest month; a tap shows another', (tester) async {
    await show(tester);
    expect(find.text('December 2026 · 84% · 84 of 100 remembered'), findsOneWidget);

    // 40 px of axis, then 12 bands across the remaining 320.
    final chart = tester.getTopLeft(find.byType(CustomPaint).last);
    final band = (360 - 40) / 12;
    await tester.tapAt(chart + Offset(40 + band * 1.5, 100));
    await tester.pump();
    expect(find.text('February 2026 · 14% · 14 of 100 remembered'), findsOneWidget);

    await tester.tapAt(chart + Offset(40 + band * 3.5, 100));
    await tester.pump();
    expect(find.text('April 2026 · no reviews'), findsOneWidget);
  });

  testWidgets('screen readers hear every month', (tester) async {
    await show(tester);
    final label = tester.getSemantics(find.byType(LayoutBuilder)).label;
    expect(label, startsWith('Retention by month for the past year.'));
    expect(label, contains('January 2026 · 7% · 7 of 100 remembered'));
    expect(label, contains('April 2026 · no reviews'));
  });
}
