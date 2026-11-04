import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/token_store.dart';
import 'errors.dart';
import 'models.dart';

/// The cookie the backend keeps the refresh token in (backend/app/routers/auth.py).
const refreshCookie = 'engram_refresh';

const _csrfHeader = {'X-Engram-CSRF': '1'};
const _requestTimeout = Duration(seconds: 20);

// Matches the refresh cookie in a Set-Cookie header. package:http joins repeated headers with
// commas, and the Expires attribute holds a comma too, so the value is matched, not split out.
final _refreshCookiePattern = RegExp('(?:^|[,;]\\s*)$refreshCookie=("?)([^";,\\s]*)\\1');

/// The refresh token from a response's Set-Cookie header: the new value, an empty string when
/// the server cleared the cookie, or null when the response didn't touch it.
String? refreshTokenFromSetCookie(String? setCookie) {
  if (setCookie == null) return null;
  final match = _refreshCookiePattern.firstMatch(setCookie);
  return match?.group(2);
}

bool _isDevelopmentHost(String host) =>
    host == 'localhost' || host == '::1' || host == '10.0.2.2' || host.startsWith('127.');

/// Turns what someone typed as their server's address into the server's root URL.
///
/// Plain http is only accepted for this machine and the Android emulator's host, since the
/// refresh token travels in a request header and anyone on the path could read it.
Uri normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) {
    throw const UserFacingError("Enter your server's address, such as https://engram.example.com.");
  }
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || !(uri.isScheme('https') || uri.isScheme('http'))) {
    throw const UserFacingError(
      "That isn't a web address. Enter one such as https://engram.example.com.",
    );
  }
  if (uri.isScheme('http') && !_isDevelopmentHost(uri.host)) {
    throw const UserFacingError(
      'Use an https:// address. Plain http would send your sign-in over the network unencrypted.',
    );
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  // Someone may paste the API address itself.
  if (path.endsWith('/api')) path = path.substring(0, path.length - 4);
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path);
}

