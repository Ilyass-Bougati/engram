import 'package:flutter/material.dart';

import '../collections.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';
import 'app_scope.dart';
import 'decks/deck_rows.dart';
import 'limit_sheet.dart';
import 'study_screen.dart';

/// A collection's own page: study all of it, set the new-card limit on every deck in it, and its
/// decks and sub-collections, which open their own pages in turn.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.collectionKey});

  /// The collection's path, its parts joined by '::'.
  final String collectionKey;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final path = deckPath(collectionKey);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final decks = scope.library.decks ?? const [];
        final inside = collectionDecks(decks, collectionKey);
        final node = _find(buildDeckTree(decks), path);
        return GlassScaffold(
          title: Text(path.last, overflow: TextOverflow.ellipsis),
          body: Builder(
            builder: (context) {
              if (node == null || inside.isEmpty) {
                return const SafeArea(
                  child: MessageState(
                    icon: Icons.folder_off_outlined,
                    title: 'Collection not found',
                    message:
                        'It may have been renamed, or its decks deleted or unshared. Go back to '
                        'your decks.',
                  ),
                );
              }
              final c = context.colors;
              return RefreshIndicator(
                onRefresh: scope.library.loadDecks,
                edgeOffset: underBars(context, EdgeInsets.zero).top,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: underBars(context, const EdgeInsets.fromLTRB(16, 24, 16, 32)),
                  children: [
                    if (path.length > 1)
                      Text(
                        path.sublist(0, path.length - 1).join(' / '),
                        style: TextStyle(fontSize: 14, color: c.inkMuted),
                      ),
                    Semantics(
                      header: true,
                      child: Text(
                        path.last,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${studyCountsText(node.dueCount, node.newCount)} · '
                      '${plural(node.deckCount, 'deck')} · ${plural(node.cardCount, 'card')}',
                      style: TextStyle(
                        color: c.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () =>
                              scope.study(StudySource.collection(collectionKey, inside)),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Study'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (await showCollectionLimitSheet(
                              context,
                              scope.api,
                              collectionKey,
                              inside,
                            )) {
                              await scope.library.loadDecks();
                            }
                          },
                          icon: const Icon(Icons.tune),
                          label: const Text('New cards per day'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DeckNodeList(nodes: node.children),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Collection? _find(List<DeckNode> nodes, List<String> path) {
    Collection? found;
    var level = nodes;
    for (final part in path) {
      found = level.whereType<Collection>().where((node) => node.name == part).firstOrNull;
      if (found == null) return null;
      level = found.children;
    }
    return found;
  }
}
