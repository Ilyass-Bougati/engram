import 'dart:convert';

import 'package:engram_mobile/screens/collection_screen.dart';
import 'package:engram_mobile/screens/decks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  late List<Map<String, Object?>> decks;
  late FakeApi api;

  setUp(() {
    decks = [
      deckJson('a', 'Java::Day 1', due: 2, limit: 20),
      deckJson('b', 'Java::Extras::Quirks', fresh: 4, limit: 20),
      deckJson('c', 'Spanish', due: 1),
    ];
    api = FakeApi({
      'GET /api/decks': (_) => decks,
      'GET /api/me/stats': (_) => statsJson(),
      'GET /api/collections/study/next': (_) => {
        'card': null,
        'due_count': 0,
        'new_count': 0,
        'next_due_at': null,
      },
      'PUT /api/collections/me': (request) {
        final limit = (jsonDecode(request.body) as Map)['new_cards_per_day'] as int;
        decks = [
          for (final deck in decks)
            if ((deck['name']! as String).startsWith('Java'))
              {...deck, 'new_cards_per_day': limit}
            else
              deck,
        ];
        return {'path': 'Java', 'decks': <Object>[]};
      },
    });
  });

  testWidgets('the Decks tab drills into collections, then sub-collections', (tester) async {
    await pumpInScope(tester, api, const DecksScreen());
    expect(find.text('Java'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);
    expect(find.text('Day 1'), findsNothing, reason: 'inside the collection, not inline');

    await tester.tap(find.text('Java'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('2 due · 4 new · 2 decks · 20 cards'), findsOneWidget);

    await tester.tap(find.text('Extras'));
    await tester.pumpAndSettle();
    expect(find.text('Quirks'), findsOneWidget);
    expect(find.text('Java'), findsWidgets, reason: 'the path above the title');
  });

  testWidgets('Study studies the whole collection', (tester) async {
    await pumpInScope(tester, api, const CollectionScreen(collectionKey: 'Java'));
    await tester.tap(find.widgetWithText(FilledButton, 'Study'));
    await tester.pumpAndSettle();
    final study = api.called('GET', '/api/collections/study/next').single;
    expect(study.url.queryParameters, {'path': 'Java'});
    expect(find.text('Nothing to study right now'), findsOneWidget);
  });

  testWidgets('sets the new-card limit on every deck in the collection', (tester) async {
    decks[1] = {...decks[1], 'new_cards_per_day': 5};
    await pumpInScope(tester, api, const CollectionScreen(collectionKey: 'Java'));
    await tester.tap(find.text('New cards per day'));
    await tester.pumpAndSettle();
    expect(find.text('New cards per day, for each deck'), findsOneWidget);
    expect(find.text('Mixed'), findsOneWidget, reason: 'the decks have different limits');

    await tester.enterText(find.byType(TextField), '15');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final put = api.called('PUT', '/api/collections/me').single;
    expect(put.url.queryParameters, {'path': 'Java'});
    expect(jsonDecode(put.body), {'new_cards_per_day': 15});
    expect(api.called('GET', '/api/decks'), hasLength(2), reason: 'reloaded after saving');
  });
}
