import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../collections.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/card_markdown.dart';
import '../widgets/glass.dart';
import '../widgets/motion.dart';
import '../widgets/states.dart';

const _ratingLabels = {1: 'Again', 2: 'Hard', 3: 'Good', 4: 'Easy'};

/// What a session studies, as in the web's Study.tsx: one deck, or every deck in a collection.
class StudySource {
  const StudySource({
    required this.title,
    required this.scope,
    required this.cardCount,
    required this.limitDetail,
    this.deckNames = const {},
  });

  factory StudySource.deck(Deck deck) => StudySource(
    title: deckDisplayName(deck.name),
    scope: DeckScope(deck.id),
    cardCount: deck.cardCount,
    limitDetail:
        "You've had today's ${plural(deck.newCardsPerDay, 'new card')}. More come after 4:00 "
        "tomorrow, or raise the limit in the deck's New cards per day.",
  );

  /// [decks] are the collection's decks, from the deck list the app already has.
  factory StudySource.collection(String key, List<Deck> decks) => StudySource(
    title: deckDisplayName(key),
    scope: CollectionScope(key),
    cardCount: decks.fold(0, (total, deck) => total + deck.cardCount),
    limitDetail:
        "You've had today's new cards from every deck here. More come after 4:00 tomorrow, or "
        "raise the limit in the collection's New cards per day.",
    deckNames: {for (final deck in decks) deck.id: nameInCollection(deck.name, key)},
  );

  final String title;
  final StudyScope scope;
  final int cardCount;

  /// Why there's nothing more today when the new-card limit is reached.
  final String limitDetail;

  /// Deck names by ID, to show above each card in a collection. Empty for one deck.
  final Map<String, String> deckNames;
}

