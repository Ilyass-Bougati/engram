import 'dart:convert';

import 'package:engram_mobile/api/client.dart';
import 'package:engram_mobile/api/models.dart';
import 'package:engram_mobile/auth/token_store.dart';
import 'package:engram_mobile/screens/study_screen.dart';
import 'package:engram_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _deck = Deck(
  id: 'd1',
  name: 'Languages::Spanish',
  description: '',
  role: DeckRole.viewer,
  cardCount: 3,
  dueCount: 2,
  newCount: 1,
  newCardsPerDay: 20,
);

Map<String, Object?> _next(Map<String, Object?>? card, {String? nextDueAt}) => {
  'card': card,
  'due_count': card == null ? 0 : 2,
  'new_count': card == null ? 0 : 1,
  'next_due_at': nextDueAt,
};

const _basic = {'id': 'c1', 'type': 'basic', 'front': 'Hola', 'back': 'Hello'};
const _quiz = {
  'id': 'c2',
  'type': 'quiz',
  'question': 'Which one means *cat*?',
  'select_all': false,
  'options': [
    {'id': 'o1', 'text': 'perro'},
    {'id': 'o2', 'text': 'gato'},
  ],
};

class _Server {
  _Server(this.first);

  final Map<String, Object?> first;
  final requests = <http.Request>[];
  Map<String, Object?> Function(Map<String, Object?> body)? onRate;
  Map<String, Object?> Function(Map<String, Object?> body)? onAnswer;

  ApiClient client() => ApiClient(
    server: Uri.parse('https://engram.test'),
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async {
      requests.add(request);
      final body = request.body.isEmpty
          ? <String, Object?>{}
          : jsonDecode(request.body) as Map<String, Object?>;
      final answer = switch (request.url.path) {
        '/api/decks/d1/study/next' || '/api/collections/study/next' => first,
        '/api/decks/d1/reviews' || '/api/collections/reviews' => onRate!(body),
        '/api/decks/d1/reviews/quiz-answer' ||
        '/api/collections/reviews/quiz-answer' => onAnswer!(body),
        _ => throw StateError('unexpected ${request.url}'),
      };
      return http.Response(jsonEncode(answer), 200, headers: {'content-type': 'application/json'});
    }),
  );
}

Future<void> _open(WidgetTester tester, _Server server) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: StudyScreen(api: server.client(), source: StudySource.deck(_deck)),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('basic card: reveal, rate, and finish', (tester) async {
    final server = _Server(_next(_basic))
      ..onRate = (body) {
        expect(body, {'card_id': 'c1', 'rating': 3});
        return _next(
          null,
          nextDueAt: DateTime.now().add(const Duration(hours: 3)).toUtc().toIso8601String(),
        );
      };
    await _open(tester, server);
    expect(_text('Hola'), findsOneWidget);
    expect(_text('Hello'), findsNothing);
    expect(find.text('Again'), findsNothing);

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(_text('Hello'), findsOneWidget);
    expect(find.text('Again'), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(find.text('Done for now'), findsOneWidget);
    expect(_text('You reviewed 1 card. The next review is due in 3 hours.'), findsOneWidget);
  });

  testWidgets('quiz card: a wrong answer is already Again and moves on with next', (tester) async {
    final server = _Server(_next(_quiz))
      ..onAnswer = (body) {
        expect(body, {
          'card_id': 'c2',
          'selected_option_ids': ['o1'],
        });
        return {
          'correct': false,
          'correct_option_ids': ['o2'],
          'explanation': 'Gato is cat.',
          'next': _next(_basic),
        };
      };
    await _open(tester, server);
    await tester.tap(_text('perro'));
    await tester.pump();
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();

    expect(_text('Not quite.'), findsOneWidget);
    expect(_text('Gato is cat.'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Your answer'), findsOneWidget);
    expect(find.text('Good'), findsNothing);

    await tester.ensureVisible(find.text('Next card'));
    await tester.tap(find.text('Next card'));
    await tester.pumpAndSettle();
    expect(_text('Hola'), findsOneWidget);
    expect(server.requests.where((r) => r.url.path.endsWith('/reviews')), isEmpty);
  });

  testWidgets('quiz card: a correct answer asks for Hard, Good or Easy', (tester) async {
    final server = _Server(_next(_quiz))
      ..onAnswer = ((body) => {
        'correct': true,
        'correct_option_ids': ['o2'],
        'explanation': '',
        'next': null,
      })
      ..onRate = (body) {
        expect(body, {'card_id': 'c2', 'rating': 4});
        return _next(null);
      };
    await _open(tester, server);
    await tester.tap(_text('gato'));
    await tester.pump();
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();

    expect(_text('Correct.'), findsOneWidget);
    expect(find.text('Again'), findsNothing);
    expect(find.text('Hard'), findsOneWidget);
    await tester.ensureVisible(find.text('Easy'));
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();
    expect(find.text('Done for now'), findsOneWidget);
  });

  testWidgets('a collection studies across its decks and names the deck over each card', (
    tester,
  ) async {
    const other = Deck(
      id: 'd2',
      name: 'Languages::Italian::Verbs',
      description: '',
      role: DeckRole.owner,
      cardCount: 4,
      dueCount: 1,
      newCount: 0,
      newCardsPerDay: 20,
    );
    final server = _Server(_next({..._basic, 'deck_id': 'd2'}))
      ..onRate = (body) => _next({..._basic, 'id': 'c3', 'deck_id': 'd1'});
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: StudyScreen(
          api: server.client(),
          source: StudySource.collection('Languages', const [_deck, other]),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Languages'), findsOneWidget, reason: 'the title is the collection');
    expect(find.text('Italian / Verbs'), findsOneWidget);
    final first = server.requests.single;
    expect(first.url.path, '/api/collections/study/next');
    expect(first.url.queryParameters, {'path': 'Languages'});

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(server.requests.last.url.path, '/api/collections/reviews');
    expect(server.requests.last.url.queryParameters, {'path': 'Languages'});
    expect(find.text('Spanish'), findsOneWidget, reason: 'the next card is from the other deck');
  });
}
