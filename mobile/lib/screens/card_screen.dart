import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/card_markdown.dart';
import '../widgets/glass.dart';

/// One card, read-only. Cards are edited on the web. A quiz card's answer key and explanation
/// show only when the server sent them, which it does for editors and the owner.
class CardScreen extends StatelessWidget {
  const CardScreen({super.key, required this.card});

  final CardView card;

  @override
  Widget build(BuildContext context) {
    final card = this.card;
    return GlassScaffold(
      title: Text(card is BasicCardView ? 'Card' : 'Multiple choice'),
      body: Builder(
        builder: (context) => ListView(
          padding: underBars(context, const EdgeInsets.fromLTRB(16, 24, 16, 32)),
          children: [
            switch (card) {
              BasicCardView() => _Side(
                children: [
                  const _Label('Front'),
                  CardMarkdown(card.front, large: true),
                  const _Divider(),
                  const _Label('Back'),
                  CardMarkdown(card.back, large: true),
                ],
              ),
              QuizCardView() => _Side(
                children: [
                  _Label(card.selectAll ? 'Question · select all that apply' : 'Question'),
                  CardMarkdown(card.question, large: true),
                  const SizedBox(height: 16),
                  for (final option in card.options) _Option(option: option),
                  if (card.explanation?.trim().isNotEmpty ?? false) ...[
                    const _Divider(),
                    const _Label('Explanation'),
                    CardMarkdown(card.explanation!),
                  ],
                ],
              ),
            },
            if (card.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tag in card.tags) Chip(label: Text(tag))],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.colors.inkMuted),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider());
}

class _Option extends StatelessWidget {
  const _Option({required this.option});

  final CardOption option;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final correct = option.correct;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
          border: Border.all(
            color: correct == true ? c.ratingGood : c.lineStrong,
            width: correct == true ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(child: CardMarkdown(option.text)),
            if (correct == true) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 16, color: c.ratingGood),
              const SizedBox(width: 4),
              Text(
                'Correct',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ratingGood),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
