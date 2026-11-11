import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../auth/session.dart';
import '../library.dart';
import '../preferences.dart';
import '../reminders/reminders.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/motion.dart';
import 'app_scope.dart';
import 'decks_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

const themeOptions = [
  (mode: ThemeMode.system, label: 'System', icon: Icons.brightness_auto_outlined),
  (mode: ThemeMode.light, label: 'Light', icon: Icons.light_mode_outlined),
  (mode: ThemeMode.dark, label: 'Dark', icon: Icons.dark_mode_outlined),
];

const _tabs = [
  (label: 'Home', icon: Icons.home_outlined, selected: Icons.home),
  (label: 'Decks', icon: Icons.layers_outlined, selected: Icons.layers),
  (label: 'Stats', icon: Icons.bar_chart_outlined, selected: Icons.bar_chart),
  (label: 'Settings', icon: Icons.settings_outlined, selected: Icons.settings),
];

/// The signed-in app: four tabs behind a glass bottom bar. Each tab keeps its own stack, so a
/// deck opened from Decks is still open after a look at Stats; tapping the tab you're on goes
/// back to its first page. Studying opens above the shell, full screen.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.session,
    required this.preferences,
    required this.reminders,
  });

  final SessionController session;
  final Preferences preferences;
  final Reminders reminders;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _navigators = [for (final _ in _tabs) GlobalKey<NavigatorState>()];
  late final Library _library;
  late User _user;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _library = Library(widget.session.api, reminders: widget.reminders);
    unawaited(_library.refresh());
    _user = (widget.session.state as SignedIn).user;
    widget.session.addListener(_followUser);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_followUser);
    _library.dispose();
    super.dispose();
  }

  // A changed timezone or password keeps the shell; the greeting follows the user.
  void _followUser() {
    if (widget.session.state case SignedIn(:final user)) setState(() => _user = user);
  }

  // Counts change with the clock (cards come due, a new study day starts): refresh on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_library.refresh());
  }

  void _select(int tab) {
    if (tab == _tab) {
      _navigators[tab].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _tab = tab);
    }
  }

  // Back closes pages within the tab first, then goes to Home, then leaves the app.
  void _back() {
    final navigator = _navigators[_tab].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else {
      unawaited(SystemNavigator.pop());
    }
  }

  Widget _page(int tab) => switch (tab) {
    0 => HomeScreen(user: _user),
    1 => const DecksScreen(),
    2 => const StatsScreen(),
    _ => SettingsScreen(
      session: widget.session,
      preferences: widget.preferences,
      reminders: widget.reminders,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppScope(
      api: widget.session.api,
      library: _library,
      goToTab: _select,
      rootNavigator: () => Navigator.of(context, rootNavigator: true),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: RiseOnChange(
            value: _tab,
            child: IndexedStack(
              index: _tab,
              children: [
                for (final (tab, _) in _tabs.indexed)
                  // Only the tab on show takes part in focus, semantics and tickers.
                  TickerMode(
                    enabled: tab == _tab,
                    child: ExcludeFocus(
                      excluding: tab != _tab,
                      child: Navigator(
                        key: _navigators[tab],
                        onGenerateRoute: (settings) =>
                            MaterialPageRoute<void>(settings: settings, builder: (_) => _page(tab)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: Glass(
            edges: const {AxisDirection.up},
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              selectedIndex: _tab,
              onDestinationSelected: _select,
              indicatorColor: c.pineSoft,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              animationDuration: Motion.of(context, Motion.base),
              destinations: [
                for (final tab in _tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selected, color: c.pine),
                    label: tab.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
