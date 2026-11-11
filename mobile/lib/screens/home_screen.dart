import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../api/models.dart';
import '../collections.dart';
import '../format.dart';
import '../suggestion.dart';
import '../theme.dart';
import '../widgets/engram_mark.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'app_scope.dart';
import 'decks/deck_rows.dart';
import 'decks/suggestion_card.dart';

/// The Home tab, the first page: what to study now, how today is going, and what's next.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final library = scope.library;
    return GlassScaffold(
      automaticallyImplyLeading: false,
      title: const Row(
        children: [
          EngramMark(),
          SizedBox(width: 8),
          Text('Engram', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2)),
        ],
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final decks = library.decks;
          if (decks == null && library.decksError != null) {
            return SafeArea(
              child: ErrorState(error: library.decksError!, onRetry: library.refresh),
            );
          }
          if (decks == null) return const LoadingState(label: 'Loading your day');
          return RefreshIndicator(
            onRefresh: library.refresh,
            edgeOffset: underBars(context, EdgeInsets.zero).top,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: underBars(context, const EdgeInsets.fromLTRB(16, 24, 16, 32)),
              children: [
                _Greeting(user: user, decks: decks),
                const SizedBox(height: 20),
                if (suggestDeck(decks) != null)
                  SuggestionCard(decks: decks, onStudy: scope.studyDeck)
                else
                  _AllDone(decks: decks, nextDueAt: library.nextDueAt),
                const SizedBox(height: 16),
                _StatsStrip(
                  stats: library.stats,
                  error: library.statsError,
                  onRetry: library.loadStats,
                  onOpen: () => scope.goToTab(2),
                ),
                ..._upNext(context, decks),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _upNext(BuildContext context, List<Deck> decks) {
    final suggested = suggestDeck(decks);
    final waiting = [
      for (final deck in rankedDecks(decks))
        if (deck.id != suggested?.id) deck,
    ].take(3).toList();
    if (waiting.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: const Text(
                'Up next',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          TextButton(
            onPressed: () => AppScope.of(context).goToTab(1),
            child: const Text('See all decks'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (index, deck) in waiting.indexed) ...[
              if (index > 0) const Divider(),
              DeckRow(deck: deck, name: deckDisplayName(deck.name)),
            ],
          ],
        ),
      ),
    ];
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user, required this.decks});

  final User user;
  final List<Deck> decks;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 4 || hour >= 18
        ? 'Good evening'
        : hour < 12
        ? 'Good morning'
        : 'Good afternoon';
    final due = decks.fold(0, (sum, deck) => sum + deck.dueCount);
    final fresh = decks.fold(0, (sum, deck) => sum + deck.newCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            '$greeting, ${user.username}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          decks.isEmpty
              ? 'No decks yet.'
              : 'Today: ${studyCountsText(due, fresh)} across ${plural(decks.length, 'deck')}',
          style: TextStyle(
            color: context.colors.inkMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// In place of the suggestion when there's nothing to study.
class _AllDone extends StatelessWidget {
  const _AllDone({required this.decks, required this.nextDueAt});

  final List<Deck> decks;
  final DateTime? nextDueAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = nextDueAt;
    final (icon, title, message) = decks.isEmpty
        ? (
            Icons.layers_outlined,
            'No decks yet',
            'Create or import a deck in Engram on the web, or ask someone to share one with you.',
          )
        : (
            Icons.task_alt,
            'All done for today',
            next != null
                ? 'The next review is due ${formatRelative(next)}.'
                : 'New cards unlock after 4:00 tomorrow.',
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: c.pineSoft, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: c.pine, size: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(message, style: TextStyle(color: c.inkMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Streak, today's reviews and recent retention. Tapping it opens Stats.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.stats,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final Stats? stats;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final stats = this.stats;
    if (stats == null && error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(child: FormError(error)),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final activity = stats?.activity;
    final today = activity?.days.where((day) => day.date == activity.today).firstOrNull;
    final recent = stats?.retentionLast30Days;
    final number = NumberFormat.decimalPattern();
    String or(String? value) => value ?? '–';
    return Semantics(
      button: true,
      label: stats == null
          ? 'Stats, loading'
          : 'Streak ${plural(activity!.currentStreak, 'day')}, '
                '${plural(today?.reviews ?? 0, 'review')} today, '
                'retention ${percent(recent!.remembered, recent.reviews)} over 30 days. Open stats',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                _Figure(
                  icon: Icons.local_fire_department_outlined,
                  value: or(activity == null ? null : plural(activity.currentStreak, 'day')),
                  label: 'Streak',
                ),
                _Figure(
                  icon: Icons.repeat,
                  value: or(activity == null ? null : number.format(today?.reviews ?? 0)),
                  label: 'Today',
                ),
                _Figure(
                  icon: Icons.track_changes,
                  value: or(recent == null ? null : percent(recent.remembered, recent.reviews)),
                  label: 'Retention',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: c.pine),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, style: TextStyle(fontSize: 13, color: c.inkMuted)),
        ],
      ),
    );
  }
}
