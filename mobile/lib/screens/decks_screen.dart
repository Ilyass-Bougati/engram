import 'package:flutter/material.dart';

import '../collections.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'app_scope.dart';
import 'decks/deck_rows.dart';

/// The Decks tab: top-level collections and loose decks. Collections open their own page.
class DecksScreen extends StatelessWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final library = scope.library;
    return GlassScaffold(
      automaticallyImplyLeading: false,
      title: const Text('Decks'),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final decks = library.decks;
          if (decks == null && library.decksError != null) {
            return SafeArea(
              child: ErrorState(error: library.decksError!, onRetry: library.loadDecks),
            );
          }
          if (decks == null) return const LoadingState(label: 'Loading your decks');
          if (decks.isEmpty) {
            return const SafeArea(
              child: MessageState(
                icon: Icons.layers_outlined,
                title: 'No decks yet',
                message:
                    'Create or import a deck in Engram on the web, or ask someone to share one '
                    'with you. It shows up here.',
              ),
            );
          }
          final due = decks.fold(0, (sum, deck) => sum + deck.dueCount);
          final fresh = decks.fold(0, (sum, deck) => sum + deck.newCount);
          return RefreshIndicator(
            onRefresh: library.loadDecks,
            edgeOffset: underBars(context, EdgeInsets.zero).top,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: underBars(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
              children: [
                Text(
                  'Today: ${studyCountsText(due, fresh)} · ${plural(decks.length, 'deck')}',
                  style: TextStyle(color: context.colors.inkMuted),
                ),
                const SizedBox(height: 12),
                DeckNodeList(nodes: buildDeckTree(decks)),
              ],
            ),
          );
        },
      ),
    );
  }
}
