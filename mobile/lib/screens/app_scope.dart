import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../library.dart';
import 'study_screen.dart';

/// What every signed-in screen needs: the API, the shared [Library], and ways to move around.
/// Provided by the home shell.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.library,
    required this.goToTab,
    required this.rootNavigator,
    required super.child,
  });

  final ApiClient api;
  final Library library;

  /// Switches the bottom bar's tab: 0 Home, 1 Decks, 2 Stats, 3 Settings.
  final ValueChanged<int> goToTab;

  /// The navigator above the shell: studying opens there, full screen, without the bottom bar.
  final NavigatorState Function() rootNavigator;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  /// Studies [source], then reloads counts and stats.
  Future<void> study(StudySource source) async {
    await rootNavigator().push(
      MaterialPageRoute<void>(
        builder: (_) => StudyScreen(
          api: api,
          source: source,
          onFinished: (study) {
            final nextDue = study.nextDueAt;
            if (nextDue != null) library.noteNextDue(nextDue);
          },
        ),
      ),
    );
    await library.refresh();
  }

  Future<void> studyDeck(Deck deck) => study(StudySource.deck(deck));

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      api != oldWidget.api || library != oldWidget.library;
}