/// The Engram API, with the same session rules as frontend/src/lib/api.ts:
///
/// - The access token lives in memory only and goes out as a bearer token.
/// - The refresh token is kept in [TokenStore] (the OS keystore) and sent back as the cookie
///   the backend expects, with the CSRF header. Each refresh rotates it.
/// - On a 401 the client refreshes once and retries. Refreshes never overlap: presenting a
///   rotated refresh token again would end the whole sign-in.
class ApiClient {
  ApiClient({required this.server, required this._tokens, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// The server's root, as returned by [normalizeServerUrl].
  final Uri server;
  final TokenStore _tokens;
  final http.Client _http;

  String? _accessToken;
  Future<SessionResponse?>? _refreshInFlight;

  /// Called when a request finds the session over and refreshing can't restore it.
  void Function()? onSessionEnded;

  bool get hasAccessToken => _accessToken != null;

  Uri _url(String path) => server.replace(path: '${server.path}/api$path');

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, _url(path))..headers.addAll(headers);
    final token = _accessToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(_requestTimeout);
      return await http.Response.fromStream(streamed).timeout(_requestTimeout);
    } on http.ClientException {
      throw const ApiError(0, unreachableMessage);
    } on SocketException {
      throw const ApiError(0, unreachableMessage);
    } on HandshakeException {
      throw const ApiError(0, unreachableMessage);
    } on TimeoutException {
      throw const ApiError(0, unreachableMessage);
    }
  }

  static ApiError _errorFrom(http.Response response) {
    var detail = 'The server answered ${response.statusCode}. Try again in a moment.';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic> && body['detail'] is String) {
        detail = body['detail'] as String;
      }
    } on FormatException {
      // A proxy error page instead of JSON: keep the generic message.
    }
    return ApiError(response.statusCode, detail);
  }

  static Object? _decode(http.Response response) =>
      response.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));

  Future<void> _keepRefreshCookie(http.Response response) async {
    final token = refreshTokenFromSetCookie(response.headers['set-cookie']);
    if (token == null) return;
    if (token.isEmpty) {
      await _tokens.clear();
    } else {
      await _tokens.write(token);
    }
  }

  /// Starts a session from a response that carries one: sign-in, sign-up, password change.
  Future<SessionResponse> _startSession(http.Response response) async {
    await _keepRefreshCookie(response);
    final session = SessionResponse.fromJson(_decode(response)! as Json);
    _accessToken = session.accessToken;
    return session;
  }

  Future<Object?> request(String method, String path, {Object? body}) async {
    var response = await _send(method, path, body: body);
    if (response.statusCode == 401 && _accessToken != null) {
      // The access token expired (15 minutes): refresh once and retry.
      final session = await refreshSession();
      if (session == null) {
        onSessionEnded?.call();
        throw const ApiError(401, sessionExpiredMessage);
      }
      response = await _send(method, path, body: body);
    }
    if (response.statusCode >= 400) throw _errorFrom(response);
    return _decode(response);
  }

  /// Exchanges the stored refresh token for a new session. Returns null when there is no
  /// session to restore. Concurrent callers share one request.
  Future<SessionResponse?> refreshSession() {
    return _refreshInFlight ??= _postRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<SessionResponse?> _postRefresh() async {
    final stored = await _tokens.read();
    if (stored == null) {
      _accessToken = null;
      return null;
    }
    final response = await _send(
      'POST',
      '/auth/refresh',
      headers: {..._csrfHeader, 'Cookie': '$refreshCookie=$stored'},
    );
    if (response.statusCode == 401) {
      _accessToken = null;
      await _tokens.clear();
      return null;
    }
    if (response.statusCode >= 400) throw _errorFrom(response);
    return _startSession(response);
  }

  Future<SessionResponse> login(String username, String password) async {
    final response = await _send(
      'POST',
      '/auth/login',
      body: {'username': username, 'password': password},
    );
    if (response.statusCode >= 400) throw _errorFrom(response);
    return _startSession(response);
  }

  Future<InviteStatus> invite(String token) async =>
      InviteStatus.fromJson(await request('GET', '/invites/${Uri.encodeComponent(token)}') as Json);

  Future<SessionResponse> redeemInvite({
    required String token,
    required String username,
    required String password,
    required String timezone,
  }) async {
    final response = await _send(
      'POST',
      '/invites/${Uri.encodeComponent(token)}/redeem',
      body: {'username': username, 'password': password, 'timezone': timezone},
    );
    if (response.statusCode >= 400) throw _errorFrom(response);
    return _startSession(response);
  }

  /// Ends this sign-in on the server and forgets it here. Succeeds offline too: the stored
  /// token is dropped either way.
  Future<void> logout() async {
    final stored = await _tokens.read();
    _accessToken = null;
    await _tokens.clear();
    if (stored == null) return;
    try {
      await _send(
        'POST',
        '/auth/logout',
        headers: {..._csrfHeader, 'Cookie': '$refreshCookie=$stored'},
      );
    } on ApiError {
      // Offline: the token is gone from this device and expires on the server by itself.
    }
  }

  Future<User> me() async => User.fromJson(await request('GET', '/me') as Json);

  Future<User> updateTimezone(String timezone) async =>
      User.fromJson(await request('PATCH', '/me', body: {'timezone': timezone}) as Json);

  /// Changes the password. Every other session ends; this one continues with a new token pair.
  Future<SessionResponse> changePassword(String current, String next) async {
    final body = {'current_password': current, 'new_password': next};
    var response = await _send('POST', '/me/password', body: body);
    if (response.statusCode == 401 && _accessToken != null) {
      if (await refreshSession() == null) {
        onSessionEnded?.call();
        throw const ApiError(401, sessionExpiredMessage);
      }
      response = await _send('POST', '/me/password', body: body);
    }
    if (response.statusCode >= 400) throw _errorFrom(response);
    return _startSession(response);
  }

  Future<List<Deck>> decks() async => [
    for (final deck in await request('GET', '/decks') as List<dynamic>) Deck.fromJson(deck as Json),
  ];

  Future<Deck> deck(String deckId) async =>
      Deck.fromJson(await request('GET', '/decks/$deckId') as Json);

  Future<StudyNext> studyNext(String deckId) async =>
      StudyNext.fromJson(await request('GET', '/decks/$deckId/study/next') as Json);

  /// Rates the card just studied (1 Again, 2 Hard, 3 Good, 4 Easy) and returns the next one.
  Future<StudyNext> rate(String deckId, String cardId, int rating) async => StudyNext.fromJson(
    await request('POST', '/decks/$deckId/reviews', body: {'card_id': cardId, 'rating': rating})
        as Json,
  );

  Future<QuizResult> answerQuiz(String deckId, String cardId, List<String> optionIds) async =>
      QuizResult.fromJson(
        await request(
          'POST',
          '/decks/$deckId/reviews/quiz-answer',
          body: {'card_id': cardId, 'selected_option_ids': optionIds},
        ) as Json,
      );

  Future<Stats> stats() async => Stats.fromJson(await request('GET', '/me/stats') as Json);

  /// Checks that [server] answers like an Engram backend.
  Future<void> checkHealth() async {
    final response = await _send('GET', '/health');
    if (response.statusCode != 200) {
      throw const UserFacingError(
        'That address answered, but not like an Engram server. Check it and try again.',
      );
    }
  }

  void close() => _http.close();
}
