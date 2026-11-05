import 'package:flutter/material.dart';

import 'auth/session.dart';
import 'preferences.dart';
import 'reminders/reminders.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/server_screen.dart';
import 'theme.dart';
import 'widgets/glass.dart';
import 'widgets/motion.dart';
import 'widgets/states.dart';

class EngramApp extends StatefulWidget {
  const EngramApp({
    super.key,
    required this.session,
    required this.preferences,
    required this.reminders,
  });

  final SessionController session;
  final Preferences preferences;
  final Reminders reminders;

  @override
  State<EngramApp> createState() => _EngramAppState();
}

class _EngramAppState extends State<EngramApp> {
  final _navigator = GlobalKey<NavigatorState>();

  SessionController get session => widget.session;
  Preferences get preferences => widget.preferences;

  @override
  void initState() {
    super.initState();
    session
      ..addListener(_closeScreensWhenSignedOut)
      ..addListener(_followSession);
  }

  @override
  void dispose() {
    session
      ..removeListener(_closeScreensWhenSignedOut)
      ..removeListener(_followSession);
    super.dispose();
  }

  // Reminders are for whoever is signed in. While restoring or offline they stay as they are,
  // so starting the app without a connection doesn't cancel them.
  void _followSession() {
    switch (session.state) {
      case SignedIn(:final user):
        widget.reminders.signedIn(user, session.api);
      case SignedOut() || NoServer():
        widget.reminders.signedOut();
      case Restoring() || Unavailable():
        break;
    }
  }

  // When the session ends (signed out, or expired mid-study), screens opened on top of the
  // home screen belong to it and close with it.
  void _closeScreensWhenSignedOut() {
    if (session.state is! SignedIn) _navigator.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        title: 'Engram',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: preferences.themeMode,
        themeAnimationDuration: Motion.base,
        themeAnimationCurve: Motion.ease,
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) =>
              _Root(session: session, preferences: preferences, reminders: widget.reminders),
        ),
      ),
    );
  }
}

/// Picks the screen for the session's state. Each switch rises in, like a page change.
class _Root extends StatelessWidget {
  const _Root({required this.session, required this.preferences, required this.reminders});

  final SessionController session;
  final Preferences preferences;
  final Reminders reminders;

  @override
  Widget build(BuildContext context) {
    final state = session.state;
    final Widget screen = switch (state) {
      NoServer() => ServerScreen(session: session),
      Restoring() => const Backdrop(child: LoadingState(label: 'Signing you in')),
      SignedOut() => LoginScreen(session: session),
      SignedIn() => HomeShell(session: session, preferences: preferences, reminders: reminders),
      Unavailable(:final message) => Backdrop(
        child: Scaffold(
          body: SafeArea(
            child: MessageState(
              icon: Icons.cloud_off_outlined,
              iconColor: context.colors.danger,
              title: "Engram isn't responding",
              message: message,
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: session.restore, child: const Text('Try again')),
                  OutlinedButton(
                    onPressed: () => openServerPicker(context, session),
                    child: const Text('Switch server'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    };
    return Backdrop(
      child: RiseIn(key: ValueKey(state.runtimeType), child: screen),
    );
  }
}
