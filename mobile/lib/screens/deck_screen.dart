import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../collections.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/card_markdown.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'app_scope.dart';
import 'card_screen.dart';
import 'limit_sheet.dart';

/// A deck's page, the web's Deck page without editing: its counts, Study, your new-card limit,
/// and its cards to browse, search and filter by tag.
class DeckScreen extends StatelessWidget {
  const DeckScreen({super.key, required this.deckId});

  final String deckId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final deck = scope.library.deck(deckId);
        final path = deck == null ? const <String>[] : deckPath(deck.name);
        return GlassScaffold(
          title: Text(path.isEmpty ? 'Deck' : path.last, overflow: TextOverflow.ellipsis),
          body: deck == null
              ? const SafeArea(
                  child: MessageState(
                    icon: Icons.search_off,
                    title: 'Deck not found',
                    message:
                        'It may have been deleted, or it is no longer shared with you. Go back to '
                        'your decks.',
                  ),
                )
              : _DeckBody(deck: deck),
        );
      },
    );
  }
}

class _DeckBody extends StatefulWidget {
  const _DeckBody({required this.deck});

  final Deck deck;

  @override
  State<_DeckBody> createState() => _DeckBodyState();
}

class _DeckBodyState extends State<_DeckBody> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String _tag = '';
  Future<List<TagCount>>? _tags;

  final _cards = <CardView>[];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tags == null) {
      _tags = AppScope.of(context).api.tags(widget.deck.id);
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Loads the first page, or the next one with [more]. A newer search wins over an older one.
  Future<void> _load({bool more = false}) async {
    final generation = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await AppScope.of(context).api
          .cards(widget.deck.id, q: _q, tag: _tag, cursor: more ? _cursor : null);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _cards.clear();
        _cards.addAll(page.cards);
        _cursor = page.nextCursor;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _searchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (text.trim() == _q) return;
      _q = text.trim();
      _load();
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    _q = '';
    _tag = '';
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final deck = widget.deck;
    final c = context.colors;
    final path = deckPath(deck.name);
    final filtered = _q.isNotEmpty || _tag.isNotEmpty;
    return RefreshIndicator(
      onRefresh: () async {
        await scope.library.loadDecks();
        await _load();
      },
      edgeOffset: underBars(context, EdgeInsets.zero).top,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: underBars(context, const EdgeInsets.fromLTRB(16, 24, 16, 32)),
        children: [
          if (path.length > 1)
            Text(
              path.sublist(0, path.length - 1).join(' / '),
              style: TextStyle(fontSize: 14, color: c.inkMuted),
            ),
          Semantics(
            header: true,
            child: Text(
              path.last,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (deck.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(deck.description, style: TextStyle(color: c.inkMuted)),
          ],
          const SizedBox(height: 4),
          Text(
            '${studyCountsText(deck.dueCount, deck.newCount)} · ${plural(deck.cardCount, 'card')}'
            '${deck.role == DeckRole.owner ? '' : ' · shared with you as ${deck.role.name}'}',
            style: TextStyle(
              fontSize: 14,
              color: c.inkMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => scope.studyDeck(deck),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Study'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await showDeckLimitSheet(context, scope.api, deck)) {
                    await scope.library.loadDecks();
                  }
                },
                icon: const Icon(Icons.tune),
                label: const Text('New cards per day'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: const Text('Cards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: _searchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search cards',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          _TagChips(
            tags: _tags!,
            selected: _tag,
            onSelected: (tag) {
              setState(() => _tag = tag);
              _load();
            },
          ),
          const SizedBox(height: 12),
          ..._list(context, filtered),
        ],
      ),
    );
  }

  List<Widget> _list(BuildContext context, bool filtered) {
    if (_loading && _cards.isEmpty) {
      return const [SizedBox(height: 120, child: LoadingState(label: 'Loading cards'))];
    }
    if (_error != null && _cards.isEmpty) {
      return [
        SizedBox(
          height: 320,
          child: ErrorState(error: _error!, onRetry: _load),
        ),
      ];
    }
    if (_cards.isEmpty) {
      return [
        SizedBox(
          height: 300,
          child: filtered
              ? MessageState(
                  icon: Icons.search_off,
                  title: 'No cards match',
                  message: _q.isEmpty
                      ? 'No cards have the tag $_tag.'
                      : 'Nothing matches "$_q"${_tag.isEmpty ? '' : ' with the tag $_tag'}.',
                  action: OutlinedButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear search'),
                  ),
                )
              : const MessageState(
                  icon: Icons.style_outlined,
                  title: 'No cards yet',
                  message: 'Add cards in Engram on the web; they show up here.',
                ),
        ),
      ];
    }
    return [
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (index, card) in _cards.indexed) ...[
              if (index > 0) const Divider(),
              _CardRow(card: card),
            ],
          ],
        ),
      ),
      if (_error != null) ...[const SizedBox(height: 12), FormError(_error)],
      if (_cursor != null) ...[
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: _loadingMore ? null : () => _load(more: true),
            icon: const Icon(Icons.expand_more),
            label: Text(_loadingMore ? 'Loading…' : 'Show more cards'),
          ),
        ),
      ],
    ];
  }
}

class _TagChips extends StatelessWidget {
  const _TagChips({required this.tags, required this.selected, required this.onSelected});

  final Future<List<TagCount>> tags;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: tags,
    builder: (context, snapshot) {
      final tags = snapshot.data ?? const <TagCount>[];
      // No tags in the deck, or they didn't load: no filter to offer.
      if (tags.isEmpty) return const SizedBox.shrink();
      Widget chip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onSelected(value),
          showCheckmark: false,
        ),
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip('All tags', ''),
            for (final tag in tags) chip('${tag.tag} (${tag.cardCount})', tag.tag),
          ],
        ),
      );
    },
  );
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card});

  final CardView card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = switch (card) {
      BasicCardView() => 'Front and back',
      QuizCardView(:final options) => 'Multiple choice · ${plural(options.length, 'option')}',
    };
    return InkWell(
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => CardScreen(card: card))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardMarkdown(firstLine(card.prompt)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  card is BasicCardView ? Icons.crop_landscape : Icons.checklist,
                  size: 14,
                  color: c.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [kind, if (card.tags.isNotEmpty) card.tags.join(', ')].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.inkMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
