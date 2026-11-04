import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that aren't secret: the servers you use and the theme.
class Preferences extends ChangeNotifier {
  Preferences(this._prefs);

  static Future<Preferences> load() async => Preferences(await SharedPreferences.getInstance());

  static const _serverKey = 'server';
  static const _serversKey = 'servers';
  static const _themeKey = 'theme';

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

  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_prefs.getString(_themeKey)] ?? ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }
}