/// Studying: the web app's Study page. Basic cards show the front, then the answer and four
/// ratings. Quiz cards are graded by the server; a wrong answer is already rated Again.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.api, required this.source, this.onFinished});

  final ApiClient api;
  final StudySource source;

  /// Called when there's nothing left to study here, with when cards come back.
  final ValueChanged<StudyNext>? onFinished;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late Future<StudyNext> _initial = _first();

  Future<StudyNext> _first() async {
    final study = await widget.api.studyNext(widget.source.scope);
    if (study.card == null) widget.onFinished?.call(study);
    return study;
  }

  StudyNext? _current;
  int _reviewed = 0;
  bool _rating = false;
  Object? _ratingError;

  void _retry() => setState(() => _initial = _first());

  void _advance(StudyNext next) => setState(() {
    if (next.card == null) widget.onFinished?.call(next);
    _current = next;
    _reviewed += 1;
    _ratingError = null;
  });

  Future<void> _rate(String cardId, int rating) async {
    if (_rating) return;
    setState(() {
      _rating = true;
      _ratingError = null;
    });
    try {
      _advance(await widget.api.rate(widget.source.scope, cardId, rating));
    } on Object catch (error) {
      if (mounted) setState(() => _ratingError = error);
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initial,
      builder: (context, snapshot) {
        final study = _current ?? snapshot.data;
        return GlassScaffold(
          scene: Scene.study,
          title: Text(widget.source.title, overflow: TextOverflow.ellipsis),
          actions: [
            if (study?.card != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      studyCountsText(study!.dueCount, study.newCount),
                      style: TextStyle(
                        fontSize: 14,
                        color: context.colors.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          body: _body(context, snapshot, study),
        );
      },
    );
  }

  Widget _body(BuildContext context, AsyncSnapshot<StudyNext> snapshot, StudyNext? study) {
    if (study == null && snapshot.hasError) {
      return SafeArea(
        child: ErrorState(error: snapshot.error!, onRetry: _retry),
      );
    }
    if (study == null) return const LoadingState(label: 'Loading the next card');
    final card = study.card;
    if (card == null) {
      return SafeArea(
        child: RiseIn(
          child: _Finished(source: widget.source, study: study, reviewed: _reviewed),
        ),
      );
    }
    // Keyed per review, not per card: a card failed moments ago can come straight back.
    final key = ValueKey('${card.id}-$_reviewed');
    // A Builder, so the padding is read below the scaffold, where it includes the top bar.
    return Builder(
      builder: (context) => SingleChildScrollView(
        padding: underBars(context, const EdgeInsets.fromLTRB(16, 32, 16, 48)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Semantics(
              label: 'Card',
              container: true,
              child: Glass(
                thin: true,
                borderRadius: const BorderRadius.all(Radius.circular(Radii.lg)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  // Each card rises in; the glass around it stays put.
                  child: AnimatedSize(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.ease,
                    alignment: Alignment.topCenter,
                    child: RiseIn(
                      key: key,
                      child: _FromDeck(
                        name: widget.source.deckNames[card.deckId],
                        child: switch (card) {
                          BasicStudyCard() => _BasicReview(
                            card: card,
                            rating: _rating,
                            error: _ratingError,
                            onRate: (value) => _rate(card.id, value),
                          ),
                          QuizStudyCard() => _QuizReview(
                            api: widget.api,
                            scope: widget.source.scope,
                            card: card,
                            rating: _rating,
                            ratingError: _ratingError,
                            onRate: (value) => _rate(card.id, value),
                            onNext: _advance,
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingButtons extends StatelessWidget {
  const _RatingButtons({required this.ratings, required this.disabled, required this.onRate});

  final List<int> ratings;
  final bool disabled;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final buttons = [
      for (final value in ratings)
        OutlinedButton(
          onPressed: disabled ? null : () => onRate(value),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            _ratingLabels[value]!,
            style: TextStyle(
              color: disabled ? c.inkMuted : c.rating(value),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ];
    return Semantics(
      label: 'How well did you remember it?',
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two rows of two on a narrow phone, one row otherwise, as the web's grid does.
          final perRow = ratings.length == 4 && constraints.maxWidth < 360 ? 2 : ratings.length;
          final rows = [
            for (var i = 0; i < buttons.length; i += perRow)
              buttons.sublist(i, (i + perRow).clamp(0, buttons.length)),
          ];
          return Column(
            children: [
              for (final (index, row) in rows.indexed) ...[
                if (index > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (i, button) in row.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: button),
                    ],
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BasicReview extends StatefulWidget {
  const _BasicReview({
    required this.card,
    required this.rating,
    required this.error,
    required this.onRate,
  });

  final BasicStudyCard card;
  final bool rating;
  final Object? error;
  final ValueChanged<int> onRate;

  @override
  State<_BasicReview> createState() => _BasicReviewState();
}

class _BasicReviewState extends State<_BasicReview> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardMarkdown(widget.card.front, large: true),
        const SizedBox(height: 32),
        if (!_revealed)
          OutlinedButton.icon(
            onPressed: () => setState(() => _revealed = true),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Show answer'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          )
        else
          RiseIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'Answer',
                  container: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: CardMarkdown(widget.card.back, large: true),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _RatingButtons(
                  ratings: const [1, 2, 3, 4],
                  disabled: widget.rating,
                  onRate: widget.onRate,
                ),
                if (widget.error != null) ...[const SizedBox(height: 12), FormError(widget.error)],
              ],
            ),
          ),
      ],
    );
  }
}

class _QuizReview extends StatefulWidget {
  const _QuizReview({
    required this.api,
    required this.scope,
    required this.card,
    required this.rating,
    required this.ratingError,
    required this.onRate,
    required this.onNext,
  });

  final ApiClient api;
  final StudyScope scope;
  final QuizStudyCard card;
  final bool rating;
  final Object? ratingError;
  final ValueChanged<int> onRate;
  final ValueChanged<StudyNext> onNext;

  @override
  State<_QuizReview> createState() => _QuizReviewState();
}

class _QuizReviewState extends State<_QuizReview> {
  final _selected = <String>[];
  QuizResult? _result;
  bool _checking = false;
  Object? _error;

  void _toggle(String optionId) => setState(() {
    if (!widget.card.selectAll) {
      _selected
        ..clear()
        ..add(optionId);
    } else if (!_selected.remove(optionId)) {
      _selected.add(optionId);
    }
  });

  Future<void> _submit() async {
    if (_selected.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final result = await widget.api.answerQuiz(widget.scope, widget.card.id, List.of(_selected));
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final result = _result;
    final next = result?.next;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardMarkdown(widget.card.question, large: true),
        const SizedBox(height: 24),
        if (widget.card.selectAll) ...[
          Text('Select all that apply', style: TextStyle(fontSize: 14, color: c.inkMuted)),
          const SizedBox(height: 8),
        ],
        for (final option in widget.card.options) ...[
          _QuizOption(
            text: option.text,
            multiple: widget.card.selectAll,
            selected: _selected.contains(option.id),
            correct: result?.correctOptionIds.contains(option.id) ?? false,
            answered: result != null,
            onTap: result != null || _checking ? null : () => _toggle(option.id),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        if (result == null) ...[
          FilledButton.icon(
            onPressed: _selected.isEmpty || _checking ? null : _submit,
            icon: const Icon(Icons.check),
            label: Text(_checking ? 'Checking…' : 'Check answer'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
          if (_error != null) ...[const SizedBox(height: 12), FormError(_error)],
        ] else
          RiseIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            result.correct ? Icons.check_circle_outline : Icons.cancel_outlined,
                            color: result.correct ? c.ratingGood : c.danger,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              result.correct
                                  ? 'Correct.'
                                  : 'Not quite. This card is marked Again and comes back soon.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: result.correct ? c.ratingGood : c.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (result.explanation.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CardMarkdown(result.explanation),
                ],
                const SizedBox(height: 24),
                if (next != null)
                  OutlinedButton(
                    onPressed: () => widget.onNext(next),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Next card'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  )
                else ...[
                  _RatingButtons(
                    ratings: const [2, 3, 4],
                    disabled: widget.rating,
                    onRate: widget.onRate,
                  ),
                  if (widget.ratingError != null) ...[
                    const SizedBox(height: 12),
                    FormError(widget.ratingError),
                  ],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.text,
    required this.multiple,
    required this.selected,
    required this.correct,
    required this.answered,
    required this.onTap,
  });

  final String text;
  final bool multiple;
  final bool selected;
  final bool correct;
  final bool answered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wrongPick = answered && selected && !correct;
    final borderColor = correct
        ? c.ratingGood
        : wrongPick
        ? c.danger
        : !answered && selected
        ? c.pine
        : c.lineStrong;
    final control = Padding(
      padding: const EdgeInsets.all(10),
      child: Icon(
        multiple
            ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
            : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        size: 20,
        color: selected ? c.pine : c.lineStrong,
      ),
    );
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: !multiple,
      button: true,
      child: Material(
        color: !answered && selected ? c.pineSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
          side: BorderSide(
            color: borderColor,
            width: correct || wrongPick || (selected && !answered) ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(
              children: [
                control,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: CardMarkdown(text),
                  ),
                ),
                if (correct)
                  _Badge(icon: Icons.check, label: 'Correct', color: c.ratingGood)
                else if (wrongPick)
                  _Badge(icon: Icons.close, label: 'Your answer', color: c.danger),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    ),
  );
}

/// In a collection, the deck a card comes from, in small text above it, as on the web.
class _FromDeck extends StatelessWidget {
  const _FromDeck({required this.name, required this.child});

  final String? name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final name = this.name;
    if (name == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: TextStyle(fontSize: 14, color: context.colors.inkMuted)),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.source, required this.study, required this.reviewed});

  final StudySource source;
  final StudyNext study;
  final int reviewed;

  @override
  Widget build(BuildContext context) {
    final String detail;
    if (study.nextDueAt != null) {
      detail = 'The next review is due ${formatRelative(study.nextDueAt!)}.';
    } else if (source.cardCount == 0) {
      detail = 'There are no cards here yet.';
    } else {
      detail = source.limitDetail;
    }
    return MessageState(
      icon: reviewed > 0 ? Icons.task_alt : Icons.event_available_outlined,
      title: reviewed > 0 ? 'Done for now' : 'Nothing to study right now',
      message: '${reviewed > 0 ? 'You reviewed ${plural(reviewed, 'card')}. ' : ''}$detail',
      action: FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
    );
  }
}
