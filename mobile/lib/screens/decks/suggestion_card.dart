import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../collections.dart';
import '../../suggestion.dart';
import '../../theme.dart';
import '../../widgets/shader_swirl.dart';

/// "Suggested for you": the deck most worth studying now, over a slow swirl of greens. The web
/// app's SuggestionCard. Nothing to study means no card: the deck list already says so.
class SuggestionCard extends StatefulWidget {
  const SuggestionCard({super.key, required this.decks, required this.onStudy});

  final List<Deck> decks;
  final ValueChanged<Deck> onStudy;

  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  // The arrow nudges forward while pressed, the touch version of the web's hover.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final deck = suggestDeck(widget.decks);
    if (deck == null) return const SizedBox.shrink();
    final c = context.colors;
    final name = deckDisplayName(deck.name);
    final reason = suggestionReason(deck);
    // As on the web, the "Study now" label only fits beside the name on wider screens.
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final onSuggestion = c.onSuggestion;
    return Semantics(
      button: true,
      label: 'Suggested for you: $name, $reason. Study now',
      excludeSemantics: true,
      child: Material(
        color: c.suggestion2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: ShaderSwirl(colors: [c.suggestion1, c.suggestion2, c.suggestion3]),
            ),
            InkWell(
              onTap: () => widget.onStudy(deck),
              onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
              splashColor: onSuggestion.withValues(alpha: 0.12),
              highlightColor: onSuggestion.withValues(alpha: 0.06),
              child: Padding(
                padding: EdgeInsets.all(wide ? 24 : 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 16, color: onSuggestion),
                              const SizedBox(width: 8),
                              Text(
                                'Suggested for you',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: onSuggestion,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: wide ? 28 : 22,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: onSuggestion,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reason,
                            style: TextStyle(
                              fontSize: 16,
                              color: onSuggestion,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: wide ? 24 : 16),
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: onSuggestion,
                        shape: const StadiumBorder(),
                      ),
                      child: Padding(
                        padding: wide
                            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                            : const EdgeInsets.all(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (wide) ...[
                              Text(
                                'Study now',
                                style: TextStyle(fontWeight: FontWeight.w500, color: c.suggestion2),
                              ),
                              const SizedBox(width: 8),
                            ],
                            AnimatedSlide(
                              offset: Offset(_pressed ? 0.2 : 0, 0),
                              duration: Motion.of(context, Motion.base),
                              curve: Motion.ease,
                              child: Icon(Icons.arrow_forward, size: 20, color: c.suggestion2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
