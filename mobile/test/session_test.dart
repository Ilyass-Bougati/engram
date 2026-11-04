import 'dart:convert';

import 'package:engram_mobile/api/errors.dart';
import 'package:engram_mobile/auth/session.dart';
import 'package:engram_mobile/auth/token_store.dart';
import 'package:engram_mobile/preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two fake Engram servers. Each issues its own refresh tokens and only accepts those.
class _Servers {
  final requests = <http.Request>[];
  final issued = <String, Set<String>>{'a.test': {}, 'b.test': {}};
  var _count = 0;

  http.Response _session(String host) {
    final token = '$host-token-${_count++}';
    issued[host]!.add(token);
    return http.Response(
      jsonEncode({
        'access_token': 'access',
        'user': {
          'id': 'u',
          'username': 'alice@$host',
          'role': 'user',
          'timezone': 'UTC',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
      200,
      headers: {
        'set-cookie': 'engram_refresh=$token; Path=/api/auth',
        'content-type': 'application/json',
      },
    );
  }

  http.Client client() => MockClient((request) async {
    requests.add(request);
    final host = request.url.host;
    switch (request.url.path) {
      case '/api/health':
        return http.Response('{"status":"ok"}', 200);
      case '/api/auth/login':
        return _session(host);
      case '/api/auth/refresh':
        final token = RegExp(r'engram_refresh=(.*)')
            .firstMatch(request.headers['Cookie'] ?? '')?[1];
        if (token == null || !issued[host]!.remove(token)) {
          return http.Response('{"detail":"Your session has expired. Sign in again."}', 401);
        }
        return _session(host);
      case '/api/auth/logout':
        final token = RegExp(r'engram_refresh=(.*)')
            .firstMatch(request.headers['Cookie'] ?? '')?[1];
        issued[host]!.remove(token);
        return http.Response('', 204);
    }
    return http.Response('{"detail":"Not found."}', 404);
  });
}

void main() {
  late _Servers servers;
  late Map<Uri, MemoryTokenStore> stores;
  late SessionController session;

  Future<SessionController> launch() async {
    final controller = SessionController(
      preferences: await Preferences.load(),
      tokensFor: (server) => stores.putIfAbsent(server, MemoryTokenStore.new),
      httpClientFactory: servers.client,
    );
    await controller.start();
    return controller;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    servers = _Servers();
    stores = {};
    session = await launch();
  });

  String? username() => switch (session.state) {
    SignedIn(:final user) => user.username,
    _ => null,
  };

  test('first launch asks for a server and checks the address', () async {
    expect(session.state, isA<NoServer>());
    await expectLater(session.chooseServer('http://a.test'), throwsA(isA<UserFacingError>()));
    expect(servers.requests, isEmpty);

    await session.chooseServer('a.test');
    expect(servers.requests.single.url.toString(), 'https://a.test/api/health');
    expect(session.state, isA<SignedOut>());
    expect(session.servers, [Uri.parse('https://a.test')]);
  });

  test('each server keeps its own sign-in, and tokens never cross servers', () async {
    await session.chooseServer('a.test');
    await session.signIn('alice', 'pw');
    expect(username(), 'alice@a.test');

    await session.chooseServer('https://b.test');
    expect(session.state, isA<SignedOut>(), reason: 'no session on b.test yet');
    await session.signIn('alice', 'pw');
    expect(username(), 'alice@b.test');
    expect(session.servers, [Uri.parse('https://b.test'), Uri.parse('https://a.test')]);

    await session.chooseServer('https://a.test');
    expect(username(), 'alice@a.test', reason: 'switching back restores the session');

    for (final request in servers.requests) {
      final cookie = request.headers['Cookie'];
      if (cookie != null) expect(cookie, contains('${request.url.host}-token'));
    }

    // Relaunching picks up the server last chosen, still signed in.
    session = await launch();
    expect(username(), 'alice@a.test');
  });

  test(
    'forgetting a server signs out of it; forgetting the one in use asks for a server',
    () async {
      await session.chooseServer('a.test');
      await session.signIn('alice', 'pw');
      await session.chooseServer('b.test');
      await session.signIn('alice', 'pw');

      await session.forgetServer(Uri.parse('https://a.test'));
      expect(stores[Uri.parse('https://a.test')]!.token, isNull);
      expect(servers.issued['a.test'], isEmpty, reason: 'revoked on the server');
      expect(session.servers, [Uri.parse('https://b.test')]);
      expect(username(), 'alice@b.test');

      await session.forgetServer(Uri.parse('https://b.test'));
      expect(session.state, isA<NoServer>());
      expect(session.servers, isEmpty);
      expect(servers.issued['b.test'], isEmpty);
    },
  );
}
