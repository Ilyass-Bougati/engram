import 'dart:convert';

import 'package:engram_mobile/api/client.dart';
import 'package:engram_mobile/auth/token_store.dart';
import 'package:engram_mobile/library.dart';
import 'package:engram_mobile/screens/app_scope.dart';
import 'package:engram_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef Handler = Object? Function(http.Request request);

/// A fake Engram server: routes by "METHOD /api/path" to a handler that returns JSON, or throws
/// an [http.Response] to answer with an error.
class FakeApi {
  FakeApi(this.routes);

  final Map<String, Handler> routes;
  final requests = <http.Request>[];

  Iterable<http.Request> called(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);

  ApiClient client() => ApiClient(
    server: Uri.parse('https://engram.test'),
    tokens: MemoryTokenStore(),
    httpClient: httpClient(),
  );

  http.Client httpClient() => MockClient((request) async {
    requests.add(request);
    final handler = routes['${request.method} ${request.url.path}'];
    if (handler == null) {
      return http.Response('{"detail":"Not found."}', 404);
    }
    try {
      return http.Response(
        jsonEncode(handler(request)),
        200,
        headers: {'content-type': 'application/json'},
      );
    } on http.Response catch (error) {
      return error;
    }
  });
}

Map<String, Object?> deckJson(
  String id,
  String name, {
  int due = 0,
  int fresh = 0,
  int cards = 10,
  int limit = 20,
  String role = 'owner',
  String description = '',
}) => {
  'id': id,
  'name': name,
  'description': description,
  'role': role,
  'card_count': cards,
  'due_count': due,
  'new_count': fresh,
  'new_cards_per_day': limit,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Map<String, Object?> statsJson({int streak = 3, int today = 12, int reviews = 40}) => {
  'activity': {
    'today': '2026-11-11',
    'days': [
      {'date': '2026-11-11', 'reviews': today},
    ],
    'current_streak': streak,
    'longest_streak': 9,
    'total_reviews': reviews,
    'days_studied': 7,
  },
  'retention_last_30_days': {'reviews': 40, 'remembered': 36},
  'retention_by_month': [
    for (var m = 1; m <= 12; m++)
      {
        'month': '${m < 12 ? 2025 : 2026}-${(m < 12 ? m + 1 : 1).toString().padLeft(2, '0')}',
        'reviews': m > 9 ? 10 * m : 0,
        'remembered': m > 9 ? 8 * m : 0,
      },
  ],
  'states': {'new': 5, 'learning': 1, 'young': 3, 'mature': 1},
  'decks': <Object>[],
};

/// Shows [child] inside an [AppScope] backed by [api], with its library loaded, the way the home
/// shell provides it. Returns the library and the list of tabs [AppScope.goToTab] was sent.
Future<(Library, List<int>)> pumpInScope(WidgetTester tester, FakeApi api, Widget child) async {
  final client = api.client();
  final library = Library(client);
  final tabs = <int>[];
  await tester.runAsync(library.refresh);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      // Reduced motion: the suggestion's swirl holds still, so pumpAndSettle can settle.
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: Builder(
        builder: (context) => AppScope(
          api: client,
          library: library,
          goToTab: tabs.add,
          rootNavigator: () => Navigator.of(context, rootNavigator: true),
          child: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (library, tabs);
}
