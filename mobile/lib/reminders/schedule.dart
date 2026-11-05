import 'package:flutter/material.dart' show TimeOfDay;
import 'package:timezone/timezone.dart' as tz;

// When study reminders fire. Pure functions, so the rules can be tested without a phone.
//
// Reminders are one-off notifications for the next [scheduleDays] days, rescheduled whenever
// the app learns something new, because a repeating notification can't skip a single day on
// iOS. iOS keeps at most 64 pending notifications, so [maxReminderTimes] a day fit in the window.

/// Like the server (backend/app/scheduling.py), a study day rolls over at 04:00 local time.
const rolloverHour = 4;
const scheduleDays = 14;
const maxReminderTimes = 4;

/// When the current study day ends: the next 04:00 in the account's timezone.
tz.TZDateTime nextRollover(DateTime now, tz.Location account) {
  final local = tz.TZDateTime.from(now, account);
  final today = tz.TZDateTime(account, local.year, local.month, local.day, rolloverHour);
  return today.isAfter(local)
      ? today
      : tz.TZDateTime(account, local.year, local.month, local.day + 1, rolloverHour);
}

/// Every reminder from [now] through the next [days] days at [times] on the phone's clock,
/// soonest first. Reminders before [doneUntil] are left out: the day's reviews are done until
/// then.
List<tz.TZDateTime> reminderSlots({
  required DateTime now,
  required List<TimeOfDay> times,
  required tz.Location device,
  DateTime? doneUntil,
  int days = scheduleDays,
}) {
  final local = tz.TZDateTime.from(now, device);
  final slots = <tz.TZDateTime>[
    for (var day = 0; day < days; day++)
      for (final time in times)
        tz.TZDateTime(device, local.year, local.month, local.day + day, time.hour, time.minute),
  ];
  return slots
      .where((slot) => slot.isAfter(now) && (doneUntil == null || !slot.isBefore(doneUntil)))
      .toList()
    ..sort();
}
