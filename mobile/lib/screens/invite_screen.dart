import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../api/errors.dart';
import '../auth/session.dart';
import '../widgets/form_page.dart';
import '../widgets/states.dart';

/// The token in an invite link (`https://engram.example.com/invite/<token>`), or the token
/// itself when that is what was pasted.
({String token, String? host}) parseInvite(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme && uri.pathSegments.length >= 2) {
    final index = uri.pathSegments.lastIndexOf('invite');
    if (index != -1 && index + 1 < uri.pathSegments.length) {
      return (token: uri.pathSegments[index + 1], host: uri.host);
    }
  }
  return (token: text, host: null);
}

Future<String> _deviceTimezone() async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object {
    return 'UTC';
  }
}

/// Creating an account from an invite link an admin sent.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _link = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _token;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final controller in [_link, _username, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
    final invite = parseInvite(_link.text);
    final server = widget.session.server!;
    if (invite.token.isEmpty) {
      throw const UserFacingError('Paste the invite link your admin sent you.');
    }
    if (invite.host != null && invite.host != server.host) {
      throw UserFacingError(
        'This invite is for ${invite.host}, but the app is connected to ${server.host}. '
        'Change the server on the sign-in screen first.',
      );
    }
    // An unusable invite answers 404 with a sentence that says so.
    await widget.session.api.invite(invite.token);
    setState(() => _token = invite.token);
  });

  Future<void> _redeem() => _run(() async {
    if (_password.text != _confirm.text) {
      throw const UserFacingError(
        "The passwords don't match. Type the same password in both fields.",
      );
    }
    await widget.session.redeemInvite(
      token: _token!,
      username: _username.text.trim(),
      password: _password.text,
      timezone: await _deviceTimezone(),
    );
    TextInput.finishAutofillContext();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  });

  @override
  Widget build(BuildContext context) {
    if (_token == null) {
      return FormPage(
        showBack: true,
        title: 'Use an invite',
        intro: 'Accounts are invite-only. Paste the invite link your admin sent you.',
        children: [
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            decoration: const InputDecoration(labelText: 'Invite link'),
            onSubmitted: (_) => _check(),
          ),
          FormError(_error),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: Text(_busy ? 'Checking…' : 'Continue'),
          ),
        ],
      );
    }
    return FormPage(
      showBack: true,
      title: 'Create your account',
      intro: 'Usernames use letters, digits, dots, dashes and underscores. Passwords need at least 10 characters.',
      children: [
        TextField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'Username', counterText: ''),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        TextField(
          controller: _confirm,
          obscureText: true,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(labelText: 'Confirm password'),
          onSubmitted: (_) => _redeem(),
        ),
        FormError(_error),
        FilledButton(
          onPressed: _busy ? null : _redeem,
          child: Text(_busy ? 'Creating account…' : 'Create account'),
        ),
      ],
    );
  }
}
