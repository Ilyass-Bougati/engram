import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'api/models.dart';
import 'reminders/reminders.dart';

/// The signed-in person's decks and stats, shared by Home, Decks and Stats so they show the same
/// counts, and reloaded together after studying or changing a limit.
class Library extends ChangeNotifier {
  Library(this._api, {this._reminders});

  final ApiClient _api;
  final Reminders? _reminders;

  List<Deck>? _decks;
  Object? _decksError;
  Stats? _stats;
  Object? _statsError;
  bool _disposed = false;

  /// Null until the first load finishes.
  List<Deck>? get decks => _decks;
  Object? get decksError => _decksError;
  Stats? get stats => _stats;
  Object? get statsError => _statsError;

  /// When a finished session said cards come back, if that's still ahead.
  DateTime? get nextDueAt {
    final at = _nextDueAt;
    return at != null && at.isAfter(DateTime.now()) ? at : null;
  }

  DateTime? _nextDueAt;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadDecks() async {
    try {
      _decks = await _api.decks();
      _decksError = null;
      unawaited(_reminders?.updateFromDecks(_decks!));
    } on Object catch (error) {
      _decksError = error;
    }
    _changed();
  }

  Future<void> loadStats() async {
    try {
      _stats = await _api.stats();
      _statsError = null;
    } on Object catch (error) {
      _statsError = error;
    }
    _changed();
  }

  Future<void> refresh() => Future.wait([loadDecks(), loadStats()]);

  /// A study session ended with nothing left; cards come back at [at].
  void noteNextDue(DateTime at) {
    _nextDueAt = at;
    _reminders?.noteNextDue(at);
  }

  /// A deck the list has, by ID.
  Deck? deck(String id) => _decks?.where((deck) => deck.id == id).firstOrNull;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
