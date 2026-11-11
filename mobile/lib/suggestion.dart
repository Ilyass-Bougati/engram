import 'api/models.dart';
import 'collections.dart';
import 'format.dart';

// What to study next, as in frontend/src/lib/suggestion.ts: due cards first, since reviews slip
// if they're left, then new cards. One deck, not a collection, because studying happens one deck
// at a time.

Deck? suggestDeck(List<Deck> decks) => rankedDecks(decks).firstOrNull;

/// Every deck with something to study, in the order [suggestDeck] picks from.
List<Deck> rankedDecks(List<Deck> decks) =>
    decks.where((deck) => deck.dueCount + deck.newCount > 0).toList()..sort((a, b) {
      final due = b.dueCount.compareTo(a.dueCount);
      if (due != 0) return due;
      final fresh = b.newCount.compareTo(a.newCount);
      return fresh != 0 ? fresh : compareNatural(a.name, b.name);
    });

String suggestionReason(Deck deck) {
  final due = deck.dueCount;
  final fresh = deck.newCount;
  if (due == 0) return '${plural(fresh, 'new card')} ready';
  final dueText = '${plural(due, 'card')} due';
  return fresh == 0 ? dueText : '$dueText, plus $fresh new';
}
