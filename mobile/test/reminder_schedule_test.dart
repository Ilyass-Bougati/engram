import 'package:engram_mobile/reminders/schedule.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location paris;
  late tz.Location newYork;
  late tz.Location tokyo;

  setUpAll(() {
    tz_data.initializeTimeZones();
    paris = tz.getLocation('Europe/Paris');
    newYork = tz.getLocation('America/New_York');
    tokyo = tz.getLocation('Asia/Tokyo');
  });

  const morning = TimeOfDay(hour: 8, minute: 0);
  const evening = TimeOfDay(hour: 19, minute: 0);

  test('schedules every time for two weeks, soonest first, from now on', () {
    final now = tz.TZDateTime(paris, 2026, 11, 5, 10);
    final slots = reminderSlots(now: now, times: [evening, morning], device: paris);
    expect(slots.first, tz.TZDateTime(paris, 2026, 11, 5, 19), reason: "today's 08:00 is past");
    expect(slots[1], tz.TZDateTime(paris, 2026, 11, 6, 8));
    expect(slots, hasLength(1 + 2 * 13));
    expect(slots.last, tz.TZDateTime(paris, 2026, 11, 18, 19));
    expect([...slots]..sort(), slots);
  });

  test('a finished day skips the rest of it, until the 04:00 rollover', () {
    final now = tz.TZDateTime(paris, 2026, 11, 5, 10);
    final rollover = nextRollover(now, paris);
    expect(rollover, tz.TZDateTime(paris, 2026, 11, 6, 4));
    final slots = reminderSlots(
      now: now,
      times: [morning, evening],
      device: paris,
      doneUntil: rollover,
    );
    expect(slots.first, tz.TZDateTime(paris, 2026, 11, 6, 8), reason: "tomorrow's still come");
  });

  test('after midnight, the study day is still yesterday until 04:00', () {
    final now = tz.TZDateTime(paris, 2026, 11, 6, 2);
    expect(nextRollover(now, paris), tz.TZDateTime(paris, 2026, 11, 6, 4));
    final slots = reminderSlots(
      now: now,
      times: [morning],
      device: paris,
      doneUntil: nextRollover(now, paris),
    );
    expect(slots.first, tz.TZDateTime(paris, 2026, 11, 6, 8));
  });

  test("the rollover follows the account's timezone, the times the phone's", () {
    // 10:00 in New York is 00:00 in Tokyo; Tokyo's study day ends at 04:00 there, 14:00 here.
    final now = tz.TZDateTime(newYork, 2026, 11, 5, 10);
    final rollover = nextRollover(now, tokyo);
    expect(rollover.isAtSameMomentAs(tz.TZDateTime(newYork, 2026, 11, 5, 14)), isTrue);
    final slots = reminderSlots(
      now: now,
      times: [const TimeOfDay(hour: 12, minute: 0), evening],
      device: newYork,
      doneUntil: rollover,
    );
    expect(slots.first, tz.TZDateTime(newYork, 2026, 11, 5, 19));
  });

  test('times stay on the clock across a daylight-saving change', () {
    final now = tz.TZDateTime(paris, 2026, 10, 20, 10);
    final slots = reminderSlots(now: now, times: [evening], device: paris);
    expect(slots.map((slot) => slot.hour).toSet(), {19});
    expect(slots.map((slot) => slot.timeZoneOffset).toSet(), hasLength(2));
  });

  test('the most reminders a day fit under the 64 iOS keeps', () {
    final now = tz.TZDateTime(paris, 2026, 11, 5, 0, 1);
    final times = [
      for (var h = 0; h < maxReminderTimes; h++) TimeOfDay(hour: 6 + h * 4, minute: 0),
    ];
    expect(reminderSlots(now: now, times: times, device: paris).length, lessThanOrEqualTo(64));
  });
}
