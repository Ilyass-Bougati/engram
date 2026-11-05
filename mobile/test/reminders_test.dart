import 'dart:convert';

import 'package:engram_mobile/api/client.dart';
import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/auth/token_store.dart';
import 'package:engram_mobile/preferences.dart';
import 'package:engram_mobile/reminders/reminders.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class FakeScheduler implements NotificationScheduler {
  bool allow = true;
  final scheduled = <(int, tz.TZDateTime, String)>[];

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<void> cancelAll() async => scheduled.clear();

  @override
  Future<void> schedule(
    int id,
    tz.TZDateTime when, {
    required String title,
    required String body,
  }) async => scheduled.add((id, when, body));
}

Map<String, Object?> _deck(int due, int fresh) => {
  'id': 'd$due$fresh',
  'name': 'Deck',
  'description': '',
  'role': 'owner',
  'card_count': 10,
  'due_count': due,
  'new_count': fresh,
  'new_cards_per_day': 20,
  'created_at': '',
  'updated_at': '',
};

Deck _parsed(int due, int fresh) => Deck.fromJson(_deck(due, fresh));

const _user = User(id: 'u', username: 'alice', role: GlobalRole.user, timezone: 'Europe/Paris');

void main() {
  late tz.Location paris;
  late FakeScheduler scheduler;
  late Reminders reminders;
  late DateTime now;
  late List<Map<String, Object?>> serverDecks;

  ApiClient api() => ApiClient(
    server: Uri.parse('https://engram.test'),
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async => http.Response(jsonEncode(serverDecks), 200)),
  );

  setUpAll(() {
    tz_data.initializeTimeZones();
    paris = tz.getLocation('Europe/Paris');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    scheduler = FakeScheduler();
    now = tz.TZDateTime(paris, 2026, 11, 5, 10);
    serverDecks = [_deck(3, 0)];
    reminders = Reminders(
      preferences: await Preferences.load(),
      scheduler: scheduler,
      device: paris,
      clock: () => now,
    );
  });

  test('nothing is scheduled until reminders are on and someone is signed in', () async {
    await reminders.signedIn(_user, api());
    expect(scheduler.scheduled, isEmpty);
    expect(await reminders.setEnabled(true), isTrue);
    expect(reminders.times, [const TimeOfDay(hour: 19, minute: 0)]);
    expect(scheduler.scheduled.first.$2, tz.TZDateTime(paris, 2026, 11, 5, 19));
    expect(scheduler.scheduled.last.$3, lastReminderBody);
    expect(scheduler.scheduled.first.$3, reminderBody);
  });

  test('turning them on without permission leaves them off', () async {
    scheduler.allow = false;
    await reminders.signedIn(_user, api());
    expect(await reminders.setEnabled(true), isFalse);
    expect(reminders.enabled, isFalse);
    expect(scheduler.scheduled, isEmpty);
  });

  test('times are kept sorted, without duplicates, and at most four', () async {
    await reminders.setEnabled(true);
    for (final hour in [21, 7, 7, 12, 15]) {
      await reminders.addTime(TimeOfDay(hour: hour, minute: 0));
    }
    expect(reminders.times.map((t) => t.hour), [
      7,
      12,
      19,
      21,
    ], reason: 'the fifth, 15:00, is refused');
    expect(reminders.canAddTime, isFalse);
    await reminders.removeTime(const TimeOfDay(hour: 12, minute: 0));
    expect(reminders.times.map((t) => t.hour), [7, 19, 21]);
    expect(reminders.canAddTime, isTrue);
  });

  test("a finished day skips today's reminders, and they come back when cards do", () async {
    await reminders.setEnabled(true);
    await reminders.signedIn(_user, api());
    expect(scheduler.scheduled.first.$2.day, 5, reason: '3 cards due: remind tonight');

    await reminders.updateFromDecks([_parsed(0, 0)]);
    expect(scheduler.scheduled.first.$2, tz.TZDateTime(paris, 2026, 11, 6, 19));

    await reminders.updateFromDecks([_parsed(1, 0)]);
    expect(scheduler.scheduled.first.$2.day, 5);
  });

  test('cards coming back later today bring back reminders from then on', () async {
    await reminders.setEnabled(true);
    await reminders.addTime(const TimeOfDay(hour: 12, minute: 0));
    await reminders.signedIn(_user, api());

    reminders.noteNextDue(tz.TZDateTime(paris, 2026, 11, 5, 15));
    await reminders.updateFromDecks([_parsed(0, 0)]);
    expect(scheduler.scheduled.first.$2, tz.TZDateTime(paris, 2026, 11, 5, 19));
  });

  test('coming back to the app refreshes the counts', () async {
    await reminders.setEnabled(true);
    await reminders.signedIn(_user, api());
    serverDecks = [_deck(0, 0)];
    await reminders.refresh();
    expect(scheduler.scheduled.first.$2.day, 6);
  });

  test('signing out cancels them; signing back in brings them back', () async {
    await reminders.setEnabled(true);
    await reminders.signedIn(_user, api());
    await reminders.signedOut();
    expect(scheduler.scheduled, isEmpty);
    await reminders.signedIn(_user, api());
    expect(scheduler.scheduled, isNotEmpty);
  });
}
