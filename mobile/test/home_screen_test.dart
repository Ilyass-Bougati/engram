import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/screens/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fake_api.dart';

const _user = User(id: 'u', username: 'alice', role: GlobalRole.user, timezone: 'UTC');

void main() {
  testWidgets('suggests a deck, lists what else is waiting, and sums up the day', (tester) async {
    final api = FakeApi({
      'GET /api/decks': (_) => [
        deckJson('a', 'Java::Streams', due: 9),
        deckJson('b', 'Spanish', due: 3, fresh: 5),
        deckJson('c', 'Chemistry', fresh: 2),
        deckJson('d', 'Done'),
      ],
      'GET /api/me/stats': (_) => statsJson(streak: 4, today: 12),
    });
    final (_, tabs) = await pumpInScope(tester, api, const HomeScreen(user: _user));

    expect(find.textContaining(', alice'), findsOneWidget);
    expect(find.text('Today: 12 due · 7 new across 4 decks'), findsOneWidget);
    expect(find.text('Suggested for you'), findsOneWidget);
    expect(find.text('Java / Streams'), findsOneWidget, reason: 'the suggestion');
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);
    expect(find.text('Chemistry'), findsOneWidget);
    expect(find.text('Done'), findsNothing, reason: 'nothing left in it');
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);

    await tester.tap(find.text('See all decks'));
    await tester.tap(find.text('Streak'));
    expect(tabs, [1, 2]);
  });

  testWidgets('says the day is done when nothing is left', (tester) async {
    final api = FakeApi({
      'GET /api/decks': (_) => [deckJson('d', 'Done')],
      'GET /api/me/stats': (_) => statsJson(),
    });
    await pumpInScope(tester, api, const HomeScreen(user: _user));
    expect(find.text('All done for today'), findsOneWidget);
    expect(find.text('Suggested for you'), findsNothing);
    expect(find.text('Up next'), findsNothing);
  });

  testWidgets('stats failing leaves the rest of Home working', (tester) async {
    var statsFail = true;
    final api = FakeApi({
      'GET /api/decks': (_) => [deckJson('a', 'Spanish', due: 2)],
      'GET /api/me/stats': (_) {
        if (statsFail) throw http.Response('{"detail":"Stats are resting."}', 500);
        return statsJson(streak: 6);
      },
    });
    await pumpInScope(tester, api, const HomeScreen(user: _user));
    expect(find.text('Suggested for you'), findsOneWidget);
    expect(find.text('Stats are resting.'), findsOneWidget);

    statsFail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('6 days'), findsOneWidget);
  });
}
