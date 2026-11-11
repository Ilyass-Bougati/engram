import 'api/models.dart';

// Collections come from deck names, as in Anki: "Java::Day 1" is the deck "Day 1" in the
// collection "Java". A port of frontend/src/lib/collections.ts; keep the two in step.

const _separator = '::';

List<String> deckPath(String name) {
  final path = [
    for (final part in name.split(_separator))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  return path.isEmpty ? [name] : path;
}

/// For places that show one deck on its own: "Java / Day 1".
String deckDisplayName(String name) => deckPath(name).join(' / ');

sealed class DeckNode {
  const DeckNode(this.name);

  final String name;
}

class DeckLeaf extends DeckNode {
  const DeckLeaf(super.name, this.deck);

  final Deck deck;
}

class Collection extends DeckNode {
  Collection(super.name, this.key);

  /// The full path, joined: stable across renames of other decks.
  final String key;
  final List<DeckNode> children = [];
  int dueCount = 0;
  int newCount = 0;
  int cardCount = 0;
  int deckCount = 0;
}

/// Compares names the way Intl.Collator with `numeric: true` and base sensitivity does for
/// the common cases: case-insensitive, with runs of digits compared as numbers.
int compareNatural(String a, String b) {
  final chunk = RegExp(r'\d+|\D+');
  final left = chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final xNumber = int.tryParse(x);
    final yNumber = int.tryParse(y);
    final order = xNumber != null && yNumber != null ? xNumber.compareTo(yNumber) : x.compareTo(y);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}

List<DeckNode> buildDeckTree(List<Deck> decks) {
  final root = Collection('', '');
  final collections = <String, Collection>{'': root};
  Collection collectionAt(List<String> path) {
    var parent = root;
    for (var depth = 1; depth <= path.length; depth++) {
      final key = path.sublist(0, depth).join(_separator);
      var collection = collections[key];
      if (collection == null) {
        collection = Collection(path[depth - 1], key);
        collections[key] = collection;
        parent.children.add(collection);
      }
      parent = collection;
    }
    return parent;
  }

  final paths = [for (final deck in decks) deckPath(deck.name)];
  for (final path in paths) {
    collectionAt(path.sublist(0, path.length - 1));
  }
  for (var index = 0; index < decks.length; index++) {
    final deck = decks[index];
    final path = paths[index];
    // A deck named like a collection ("Java" next to "Java::Day 1") goes inside it.
    final homePath = collections.containsKey(path.join(_separator))
        ? path
        : path.sublist(0, path.length - 1);
    collectionAt(homePath).children.add(DeckLeaf(path.last, deck));
    for (var depth = homePath.length; depth > 0; depth--) {
      collectionAt(homePath.sublist(0, depth))
        ..dueCount += deck.dueCount
        ..newCount += deck.newCount
        ..cardCount += deck.cardCount
        ..deckCount += 1;
    }
  }

  void sort(List<DeckNode> nodes, String parent) {
    nodes.sort((a, b) {
      // A collection's own deck comes first, then everything by name, numbers in order.
      final aOwn = a is DeckLeaf && a.name == parent;
      final bOwn = b is DeckLeaf && b.name == parent;
      if (aOwn != bOwn) return aOwn ? -1 : 1;
      return compareNatural(a.name, b.name);
    });
    for (final node in nodes) {
      if (node is Collection) sort(node.children, node.name);
    }
  }

  sort(root.children, '');
  return root.children;
}

/// The decks in the collection [key] ("Java", "Java::Extras"), at any depth. A deck named like
/// the collection itself belongs to it too, as on the server (in_collection).
List<Deck> collectionDecks(List<Deck> decks, String key) {
  final collection = deckPath(key);
  bool inside(Deck deck) {
    final path = deckPath(deck.name);
    if (path.length < collection.length) return false;
    for (var i = 0; i < collection.length; i++) {
      if (path[i] != collection[i]) return false;
    }
    return true;
  }

  return decks.where(inside).toList();
}

/// A deck's name as seen from inside the collection [key]: "Extras / Quirks" in "Java". A deck
/// named like the collection keeps its full name.
String nameInCollection(String deckName, String key) {
  final inside = deckPath(deckName).skip(deckPath(key).length).toList();
  return inside.isEmpty ? deckDisplayName(deckName) : inside.join(' / ');
}

/// The first line of a card's Markdown, for one-line previews in lists, as format.ts does.
String firstLine(String markdown) {
  final line = markdown
      .split('\n')
      .firstWhere(
        (text) => text.trim().isNotEmpty && !text.trim().startsWith('```'),
        orElse: () => '',
      );
  return line.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim();
}
