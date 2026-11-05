import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that aren't secret: the servers you use and the theme.
class Preferences extends ChangeNotifier {
  Preferences(this._prefs);

  static Future<Preferences> load() async => Preferences(await SharedPreferences.getInstance());

  static const _serverKey = 'server';
  static const _serversKey = 'servers';
  static const _themeKey = 'theme';
  static const _remindersKey = 'reminders';
  static const _reminderTimesKey = 'reminder_times';

  final SharedPreferences _prefs;

  /// The server in use, as normalized by normalizeServerUrl; null on first launch.
  String? get server => _prefs.getString(_serverKey);

  /// Every server used on this device, most recently chosen first.
  List<String> get servers {
    final saved = _prefs.getStringList(_serversKey) ?? const [];
    final current = server;
    return [if (current != null && !saved.contains(current)) current, ...saved];
  }

  /// Makes [server] the one in use and moves it to the top of the list.
  Future<void> setServer(String server) async {
    final others = servers.where((s) => s != server);
    await _prefs.setString(_serverKey, server);
    await _prefs.setStringList(_serversKey, [server, ...others]);
    notifyListeners();
  }

  /// Takes [server] off the list. If it was the one in use, none is.
  Future<void> removeServer(String server) async {
    final others = servers.where((s) => s != server).toList();
    if (this.server == server) await _prefs.remove(_serverKey);
    await _prefs.setStringList(_serversKey, others);
    notifyListeners();
  }

  bool get remindersEnabled => _prefs.getBool(_remindersKey) ?? false;

  Future<void> setRemindersEnabled(bool enabled) => _prefs.setBool(_remindersKey, enabled);

  /// Reminder times on the phone's clock, sorted, stored as "HH:MM".
  List<TimeOfDay> get reminderTimes => [
    for (final text in _prefs.getStringList(_reminderTimesKey) ?? const <String>[])
      if (RegExp(r'^(\d\d):(\d\d)$').firstMatch(text) case final match?)
        TimeOfDay(hour: int.parse(match[1]!), minute: int.parse(match[2]!)),
  ];

  Future<void> setReminderTimes(List<TimeOfDay> times) {
    final sorted = {...times}.toList()
      ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    String two(int n) => n.toString().padLeft(2, '0');
    return _prefs.setStringList(_reminderTimesKey, [
      for (final t in sorted) '${two(t.hour)}:${two(t.minute)}',
    ]);
  }

  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_prefs.getString(_themeKey)] ?? ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }
}
