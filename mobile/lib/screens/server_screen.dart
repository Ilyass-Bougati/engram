import 'package:flutter/material.dart';

import '../auth/session.dart';
import '../theme.dart';
import '../widgets/form_page.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';

/// Opens the server picker over the current screen, from Settings, sign-in or an error.
Future<void> openServerPicker(BuildContext context, SessionController session) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ServerScreen(session: session)));

/// Which Engram server to use: one this device used before, or a new address. Shown on first
/// launch, and opened from Settings or the sign-in screen to switch. Each server keeps its own
/// sign-in, so switching back doesn't mean signing in again.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _address = TextEditingController();

  /// The server being connected to or forgotten, or '' for the address field.
  String? _busy;
  Object? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _run(String which, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _choose(String which, String address) =>
      _run(which, () => widget.session.chooseServer(address));

  Future<void> _forget(Uri server) async {
    final current = server == widget.session.server;
    final confirmed = await showGlassSheet<bool>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Forget ${server.host}?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            current
                ? 'This signs you out of it and takes it off the list. You pick a server next.'
                : 'This signs you out of it and takes it off the list.',
            style: TextStyle(color: sheet.colors.inkMuted),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(sheet).pop(true),
            child: const Text('Forget server'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(sheet).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(server.toString(), () => widget.session.forgetServer(server));
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.session.servers;
    final current = widget.session.server;
    final pushed = Navigator.of(context).canPop();
    return FormPage(
      showBack: pushed,
      title: servers.isEmpty ? 'Connect to your server' : 'Choose a server',
      intro: servers.isEmpty
          ? 'Engram is self-hosted. Enter the address you open it at in a browser.'
          : 'Each server keeps its own sign-in on this device.',
      children: [
        if (servers.isNotEmpty)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, server) in servers.indexed) ...[
                  if (index > 0) const Divider(),
                  _ServerTile(
                    server: server,
                    current: server == current,
                    busy: _busy == server.toString(),
                    enabled: _busy == null,
                    onTap: () => _choose(server.toString(), server.toString()),
                    onForget: () => _forget(server),
                  ),
                ],
              ],
            ),
          ),
        if (servers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              header: true,
              child: Text(
                'Add a server',
                style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
              ),
            ),
          ),
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
          onSubmitted: (_) => _choose('', _address.text),
        ),
        FormError(_error),
        FilledButton(
          onPressed: _busy == null ? () => _choose('', _address.text) : null,
          child: Text(_busy == '' ? 'Connecting…' : 'Connect'),
        ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.current,
    required this.busy,
    required this.enabled,
    required this.onTap,
    required this.onForget,
  });

  final Uri server;
  final bool current;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: Icon(current ? Icons.check_circle : Icons.dns_outlined, color: c.pine),
      // Host, port and path: two servers can share a host.
      title: Text(
        '${server.authority}${server.path}',
        style: const TextStyle(fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: busy || current || server.isScheme('http')
          ? Text(
              busy
                  ? 'Connecting…'
                  : [
                      if (current) 'In use',
                      if (server.isScheme('http')) 'http, for development',
                    ].join(' · '),
              style: TextStyle(color: c.inkMuted),
            )
          : null,
      trailing: IconButton(
        tooltip: 'Forget ${server.host}',
        onPressed: enabled ? onForget : null,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
