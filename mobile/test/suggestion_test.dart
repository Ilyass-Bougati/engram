import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

// The same cases as frontend/src/lib/suggestion.test.ts.

Deck _deck(String name, [int due = 0, int fresh = 0]) => Deck(
  id: name,
  name: name,
  description: '',
  role: DeckRole.owner,
  cardCount: 10,
  dueCount: due,
  newCount: fresh,
  newCardsPerDay: 20,
);

void main() {
  group('suggestDeck', () {
    test('prefers the most due cards over any number of new ones', () {
      final decks = [_deck('New', 0, 50), _deck('Some', 3), _deck('Most', 9)];
      expect(suggestDeck(decks)?.name, 'Most');
    });

    test('falls back to the most new cards when nothing is due', () {
      expect(suggestDeck([_deck('Few', 0, 2), _deck('Many', 0, 8)])?.name, 'Many');
    });

    test('breaks ties by new cards, then by name in numeric order', () {
      expect(suggestDeck([_deck('A', 4, 1), _deck('B', 4, 2)])?.name, 'B');
      expect(suggestDeck([_deck('Day 10', 4), _deck('Day 2', 4)])?.name, 'Day 2');
    });

    test("suggests nothing when there's nothing to study", () {
      expect(suggestDeck([_deck('Done')]), isNull);
      expect(suggestDeck([]), isNull);
    });
  });

  test("suggestionReason says what's waiting", () {
    expect(suggestionReason(_deck('A', 12, 5)), '12 cards due, plus 5 new');
    expect(suggestionReason(_deck('A', 1)), '1 card due');
    expect(suggestionReason(_deck('A', 0, 8)), '8 new cards ready');
  });
}
