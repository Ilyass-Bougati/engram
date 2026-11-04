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
/// [api]; a change of server or sign-in replaces the client.
class SessionController extends ChangeNotifier {
  SessionController({required this._preferences, required this._tokens, this._httpClientFactory});

  final Preferences _preferences;
  final TokenStore _tokens;
  final http.Client Function()? _httpClientFactory;

  SessionState _state = const Restoring();
  SessionState get state => _state;

  ApiClient? _api;

  /// The client for the chosen server. Only valid once a server is set.
  ApiClient get api => _api!;

  Uri? get server => _api?.server;

  void _set(SessionState state) {
    _state = state;
    notifyListeners();
  }

  ApiClient _clientFor(Uri server) {
    _api?.close();
    final client = ApiClient(
      server: server,
      tokens: _tokens,
      httpClient: _httpClientFactory?.call(),
    );
    client.onSessionEnded = () => _set(const SignedOut());
    return _api = client;
  }

  /// Picks up the saved server and session on launch.
  Future<void> start() async {
    final saved = _preferences.server;
    if (saved == null) {
      _set(const NoServer());
      return;
    }
    _clientFor(Uri.parse(saved));
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

  /// Checks [input] answers as an Engram server, then switches to it. Throws a
  /// [UserFacingError] to show next to the field.
  Future<void> chooseServer(String input) async {
    final server = normalizeServerUrl(input);
    final candidate = ApiClient(
      server: server,
      tokens: MemoryTokenStore(),
      httpClient: _httpClientFactory?.call(),
    );
    try {
      await candidate.checkHealth();
    } finally {
      candidate.close();
    }
    if (server.toString() != _preferences.server) {
      // A session belongs to one server; never send its token to another.
      await _api?.logout();
      await _tokens.clear();
    }
    await _preferences.setServer(server.toString());
    _clientFor(server);
    await restore();
  }

  /// Back to the server screen, to pick a different one.
  void changeServer() => _set(const NoServer());

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
