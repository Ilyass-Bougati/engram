import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/collections.dart';
import 'package:flutter_test/flutter_test.dart';

// The same cases as frontend/src/lib/collections.test.ts.

Deck _deck(String name, {int due = 0, int fresh = 0}) => Deck(
  id: name,
  name: name,
  description: '',
  role: DeckRole.owner,
  cardCount: 10,
  dueCount: due,
  newCount: fresh,
  newCardsPerDay: 20,
);

List<Object> _outline(List<DeckNode> nodes) => [
  for (final node in nodes)
    switch (node) {
      DeckLeaf() => node.name,
      Collection() => {
        node.name: _outline(node.children),
        'totals': [node.dueCount, node.newCount, node.cardCount, node.deckCount],
      },
    },
];

void main() {
  test('groups decks by their :: path and sums each collection', () {
    final tree = buildDeckTree([
      _deck('OCP Java 17::Day 10 - Streams', due: 1),
      _deck('Organic chemistry'),
      _deck('OCP Java 17::Day 2 - Operators', fresh: 20),
      _deck('OCP Java 17 :: Extras :: Quirks', due: 2),
      _deck('Algebra'),
    ]);
    expect(_outline(tree), [
      'Algebra',
      {
        'OCP Java 17': [
          'Day 2 - Operators',
          'Day 10 - Streams',
          {
            'Extras': ['Quirks'],
            'totals': [2, 0, 10, 1],
          },
        ],
        'totals': [3, 20, 30, 3],
      },
      'Organic chemistry',
    ]);
  });

  test('puts a deck named like a collection inside it, first', () {
    final tree = buildDeckTree([_deck('Java::Basics'), _deck('Java'), _deck('Java::Advanced')]);
    expect(_outline(tree), [
      {
        'Java': ['Java', 'Advanced', 'Basics'],
        'totals': [0, 0, 30, 3],
      },
    ]);
  });

  test('keeps decks with the same name apart and ignores empty path parts', () {
    final tree = buildDeckTree([
      _deck('Spanish::Verbs'),
      _deck('Spanish::Verbs'),
      _deck('::Odd::'),
    ]);
    expect(_outline(tree), [
      'Odd',
      {
        'Spanish': ['Verbs', 'Verbs'],
        'totals': [0, 0, 20, 2],
      },
    ]);
    expect(deckDisplayName('OCP Java 17::Day 1'), 'OCP Java 17 / Day 1');
  });

  test('finds the decks in a collection, at any depth, by whole path parts', () {
    final decks = [
      _deck('Java'),
      _deck('Java::Day 1'),
      _deck('Java::Extras::Quirks'),
      _deck('JavaScript::Basics'),
      _deck('Spanish'),
    ];
    expect(collectionDecks(decks, 'Java').map((d) => d.name), [
      'Java',
      'Java::Day 1',
      'Java::Extras::Quirks',
    ]);
    expect(collectionDecks(decks, 'Java::Extras').map((d) => d.name), ['Java::Extras::Quirks']);
  });

  test('names decks from inside their collection', () {
    expect(nameInCollection('Java::Extras::Quirks', 'Java'), 'Extras / Quirks');
    expect(nameInCollection('Java', 'Java'), 'Java');
    expect(firstLine('\n```dart\n# Heading\nmore'), 'Heading');
  });
}
