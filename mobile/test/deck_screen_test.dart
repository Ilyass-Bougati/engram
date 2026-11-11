import 'dart:convert';

import 'package:engram_mobile/screens/deck_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fake_api.dart';

Map<String, Object?> _basic(String id, String front, {List<String> tags = const []}) => {
  'id': id,
  'type': 'basic',
  'front': front,
  'back': 'Answer to $front',
  'tags': tags,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Map<String, Object?> _quiz({bool withKey = true}) => {
  'id': 'q',
  'type': 'quiz',
  'question': 'Which is a **verb**?',
  'select_all': false,
  'options': [
    {'id': 'o1', 'text': 'run', 'correct': ?(withKey ? true : null)},
    {'id': 'o2', 'text': 'blue', 'correct': ?(withKey ? false : null)},
  ],
  'explanation': ?(withKey ? 'Run is an action.' : null),
  'tags': ['grammar'],
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

void main() {
  late FakeApi api;
  late bool withKey;

  setUp(() {
    withKey = true;
    api = FakeApi({
      'GET /api/decks': (_) => [
        deckJson('d', 'Languages::Spanish', due: 3, fresh: 2, cards: 3, role: 'viewer'),
      ],
      'GET /api/me/stats': (_) => statsJson(),
      'GET /api/decks/d/tags': (_) => [
        {'tag': 'grammar', 'card_count': 1},
        {'tag': 'food', 'card_count': 2},
      ],
      'GET /api/decks/d/cards': (request) {
        final q = request.url.queryParameters;
        if (q['q'] == 'nothing') {
          return {'cards': <Object>[], 'next_cursor': null};
        }
        if (q['tag'] == 'grammar') {
          return {
            'cards': [_quiz(withKey: withKey)],
            'next_cursor': null,
          };
        }
        if (q['cursor'] == 'page2') {
          return {
            'cards': [
              _basic('c3', 'leche', tags: ['food']),
            ],
            'next_cursor': null,
          };
        }
        return {
          'cards': [
            _basic('c1', '# hola'),
            _basic('c2', 'agua', tags: ['food']),
          ],
          'next_cursor': 'page2',
        };
      },
      'PUT /api/decks/d/me': (request) => deckJson('d', 'Languages::Spanish'),
    });
  });

  testWidgets('shows the deck, pages through its cards, and filters them', (tester) async {
    // A tall phone, so the whole page fits.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpInScope(tester, api, const DeckScreen(deckId: 'd'));
    expect(find.text('Languages'), findsOneWidget);
    expect(find.text('3 due · 2 new · 3 cards · shared with you as viewer'), findsOneWidget);
    expect(find.textContaining('hola', findRichText: true), findsOneWidget);
    expect(find.text('food (2)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Show more cards'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Show more cards'));
    await tester.pumpAndSettle();
    expect(find.textContaining('leche', findRichText: true), findsOneWidget);
    expect(find.text('Show more cards'), findsNothing);
    expect(api.requests.last.url.queryParameters, {'cursor': 'page2'});

    await tester.scrollUntilVisible(
      find.text('grammar (1)'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('grammar (1)'));
    await tester.pumpAndSettle();
    expect(api.requests.last.url.queryParameters, {'tag': 'grammar'});
    expect(find.text('Multiple choice · 2 options · grammar'), findsOneWidget);

    await tester.ensureVisible(find.text('All tags'));
    await tester.tap(find.text('All tags'));
    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(api.requests.last.url.queryParameters, {'q': 'nothing'});
    expect(find.text('No cards match'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('agua', findRichText: true),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('agua', findRichText: true), findsOneWidget);
    expect(api.requests.last.url.queryParameters, isEmpty, reason: 'search and tag cleared');
  });

  testWidgets('a quiz card shows its key only when the server sends it', (tester) async {
    for (final key in [true, false]) {
      withKey = key;
      await tester.pumpWidget(const SizedBox());
      await pumpInScope(tester, api, const DeckScreen(deckId: 'd'));
      await tester.tap(find.text('grammar (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('verb', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Correct'), key ? findsOneWidget : findsNothing);
      expect(find.text('Explanation'), key ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('sets your new-card limit on the deck', (tester) async {
    await pumpInScope(tester, api, const DeckScreen(deckId: 'd'));
    await tester.tap(find.text('New cards per day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a number of new cards from 0 to 9999.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '35');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(jsonDecode(api.called('PUT', '/api/decks/d/me').single.body), {'new_cards_per_day': 35});
  });

  testWidgets('shows the server sentence when saving the limit fails', (tester) async {
    api.routes['PUT /api/decks/d/me'] = (_) =>
        throw http.Response('{"detail":"That limit is too high."}', 422);
    await pumpInScope(tester, api, const DeckScreen(deckId: 'd'));
    await tester.tap(find.text('New cards per day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('That limit is too high.'), findsOneWidget);
  });
}
