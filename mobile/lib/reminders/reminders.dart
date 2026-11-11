import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../api/client.dart';
import '../api/models.dart';
import '../preferences.dart';
import 'schedule.dart';

/// Shows and schedules notifications. The app uses the platform's (notifier.dart); tests use a
/// fake.
abstract interface class NotificationScheduler {
  /// Asks to show notifications. True when allowed.
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> schedule(int id, tz.TZDateTime when, {required String title, required String body});
}

const reminderTitle = 'Time to study';
const reminderBody = 'Your reviews are waiting in Engram.';

/// The last reminder in the window: after it, reminders stop until the app is opened again.
const lastReminderBody = 'Open Engram to keep your study reminders coming.';

/// The default when reminders are first turned on.
const defaultReminderTime = TimeOfDay(hour: 19, minute: 0);

/// Daily study reminders at the times chosen in Settings, skipped once the day's reviews are
/// done. Everything runs on the phone: "done" means every deck's due and new counts from
/// GET /api/decks are zero. Reminders follow whoever is signed in on the server in use.
class Reminders extends ChangeNotifier {
  Reminders({
    required this._preferences,
    required this._scheduler,
    required this._device,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Preferences _preferences;
  final NotificationScheduler _scheduler;
  final tz.Location _device;
  final DateTime Function() _clock;

  ApiClient? _api;
  User? _user;

  /// Reminders before this are skipped: today's reviews are done until then.
  DateTime? _doneUntil;

  /// The earliest time a finished session said cards come back, if still in the future.
  DateTime? _nextDue;

  Future<void> _queue = Future.value();

  bool get enabled => _preferences.remindersEnabled;

  List<TimeOfDay> get times => _preferences.reminderTimes;

  bool get canAddTime => times.length < maxReminderTimes;

  /// Turns reminders on or off. Turning them on asks for permission first; returns false if it
  /// was refused, and reminders stay off.
  Future<bool> setEnabled(bool on) async {
    if (on && !await _scheduler.requestPermission()) return false;
    if (on && times.isEmpty) await _preferences.setReminderTimes([defaultReminderTime]);
    await _preferences.setRemindersEnabled(on);
    notifyListeners();
    await _reschedule();
    return true;
  }

  /// Adds a reminder time. Ignored if it's already there or there are [maxReminderTimes].
  Future<void> addTime(TimeOfDay time) async {
    if (!canAddTime || times.contains(time)) return;
    await _preferences.setReminderTimes([...times, time]);
    notifyListeners();
    await _reschedule();
  }

  Future<void> removeTime(TimeOfDay time) async {
    await _preferences.setReminderTimes(times.where((t) => t != time).toList());
    notifyListeners();
    await _reschedule();
  }

  /// Someone is signed in: reminders are for them, and today's counts come from [api].
  Future<void> signedIn(User user, ApiClient api) async {
    final changed = _api != api || _user?.id != user.id || _user?.timezone != user.timezone;
    _api = api;
    _user = user;
    if (!changed) return;
    _doneUntil = null;
    _nextDue = null;
    await refresh();
  }

  /// Nobody is signed in any more: no reminders.
  Future<void> signedOut() async {
    _api = null;
    _user = null;
    _doneUntil = null;
    _nextDue = null;
    await _reschedule();
  }

  /// Fetches today's counts and reschedules. Offline, the current reminders stay as they are.
  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    try {
      await updateFromDecks(await api.decks());
    } on Exception {
      // Can't tell whether today is done: keep what's scheduled.
    }
  }

  /// Today is done when nothing is due and no new cards are left, in any deck.
  Future<void> updateFromDecks(List<Deck> decks) async {
    final user = _user;
    if (user == null) return;
    final now = _clock();
    final done = decks.every((deck) => deck.dueCount == 0 && deck.newCount == 0);
    if (!done) {
      _doneUntil = null;
    } else {
      final rollover = nextRollover(now, _accountLocation(user));
      final nextDue = _nextDue;
      // Learning steps can bring cards back the same day: remind from then on.
      _doneUntil = nextDue != null && nextDue.isAfter(now) && nextDue.isBefore(rollover)
          ? nextDue
          : rollover;
    }
    await _reschedule();
  }

  /// A study session ended, and its cards come back at [at].
  void noteNextDue(DateTime at) {
    final current = _nextDue;
    if (current == null || !current.isAfter(_clock()) || at.isBefore(current)) _nextDue = at;
  }

  tz.Location _accountLocation(User user) {
    try {
      return tz.getLocation(user.timezone);
    } on tz.LocationNotFoundException {
      return _device;
    }
  }

  // One reschedule at a time, so a cancel never lands between another one's schedules.
  Future<void> _reschedule() => _queue = _queue.then((_) async {
    await _scheduler.cancelAll();
    if (!enabled || _user == null || times.isEmpty) return;
    final slots = reminderSlots(
      now: _clock(),
      times: times,
      device: _device,
      doneUntil: _doneUntil,
    );
    for (final (id, slot) in slots.indexed) {
      await _scheduler.schedule(
        id,
        slot,
        title: reminderTitle,
        body: id == slots.length - 1 ? lastReminderBody : reminderBody,
      );
    }
  });
}
