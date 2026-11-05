import 'package:engram_mobile/preferences.dart';
import 'package:engram_mobile/reminders/reminders.dart';
import 'package:engram_mobile/screens/settings/reminder_settings.dart';
import 'package:engram_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminders_test.dart' show FakeScheduler;

void main() {
  late FakeScheduler scheduler;
  late Reminders reminders;

  setUpAll(tz_data.initializeTimeZones);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    scheduler = FakeScheduler();
    reminders = Reminders(
      preferences: await Preferences.load(),
      scheduler: scheduler,
      device: tz.getLocation('Europe/Paris'),
    );
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: ReminderSettings(reminders: reminders)),
      ),
    ),
  );

  testWidgets('turning reminders on starts with 19:00; times can be added and removed', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Add a time'), findsNothing);

    await tester.tap(find.text('Remind me to study'));
    await tester.pumpAndSettle();
    expect(find.text('19:00'), findsOneWidget);

    await tester.tap(find.text('Add a time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '08');
    await tester.enterText(fields.at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('08:30'), findsOneWidget);
    expect(reminders.times.map((t) => '${t.hour}:${t.minute}'), ['8:30', '19:0']);

    await tester.tap(find.byTooltip('Remove 19:00'));
    await tester.pumpAndSettle();
    expect(find.text('19:00'), findsNothing);
    expect(find.text('08:30'), findsOneWidget);
  });

  testWidgets('says how to fix it when notifications are refused', (tester) async {
    scheduler.allow = false;
    await show(tester);
    await tester.tap(find.text('Remind me to study'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Notifications are off for Engram.'), findsOneWidget);
    expect(reminders.enabled, isFalse);
  });

  testWidgets('stops offering more times at four', (tester) async {
    await tester.runAsync(() async {
      await reminders.setEnabled(true);
      for (final hour in [7, 12, 15]) {
        await reminders.addTime(TimeOfDay(hour: hour, minute: 0));
      }
    });
    await show(tester);
    expect(find.text('Add a time'), findsNothing);
    expect(find.text('Up to 4 reminders a day.'), findsOneWidget);
  });
}
