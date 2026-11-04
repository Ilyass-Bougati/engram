import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../api/errors.dart';
import '../api/models.dart';
import '../preferences.dart';
import 'token_store.dart';

sealed class SessionState {
  const SessionState();
}

/// No server chosen yet: the first launch.
class NoServer extends SessionState {
  const NoServer();
}

/// Restoring a stored session; usually a fraction of a second.
class Restoring extends SessionState {
  const Restoring();
}

class SignedOut extends SessionState {
  const SignedOut();
}

class SignedIn extends SessionState {
  const SignedIn(this.user);

  final User user;
}

/// The server couldn't be reached while restoring the session. The stored session is kept.
class Unavailable extends SessionState {
  const Unavailable(this.message);

  final String message;
}

/// The app's session, the counterpart of frontend/src/lib/auth.tsx. Screens read [state] and
/// [api]; choosing another server replaces the client.
///
/// Each server keeps its own sign-in on this device ([tokensFor] gives each its own store), so
/// switching back to a server picks up where you left off, and no token ever goes to a server
/// other than the one that issued it.
class SessionController extends ChangeNotifier {
  SessionController({
    required this._preferences,
    required this._tokensFor,
    this._httpClientFactory,
  });

  final Preferences _preferences;
  final TokenStore Function(Uri server) _tokensFor;
  final http.Client Function()? _httpClientFactory;

  SessionState _state = const Restoring();
  SessionState get state => _state;

  ApiClient? _api;

  /// The client for the chosen server. Only valid once a server is set.
  ApiClient get api => _api!;

  Uri? get server => _api?.server;

  /// Every server used on this device, most recently chosen first.
  List<Uri> get servers => [for (final server in _preferences.servers) Uri.parse(server)];

  void _set(SessionState state) {
    _state = state;
    notifyListeners();
  }

  ApiClient _newClient(Uri server, {TokenStore? tokens}) => ApiClient(
    server: server,
    tokens: tokens ?? _tokensFor(server),
    httpClient: _httpClientFactory?.call(),
  );

  void _use(Uri server) {
    _api?.close();
    _api = _newClient(server)..onSessionEnded = () => _set(const SignedOut());
  }

  /// Picks up the saved server and session on launch.
  Future<void> start() async {
    final saved = _preferences.server;
    if (saved == null) {
      _set(const NoServer());
      return;
    }
    _use(Uri.parse(saved));
    await restore();
  }

  Future<void> restore() async {
    _set(const Restoring());
    try {
      final session = await api.refreshSession();
      _set(session == null ? const SignedOut() : SignedIn(session.user));
    } on UserFacingError catch (error) {
      _set(Unavailable(error.message));
    }
  }

  /// Checks that [input] answers as an Engram server, then switches to it, signed in if this
  /// device still has a session there. Throws a [UserFacingError] to show next to the field.
  Future<void> chooseServer(String input) async {
    final server = normalizeServerUrl(input);
    final candidate = _newClient(server, tokens: MemoryTokenStore());
    try {
      await candidate.checkHealth();
    } finally {
      candidate.close();
    }
    await _preferences.setServer(server.toString());
    _use(server);
    await restore();
  }

  /// Signs out of [server] and takes it off the list. If it was the one in use, the app goes
  /// back to choosing a server.
  Future<void> forgetServer(Uri server) async {
    if (server == this.server) {
      await api.logout();
    } else {
      final client = _newClient(server);
      try {
        await client.logout();
      } finally {
        client.close();
      }
    }
    await _preferences.removeServer(server.toString());
    if (_preferences.server == null) {
      _api?.close();
      _api = null;
      _set(const NoServer());
    } else {
      notifyListeners();
    }
  }

  Future<void> signIn(String username, String password) async {
    final session = await api.login(username, password);
    _set(SignedIn(session.user));
  }

  Future<void> redeemInvite({
    required String token,
    required String username,
    required String password,
    required String timezone,
  }) async {
    final session = await api.redeemInvite(
      token: token,
      username: username,
      password: password,
      timezone: timezone,
    );
    _set(SignedIn(session.user));
  }

  Future<void> changePassword(String current, String next) async {
    final session = await api.changePassword(current, next);
    _set(SignedIn(session.user));
  }

  void userChanged(User user) => _set(SignedIn(user));

  Future<void> signOut() async {
    await api.logout();
    _set(const SignedOut());
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }
}
