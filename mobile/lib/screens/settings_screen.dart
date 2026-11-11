import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../api/errors.dart';
import '../auth/session.dart';
import '../preferences.dart';
import '../reminders/reminders.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'home_shell.dart';
import 'server_screen.dart';
import 'settings/reminder_settings.dart';

/// Theme, reminders, timezone, password and server: the web app's Settings page, plus the
/// phone-only reminders.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.preferences,
    required this.reminders,
  });

  final SessionController session;
  final Preferences preferences;
  final Reminders reminders;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: const Text('Settings'),
      // A Builder, so the padding is read below the scaffold, where it includes the top bar.
      body: Builder(
        builder: (context) => ListView(
          padding: underBars(context, const EdgeInsets.fromLTRB(16, 24, 16, 48)),
          children: [
            _Section(
              icon: Icons.contrast,
              title: 'Theme',
              description: 'Saved on this device.',
              child: ListenableBuilder(
                listenable: preferences,
                builder: (context, _) => SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final option in themeOptions)
                      ButtonSegment(
                        value: option.mode,
                        label: Text(option.label),
                        icon: Icon(option.icon, size: 18),
                      ),
                  ],
                  selected: {preferences.themeMode},
                  onSelectionChanged: (selection) => preferences.setThemeMode(selection.single),
                ),
              ),
            ),
            _Section(
              icon: Icons.notifications_outlined,
              title: 'Reminders',
              description:
                  "A nudge at these times each day, skipped once you've finished the day's "
                  'reviews.',
              child: ReminderSettings(reminders: reminders),
            ),
            _TimezoneSection(session: session),
            _PasswordSection(session: session),
            _Section(
              icon: Icons.dns_outlined,
              title: 'Server',
              description:
                  'Connected to ${session.server}. Each server keeps its own sign-in on this '
                  'device, so you can switch back and forth.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => openServerPicker(context, session),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Switch server'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _confirmSignOut(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showGlassSheet<bool>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sign out?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'This device forgets your session on ${session.server?.host}. Your progress is saved on the server.',
            style: TextStyle(color: sheet.colors.inkMuted),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(sheet).pop(true),
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(sheet).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    navigator.popUntil((route) => route.isFirst);
    await session.signOut();
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: c.pine),
                  const SizedBox(width: 8),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(description, style: TextStyle(fontSize: 14, color: c.inkMuted)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _TimezoneSection extends StatefulWidget {
  const _TimezoneSection({required this.session});

  final SessionController session;

  @override
  State<_TimezoneSection> createState() => _TimezoneSectionState();
}

class _TimezoneSectionState extends State<_TimezoneSection> {
  late final _timezone = TextEditingController(text: _userTimezone ?? '');
  bool _busy = false;
  Object? _error;
  bool _saved = false;

  String? get _userTimezone => switch (widget.session.state) {
    SignedIn(:final user) => user.timezone,
    _ => null,
  };

  @override
  void dispose() {
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _useDevice() async {
    try {
      _timezone.text = (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      setState(
        () => _error = const UserFacingError(
          "This device didn't say which timezone it's in. Type it instead.",
        ),
      );
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      final user = await widget.session.api.updateTimezone(_timezone.text.trim());
      widget.session.userChanged(user);
      if (mounted) setState(() => _saved = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      icon: Icons.schedule,
      title: 'Timezone',
      description: "Your study day starts at 4:00 here: that's when new cards unlock.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _timezone,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Timezone',
              hintText: 'Europe/Paris',
              suffixIcon: IconButton(
                tooltip: "Use this device's timezone",
                onPressed: _useDevice,
                icon: const Icon(Icons.my_location),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FormError(_error),
          if (_saved)
            Semantics(
              liveRegion: true,
              child: Text('Saved.', style: TextStyle(color: context.colors.pine)),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save timezone'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordSection extends StatefulWidget {
  const _PasswordSection({required this.session});

  final SessionController session;

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  Object? _error;
  bool _changed = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    setState(() {
      _error = null;
      _changed = false;
    });
    if (_next.text != _confirm.text) {
      setState(
        () => _error = const UserFacingError(
          "The new passwords don't match. Type the same password in both fields.",
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.session.changePassword(_current.text, _next.text);
      _current.clear();
      _next.clear();
      _confirm.clear();
      if (mounted) setState(() => _changed = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      icon: Icons.key_outlined,
      title: 'Password',
      description: 'Changing it signs you out on every other device and browser.',
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _current,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 10 characters.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Confirm new password'),
            ),
            const SizedBox(height: 12),
            FormError(_error),
            if (_changed)
              Semantics(
                liveRegion: true,
                child: Text(
                  'Password changed. Other devices are signed out.',
                  style: TextStyle(color: context.colors.pine),
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _change,
                child: Text(_busy ? 'Changing…' : 'Change password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
