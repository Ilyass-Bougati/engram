import 'package:engram_mobile/auth/session.dart';
import 'package:engram_mobile/auth/token_store.dart';
import 'package:engram_mobile/preferences.dart';
import 'package:engram_mobile/reminders/reminders.dart';
import 'package:engram_mobile/screens/collection_screen.dart';
import 'package:engram_mobile/screens/home_shell.dart';
import 'package:engram_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminders_test.dart' show FakeScheduler;
import 'support/fake_api.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'server': 'https://engram.test'});
    final api = FakeApi({
      'POST /api/auth/refresh': (_) => {
        'access_token': 'a',
        'user': {
          'id': 'u',
          'username': 'alice',
          'role': 'user',
          'timezone': 'UTC',
          'created_at': '2026-01-01T00:00:00Z',
        },
      },
      'GET /api/decks': (_) => [
        deckJson('a', 'Java::Day 1', due: 2),
        deckJson('b', 'Spanish', fresh: 3),
      ],
      'GET /api/me/stats': (_) => statsJson(),
    });
    late Preferences preferences;
    late SessionController session;
    await tester.runAsync(() async {
      preferences = await Preferences.load();
      session = SessionController(
        preferences: preferences,
        tokensFor: (_) => MemoryTokenStore('refresh'),
        httpClientFactory: api.httpClient,
      );
      await session.start();
    });
    final reminders = Reminders(
      preferences: preferences,
      scheduler: FakeScheduler(),
      device: tz.UTC,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: HomeShell(session: session, preferences: preferences, reminders: reminders),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(String label) =>
      find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  testWidgets('opens on Home, and each tab keeps its place', (tester) async {
    // A tall phone, so each page fits without scrolling.
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    expect(find.text('Suggested for you'), findsOneWidget);

    await tester.tap(tab('Decks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Java'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget);

    await tester.tap(tab('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);

    await tester.tap(tab('Decks'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget, reason: 'Decks kept its page');

    await tester.tap(tab('Decks'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsNothing, reason: 'tapping it again goes back');
    expect(find.text('Spanish'), findsOneWidget);

    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
  });
}
