import 'package:flutter/material.dart';

import '../auth/session.dart';
import '../widgets/form_page.dart';
import '../widgets/states.dart';

/// First launch: which Engram server to use.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final _address = TextEditingController(text: widget.session.server?.toString() ?? '');
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.chooseServer(_address.text);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Connect to your server',
      intro: 'Engram is self-hosted. Enter the address you open it at in a browser.',
      children: [
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.url],
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'https://engram.example.com',
          ),
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
        FormError(_error),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Connecting…' : 'Continue'),
        ),
      ],
    );
  }
}
