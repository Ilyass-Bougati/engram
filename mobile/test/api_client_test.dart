import 'dart:convert';

import 'package:engram_mobile/api/client.dart';
import 'package:engram_mobile/api/errors.dart';
import 'package:engram_mobile/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = {
  'id': 'u1',
  'username': 'alice',
  'role': 'user',
  'timezone': 'Europe/Paris',
  'created_at': '2026-01-01T00:00:00Z',
};

http.Response _json(Object body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

String _cookie(String value) =>
    'engram_refresh=$value; HttpOnly; Max-Age=2592000; Path=/api/auth; SameSite=lax; Secure; '
    'expires=Fri, 04 Dec 2026 12:00:00 GMT';

void main() {
  group('refreshTokenFromSetCookie', () {
    test('reads the value, also next to other cookies and an Expires comma', () {
      expect(refreshTokenFromSetCookie(_cookie('abc-_123')), 'abc-_123');
      expect(refreshTokenFromSetCookie('other=1; Path=/, ${_cookie('xyz')}'), 'xyz');
    });

    test('sees a cleared cookie and ignores responses without one', () {
      expect(
        refreshTokenFromSetCookie(
          'engram_refresh=""; expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=/api/auth',
        ),
        '',
      );
      expect(refreshTokenFromSetCookie(null), isNull);
      expect(refreshTokenFromSetCookie('not_engram_refresh=1'), isNull);
    });
  });

  group('normalizeServerUrl', () {
    test('adds https, strips slashes and a pasted /api', () {
      expect(normalizeServerUrl('engram.example.com/').toString(), 'https://engram.example.com');
      expect(
        normalizeServerUrl(' https://example.com/engram/api/ ').toString(),
        'https://example.com/engram',
      );
    });

    test('refuses plain http except for this machine and the emulator host', () {
      expect(
        () => normalizeServerUrl('http://engram.example.com'),
        throwsA(isA<UserFacingError>()),
      );
      expect(normalizeServerUrl('http://10.0.2.2:6767').toString(), 'http://10.0.2.2:6767');
      expect(normalizeServerUrl('http://127.0.0.1:6767').toString(), 'http://127.0.0.1:6767');
      expect(() => normalizeServerUrl('ftp://x'), throwsA(isA<UserFacingError>()));
      expect(() => normalizeServerUrl(''), throwsA(isA<UserFacingError>()));
    });
  });

  group('ApiClient', () {
    late MemoryTokenStore tokens;
    late List<http.Request> requests;

    ApiClient client(Future<http.Response> Function(http.Request request) handler) {
      return ApiClient(
        server: Uri.parse('https://engram.test'),
        tokens: tokens,
        httpClient: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      );
    }

    setUp(() {
      tokens = MemoryTokenStore();
      requests = [];
    });

    test('sign-in keeps the refresh cookie and sends the access token after', () async {
      final api = client((request) async {
        if (request.url.path == '/api/auth/login') {
          return _json(
            {'access_token': 'access-1', 'user': _user},
            headers: {'set-cookie': _cookie('refresh-1')},
          );
        }
        return _json([]);
      });
      final session = await api.login('alice', 'correct horse');
      expect(session.user.username, 'alice');
      expect(tokens.token, 'refresh-1');
      await api.decks();
      expect(requests.last.headers['Authorization'], 'Bearer access-1');
    });

    test(
      'an expired access token is refreshed once with the cookie, then the request retried',
      () async {
        tokens.token = 'refresh-1';
        var access = 'stale';
        final api = client((request) async {
          switch (request.url.path) {
            case '/api/auth/refresh':
              expect(request.headers['Cookie'], 'engram_refresh=refresh-1');
              expect(request.headers['X-Engram-CSRF'], '1');
              access = 'fresh';
              return _json(
                {'access_token': 'fresh', 'user': _user},
                headers: {'set-cookie': _cookie('refresh-2')},
              );
            case '/api/auth/login':
              return _json({'access_token': 'stale', 'user': _user});
            default:
              return request.headers['Authorization'] == 'Bearer $access'
                  ? _json([])
                  : _json({'detail': 'Sign in again.'}, status: 401);
          }
        });
        await api.login('alice', 'pw');
        access = 'other';
        expect(await api.decks(), isEmpty);
        expect(requests.where((r) => r.url.path == '/api/auth/refresh'), hasLength(1));
        expect(tokens.token, 'refresh-2');
        expect(requests.last.headers['Authorization'], 'Bearer fresh');
      },
    );

    test('concurrent 401s share one refresh, so a rotated token is never replayed', () async {
      tokens.token = 'refresh-1';
      final api = client((request) async {
        if (request.url.path == '/api/auth/login') {
          return _json({'access_token': 'stale', 'user': _user});
        }
        if (request.url.path == '/api/auth/refresh') {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return _json(
            {'access_token': 'fresh', 'user': _user},
            headers: {'set-cookie': _cookie('refresh-2')},
          );
        }
        return request.headers['Authorization'] == 'Bearer fresh'
            ? _json(<Object>[])
            : _json({'detail': 'x'}, status: 401);
      });
      await api.login('alice', 'pw');
      await Future.wait([api.decks(), api.decks(), api.decks()]);
      expect(requests.where((r) => r.url.path == '/api/auth/refresh'), hasLength(1));
    });

    test('a refused refresh ends the session and forgets the token', () async {
      tokens.token = 'refresh-1';
      var ended = false;
      final api = client((request) async {
        if (request.url.path == '/api/auth/login') {
          return _json({'access_token': 'stale', 'user': _user});
        }
        return _json({'detail': 'Your session has expired. Sign in again.'}, status: 401);
      })..onSessionEnded = () => ended = true;
      await api.login('alice', 'pw');
      await expectLater(
        api.decks(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      expect(ended, isTrue);
      expect(tokens.token, isNull);
    });

    test('errors carry the server sentence, or a generic one for a proxy page', () async {
      final api = client(
        (request) async => request.url.path == '/api/decks'
            ? _json({'detail': 'This deck is gone.'}, status: 404)
            : http.Response('<html>Bad gateway</html>', 502),
      );
      await expectLater(
        api.decks(),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'This deck is gone.')),
      );
      await expectLater(
        api.stats(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            'The server answered 502. Try again in a moment.',
          ),
        ),
      );
    });

    test('an unreachable server says so', () async {
      final api = client((request) async => throw http.ClientException('Connection refused'));
      await expectLater(
        api.decks(),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', unreachableMessage)),
      );
    });

    test('logout revokes on the server with the cookie and forgets the token', () async {
      tokens.token = 'refresh-1';
      final api = client((request) async => http.Response('', 204));
      await api.logout();
      expect(requests.single.url.path, '/api/auth/logout');
      expect(requests.single.headers['Cookie'], 'engram_refresh=refresh-1');
      expect(requests.single.headers['X-Engram-CSRF'], '1');
      expect(tokens.token, isNull);
    });

    test('restoring without a stored token asks nothing of the server', () async {
      final api = client((request) async => fail('no request expected'));
      expect(await api.refreshSession(), isNull);
      expect(requests, isEmpty);
    });

    test('collection routes pass the path as a query parameter', () async {
      final api = client((request) async => _json({'card': null, 'due_count': 0, 'new_count': 0}));
      await api.studyNext(const CollectionScope('Java::Day 1'));
      expect(requests.last.url.path, '/api/collections/study/next');
      expect(requests.last.url.query, 'path=Java%3A%3ADay+1');
      expect(requests.last.url.queryParameters, {'path': 'Java::Day 1'});

      await api.studyNext(const DeckScope('d1'));
      expect(requests.last.url.toString(), 'https://engram.test/api/decks/d1/study/next');
    });

    test('new-card limits go to the deck or the collection', () async {
      final api = client(
        (request) async => request.url.path.startsWith('/api/collections')
            ? _json({'path': 'Java', 'decks': <Object>[]})
            : _json({
                'id': 'd1',
                'name': 'Java',
                'description': '',
                'role': 'owner',
                'card_count': 1,
                'due_count': 0,
                'new_count': 0,
                'new_cards_per_day': 30,
              }),
      );
      await api.setDeckLimit('d1', 30);
      expect(requests.last.method, 'PUT');
      expect(requests.last.url.path, '/api/decks/d1/me');
      expect(jsonDecode(requests.last.body), {'new_cards_per_day': 30});

      await api.setCollectionLimit('Java', 12);
      expect(requests.last.url.path, '/api/collections/me');
      expect(requests.last.url.queryParameters, {'path': 'Java'});
      expect(jsonDecode(requests.last.body), {'new_cards_per_day': 12});
    });

    test('card pages pass only the filters in use', () async {
      final api = client((request) async => _json({'cards': <Object>[], 'next_cursor': null}));
      await api.cards('d1');
      expect(requests.last.url.query, isEmpty);
      await api.cards('d1', q: 'verb', tag: 'grammar', cursor: '2026-01-01_c9');
      expect(requests.last.url.queryParameters, {
        'q': 'verb',
        'tag': 'grammar',
        'cursor': '2026-01-01_c9',
      });
    });
  });
}
