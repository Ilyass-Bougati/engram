import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../api/models.dart';
import '../collections.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'app_scope.dart';
import 'stats/retention_chart.dart';

/// The Stats tab: the web app's Stats page, sized for a phone. It reads the stats Home also
/// shows, from the shared library.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return GlassScaffold(
      automaticallyImplyLeading: false,
      title: const Text('Stats'),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final stats = library.stats;
          if (stats == null && library.statsError != null) {
            return SafeArea(
              child: ErrorState(error: library.statsError!, onRetry: library.loadStats),
            );
          }
          if (stats == null) return const LoadingState(label: 'Loading your stats');
          if (stats.activity.totalReviews == 0 && stats.decks.isEmpty) {
            return const SafeArea(
              child: MessageState(
                icon: Icons.bar_chart,
                title: 'Nothing to show yet',
                message: 'Create or import a deck and study it; your activity shows up here.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: library.loadStats,
            edgeOffset: underBars(context, EdgeInsets.zero).top,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: underBars(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
              children: [
                _Tiles(stats: stats),
                const SizedBox(height: 32),
                _Section(
                  title: 'Activity',
                  description: 'Reviews per day over the past year.',
                  child: stats.activity.totalReviews == 0
                      ? Text(
                          'No reviews yet. Study a deck to fill this in.',
                          style: TextStyle(color: context.colors.inkMuted),
                        )
                      : _ActivityHeatmap(activity: stats.activity),
                ),
                if (stats.retentionByMonth.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _Section(
                    title: 'Retention',
                    description:
                        'Of the cards you reviewed on a later day than you last saw them, the '
                        "share you didn't rate Again. Learning steps on the same day don't count.",
                    child: RetentionChart(months: stats.retentionByMonth),
                  ),
                ],
                const SizedBox(height: 32),
                _Section(
                  title: 'Cards',
                  description:
                      'Where your cards stand, across the decks you can study. Young and mature '
                      'split at a 21-day interval.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CardStatesBar(states: stats.states),
                      const SizedBox(height: 16),
                      _CardStatesLegend(states: stats.states),
                      if (stats.decks.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _DeckTable(decks: stats.decks),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.description, required this.child});

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        Text(description, style: TextStyle(fontSize: 14, color: c.inkMuted)),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final activity = stats.activity;
    final recent = stats.retentionLast30Days;
    final number = NumberFormat.decimalPattern();
    final tiles = [
      _Tile(
        icon: Icons.local_fire_department_outlined,
        label: 'Current streak',
        value: plural(activity.currentStreak, 'day'),
        detail: activity.currentStreak > 0 ? 'Keep it going today' : 'Study today to start one',
      ),
      _Tile(
        icon: Icons.emoji_events_outlined,
        label: 'Longest streak',
        value: plural(activity.longestStreak, 'day'),
        detail: '${plural(activity.daysStudied, 'day')} studied in all',
      ),
      _Tile(
        icon: Icons.repeat,
        label: 'Reviews',
        value: number.format(activity.totalReviews),
        detail: 'All time',
      ),
      _Tile(
        icon: Icons.track_changes,
        label: 'Retention',
        value: percent(recent.remembered, recent.reviews),
        detail: recent.reviews > 0
            ? 'Last 30 days · ${number.format(recent.remembered)} of ${number.format(recent.reviews)} remembered'
            : 'Last 30 days · no reviews due',
      ),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[row * 2]),
                const SizedBox(width: 12),
                Expanded(child: tiles[row * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, required this.detail});

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: c.inkMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label, style: TextStyle(fontSize: 14, color: c.inkMuted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(detail, style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

const _cell = 11.0;
const _gap = 3.0;
const _step = _cell + _gap;
const _left = 30.0;
const _top = 18.0;
const _weeks = 53;

/// A year of reviews, one square per day, weeks as columns starting on Monday. Scrolled to the
/// newest weeks, which matter most.
class _ActivityHeatmap extends StatelessWidget {
  const _ActivityHeatmap({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Reviews per day over the past year: ${plural(activity.totalReviews, 'review')} in total.',
      image: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: CustomPaint(
          size: const Size(_left + _weeks * _step, _top + 7 * _step),
          painter: _HeatmapPainter(activity: activity, colors: context.colors),
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.activity, required this.colors});

  final Activity activity;
  final EngramColors colors;

  void _label(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: sansFamily, fontSize: 10, color: colors.inkMuted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final counts = {for (final day in activity.days) day.date: day.reviews};
    final busiest = math.max(1, activity.days.fold(0, (most, day) => math.max(most, day.reviews)));
    final parts = activity.today.split('-').map(int.parse).toList();
    final today = DateTime.utc(parts[0], parts[1], parts[2]);
    final start = today.subtract(Duration(days: (today.weekday - 1) + (_weeks - 1) * 7));
    final monthFormat = DateFormat.MMM();
    final weekdayFormat = DateFormat.E();
    for (final weekday in [0, 2, 4]) {
      _label(
        canvas,
        weekdayFormat.format(start.add(Duration(days: weekday))),
        Offset(0, _top + weekday * _step - 1),
      );
    }
    int? lastMonthWeek;
    for (var offset = 0; ; offset++) {
      final date = start.add(Duration(days: offset));
      if (date.isAfter(today)) break;
      final week = offset ~/ 7;
      final key = DateFormat('yyyy-MM-dd').format(date);
      final reviews = counts[key] ?? 0;
      // Zero is the sunken surface; one to four steps of the pine ramp split the busiest day.
      final level = reviews == 0 ? 0 : math.min(4, math.max(1, (4 * reviews / busiest).ceil()));
      final paint = Paint()..color = level == 0 ? colors.surfaceSunken : colors.chart[level - 1];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_left + week * _step, _top + (offset % 7) * _step, _cell, _cell),
          const Radius.circular(2),
        ),
        paint,
      );
      if (date.day == 1 &&
          week <= _weeks - 3 &&
          (lastMonthWeek == null || week - lastMonthWeek >= 3)) {
        _label(canvas, monthFormat.format(date), Offset(_left + week * _step, 0));
        lastMonthWeek = week;
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => old.activity != activity || old.colors != colors;
}

const _states = [
  (label: 'New', help: 'not studied yet'),
  (label: 'Learning', help: 'in learning steps'),
  (label: 'Young', help: 'interval under 21 days'),
  (label: 'Mature', help: 'interval of 21 days or more'),
];

List<int> _stateCounts(CardStates states) => [
  states.fresh,
  states.learning,
  states.young,
  states.mature,
];

class _CardStatesBar extends StatelessWidget {
  const _CardStatesBar({required this.states, this.height = 24});

  final CardStates states;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counts = _stateCounts(states);
    if (states.total == 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(4)),
      );
    }
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, count) in counts.indexed)
                if (count > 0) ...[
                  Expanded(
                    flex: count,
                    child: ColoredBox(color: c.chart[index]),
                  ),
                  if (index < counts.length - 1) const SizedBox(width: 2),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardStatesLegend extends StatelessWidget {
  const _CardStatesLegend({required this.states});

  final CardStates states;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counts = _stateCounts(states);
    final number = NumberFormat.decimalPattern();
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        for (final (index, state) in _states.indexed)
          // A minimum, not a fixed width: labels grow with the phone's text size.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.chart[index],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(state.label, style: TextStyle(fontSize: 14, color: c.inkMuted)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Text(
                      number.format(counts[index]),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DeckTable extends StatelessWidget {
  const _DeckTable({required this.decks});

  final List<DeckStats> decks;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Column(
        children: [
          for (final (index, deck) in decks.indexed) ...[
            if (index > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deckDisplayName(deck.name),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          percent(deck.retention.remembered, deck.retention.reviews),
                          style: TextStyle(
                            color: c.inkMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CardStatesBar(states: deck.states, height: 8),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
