import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../collections.dart';
import '../../format.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../collection_screen.dart';
import '../deck_screen.dart';

/// One level of the deck tree in a card: collections open their own page, decks open theirs,
/// and each deck has a Study button. Used by the Decks tab and by collection pages.
class DeckNodeList extends StatelessWidget {
  const DeckNodeList({super.key, required this.nodes});

  final List<DeckNode> nodes;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (index, node) in nodes.indexed) ...[
          if (index > 0) const Divider(),
          switch (node) {
            DeckLeaf() => DeckRow(deck: node.deck, name: node.name),
            Collection() => CollectionRow(collection: node),
          },
        ],
      ],
    ),
  );
}

/// "12 due · 5 new", with due in pine and bold when there's any.
class StudyCounts extends StatelessWidget {
  const StudyCounts({super.key, required this.due, required this.fresh});

  final int due;
  final int fresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      label: studyCountsText(due, fresh),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$due due',
              style: style.copyWith(
                color: due > 0 ? c.pine : c.inkMuted,
                fontWeight: due > 0 ? FontWeight.w600 : null,
              ),
            ),
            Text(' · ', style: style.copyWith(color: c.inkMuted)),
            Text('$fresh new', style: style.copyWith(color: c.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// A round play button that starts studying.
class StudyButton extends StatelessWidget {
  const StudyButton({super.key, required this.label, required this.onPressed});

  /// What it studies, for screen readers: "Study Spanish verbs".
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: c.pineSoft, foregroundColor: c.pine),
      icon: const Icon(Icons.play_arrow_rounded),
    );
  }
}

class DeckRow extends StatelessWidget {
  const DeckRow({super.key, required this.deck, required this.name});

  final Deck deck;

  /// The name shown: the last part of the path, inside a collection.
  final String name;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        plural(deck.cardCount, 'card'),
        style: TextStyle(color: context.colors.inkMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudyCounts(due: deck.dueCount, fresh: deck.newCount),
          const SizedBox(width: 8),
          StudyButton(
            label: 'Study ${deckDisplayName(deck.name)}',
            onPressed: () => scope.studyDeck(deck),
          ),
        ],
      ),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => DeckScreen(deckId: deck.id))),
    );
  }
}

class CollectionRow extends StatelessWidget {
  const CollectionRow({super.key, required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 12),
      leading: Icon(Icons.folder_outlined, color: c.pine),
      title: Text(collection.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${plural(collection.deckCount, 'deck')} · ${plural(collection.cardCount, 'card')}',
        style: TextStyle(color: c.inkMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudyCounts(due: collection.dueCount, fresh: collection.newCount),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: c.inkMuted),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CollectionScreen(collectionKey: collection.key)),
      ),
    );
  }
}
