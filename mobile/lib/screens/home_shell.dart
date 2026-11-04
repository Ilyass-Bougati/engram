import 'package:flutter/material.dart';

import '../auth/session.dart';
import '../preferences.dart';
import '../theme.dart';
import '../widgets/engram_mark.dart';
import '../widgets/glass.dart';
import '../widgets/motion.dart';
import 'decks_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

enum _Tab { decks, stats }

/// The signed-in app, laid out like the web app's AppShell: a glass top bar with the mark, the
/// Decks and Stats links and the account menu, over the current page.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.preferences});

  final SessionController session;
  final Preferences preferences;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Tab _tab = _Tab.decks;

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(session: widget.session, preferences: widget.preferences),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.session.state;
    final username = state is SignedIn ? state.user.username : '';
    return GlassScaffold(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const EngramMark(),
          const SizedBox(width: 8),
          const Text('Engram', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2)),
          const SizedBox(width: 16),
          _NavLink(
            icon: Icons.view_agenda_outlined,
            label: 'Decks',
            active: _tab == _Tab.decks,
            onTap: () => setState(() => _tab = _Tab.decks),
          ),
          const SizedBox(width: 4),
          _NavLink(
            icon: Icons.bar_chart,
            label: 'Stats',
            active: _tab == _Tab.stats,
            onTap: () => setState(() => _tab = _Tab.stats),
          ),
        ],
      ),
      actions: [
        _AccountButton(
          username: username,
          preferences: widget.preferences,
          onSettings: _openSettings,
          onSignOut: widget.session.signOut,
        ),
        const SizedBox(width: 8),
      ],
      // Each page rises in when you switch; changes within a page don't replay it.
      body: RiseIn(
        key: ValueKey(_tab),
        child: switch (_tab) {
          _Tab.decks => DecksScreen(api: widget.session.api),
          _Tab.stats => StatsScreen(api: widget.session.api),
        },
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.ink : c.inkMuted;
    // Narrow screens show the icon only; the label stays for screen readers, as on the web.
    final narrow = MediaQuery.sizeOf(context).width < 640;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            curve: Motion.ease,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? c.pineSoft : c.pineSoft.withValues(alpha: 0),
              borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                if (!narrow) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.username,
    required this.preferences,
    required this.onSettings,
    required this.onSignOut,
  });

  final String username;
  final Preferences preferences;
  final VoidCallback onSettings;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Builder(
      builder: (anchor) => Semantics(
        button: true,
        label: 'Account menu, $username',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
          onTap: () => showGlassMenu<void>(
            context: context,
            anchor: anchor,
            builder: (menu) => _AccountMenu(
              preferences: preferences,
              onSettings: () {
                Navigator.of(menu).pop();
                onSettings();
              },
              onSignOut: () {
                Navigator.of(menu).pop();
                onSignOut();
              },
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_circle_outlined, size: 18, color: c.inkMuted),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(
                    username,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink),
                  ),
                ),
                Icon(Icons.expand_more, size: 18, color: c.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const themeOptions = [
  (mode: ThemeMode.system, label: 'System', icon: Icons.brightness_auto_outlined),
  (mode: ThemeMode.light, label: 'Light', icon: Icons.light_mode_outlined),
  (mode: ThemeMode.dark, label: 'Dark', icon: Icons.dark_mode_outlined),
];

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.preferences,
    required this.onSettings,
    required this.onSignOut,
  });

  final Preferences preferences;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(IconData icon, String label, VoidCallback onTap, {bool checked = false}) => InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, color: c.ink)),
            ),
            if (checked) Icon(Icons.check, size: 16, color: c.pine),
          ],
        ),
      ),
    );
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(
              'Theme',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.inkMuted),
            ),
          ),
          for (final option in themeOptions)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: preferences.themeMode == option.mode,
              child: item(
                option.icon,
                option.label,
                () => preferences.setThemeMode(option.mode),
                checked: preferences.themeMode == option.mode,
              ),
            ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider()),
          item(Icons.settings_outlined, 'Settings', onSettings),
          item(Icons.logout, 'Sign out', onSignOut),
        ],
      ),
    );
  }
}
