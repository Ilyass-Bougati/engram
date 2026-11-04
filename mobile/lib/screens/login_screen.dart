import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/session.dart';
import '../widgets/form_page.dart';
import '../widgets/states.dart';
import 'invite_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.signIn(_username.text.trim(), _password.text);
      TextInput.finishAutofillContext();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.session.server;
    return FormPage(
      title: 'Sign in to Engram',
      intro: server?.host,
      footer: Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => InviteScreen(session: widget.session))),
            child: const Text('I have an invite'),
          ),
          TextButton(onPressed: widget.session.changeServer, child: const Text('Change server')),
        ],
      ),
      children: [
        TextField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _submit(),
        ),
        FormError(_error),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }
}
