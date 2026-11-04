import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that aren't secret: the server's address and the theme.
class Preferences extends ChangeNotifier {
  Preferences(this._prefs);

  static Future<Preferences> load() async => Preferences(await SharedPreferences.getInstance());

  static const _serverKey = 'server';
  static const _themeKey = 'theme';

  final SharedPreferences _prefs;

  String? get server => _prefs.getString(_serverKey);

  Future<void> setServer(String server) async {
    await _prefs.setString(_serverKey, server);
  }

  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_prefs.getString(_themeKey)] ?? ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }
}
