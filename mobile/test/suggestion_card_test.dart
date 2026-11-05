import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/screens/decks/suggestion_card.dart';
import 'package:engram_mobile/theme.dart';
import 'package:engram_mobile/widgets/shader_swirl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Deck _deck(String name, [int due = 0, int fresh = 0]) => Deck(
  id: name,
  name: name,
  description: '',
  role: DeckRole.owner,
  cardCount: 10,
  dueCount: due,
  newCount: fresh,
  newCardsPerDay: 20,
);

Future<void> _show(
  WidgetTester tester,
  List<Deck> decks, {
  ValueChanged<Deck>? onStudy,
  bool reducedMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: SuggestionCard(decks: decks, onStudy: onStudy ?? (_) {}),
      ),
    ),
  ),
);

bool _swirlTicking(WidgetTester tester) =>
    tester.binding.transientCallbackCount > 0 || SchedulerBinding.instance.hasScheduledFrame;

void main() {
  testWidgets('suggests the deck with the most due cards and opens it', (tester) async {
    Deck? studied;
    await _show(tester, [
      _deck('Spanish', 0, 20),
      _deck('OCP Java 17::Day 2', 12, 5),
      _deck('Chemistry', 3),
    ], onStudy: (deck) => studied = deck);

    expect(find.text('Suggested for you'), findsOneWidget);
    expect(find.text('OCP Java 17 / Day 2'), findsOneWidget);
    expect(find.text('12 cards due, plus 5 new'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Suggested for you: OCP Java 17 / Day 2, 12 cards due, plus 5 new. Study now',
      ),
      findsOneWidget,
    );
    expect(find.byType(ShaderSwirl), findsOneWidget);
    expect(_swirlTicking(tester), isTrue, reason: 'the swirl moves');

    await tester.tap(find.byType(SuggestionCard));
    await tester.pump();
    expect(studied?.name, 'OCP Java 17::Day 2');
  });

  testWidgets("shows nothing when there's nothing to study", (tester) async {
    await _show(tester, [_deck('Done')]);
    expect(find.text('Suggested for you'), findsNothing);
    expect(find.byType(ShaderSwirl), findsNothing);
  });

  testWidgets('holds still with reduced motion', (tester) async {
    await _show(tester, [_deck('Spanish', 2)], reducedMotion: true);
    await tester.pump();
    expect(find.text('2 cards due'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker under reduced motion');
  });
}
