import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../collections.dart';
import '../format.dart';
import '../reminders/reminders.dart';
import '../suggestion.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'decks/suggestion_card.dart';
import 'study_screen.dart';

/// Your decks, grouped into collections, with what's due today. Tapping one starts studying.
/// The body of the Decks tab in the home shell.
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key, required this.api, this.reminders});

  final ApiClient api;

  /// Told what's left today after every load, so reminders can skip a finished day.
  final Reminders? reminders;

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  late Future<List<Deck>> _decks = _load();

  Future<List<Deck>> _load() async {
    final decks = await widget.api.decks();
    await widget.reminders?.updateFromDecks(decks);
    return decks;
  }

  Future<void> _reload() {
    final next = _load();
    setState(() => _decks = next);
    return next.then((_) {}, onError: (_) {});
  }

  Future<void> _study(Deck deck) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyScreen(
          api: widget.api,
          deck: deck,
          onFinished: (study) {
            final nextDue = study.nextDueAt;
            if (nextDue != null) widget.reminders?.noteNextDue(nextDue);
          },
        ),
      ),
    );
    // Counts are stale once anything is rated.
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _decks,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SafeArea(
            child: ErrorState(error: snapshot.error!, onRetry: _reload),
          );
        }
        final decks = snapshot.data;
        if (decks == null) return const LoadingState(label: 'Loading your decks');
        if (decks.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            edgeOffset: underTopBar(context, EdgeInsets.zero).top,
            child: const CustomScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: Icons.layers_outlined,
                    title: 'No decks yet',
                    message:
                        'Create or import a deck in Engram on the web, or ask someone to share '
                        'one with you. It shows up here.',
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          edgeOffset: underTopBar(context, EdgeInsets.zero).top,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: underTopBar(context, const EdgeInsets.fromLTRB(16, 24, 16, 32)),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Decks',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              _TotalsLine(decks: decks),
              const SizedBox(height: 16),
              if (suggestDeck(decks) != null) ...[
                SuggestionCard(decks: decks, onStudy: _study),
                const SizedBox(height: 16),
              ],
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: _rows(buildDeckTree(decks), 0)),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _rows(List<DeckNode> nodes, int depth) => [
    for (final (index, node) in nodes.indexed) ...[
      if (index > 0 || depth > 0) const Divider(),
      switch (node) {
        DeckLeaf() => _DeckTile(leaf: node, depth: depth, onTap: () => _study(node.deck)),
        Collection() => _CollectionTile(
          collection: node,
          depth: depth,
          children: _rows(node.children, depth + 1),
        ),
      },
    ],
  ];
}

class _TotalsLine extends StatelessWidget {
  const _TotalsLine({required this.decks});

  final List<Deck> decks;

  @override
  Widget build(BuildContext context) {
    final due = decks.fold(0, (sum, deck) => sum + deck.dueCount);
    final fresh = decks.fold(0, (sum, deck) => sum + deck.newCount);
    return Text(
      'Today: ${studyCountsText(due, fresh)}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.inkMuted),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.due, required this.fresh});

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

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.leaf, required this.depth, required this.onTap});

  final DeckLeaf leaf;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deck = leaf.deck;
    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(start: 16.0 + 16 * depth, end: 16),
      title: Text(leaf.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        plural(deck.cardCount, 'card'),
        style: TextStyle(color: context.colors.inkMuted),
      ),
      trailing: _Counts(due: deck.dueCount, fresh: deck.newCount),
      onTap: onTap,
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.collection, required this.depth, required this.children});

  final Collection collection;
  final int depth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Theme(
      // The expansion tile draws its own dividers; the list already has them.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey(collection.key),
        tilePadding: EdgeInsetsDirectional.only(start: 16.0 + 16 * depth, end: 12),
        leading: Icon(Icons.folder_outlined, color: c.pine),
        title: Text(collection.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${plural(collection.deckCount, 'deck')} · ${plural(collection.cardCount, 'card')}',
          style: TextStyle(color: c.inkMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Counts(due: collection.dueCount, fresh: collection.newCount),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more),
          ],
        ),
        expansionAnimationStyle: AnimationStyle(
          duration: Motion.of(context, Motion.base),
          curve: Motion.ease,
        ),
        children: children,
      ),
    );
  }
}
