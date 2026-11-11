import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../api/errors.dart';
import '../api/models.dart';
import '../collections.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/states.dart';

const _maxLimit = 9999;

/// Your new-card limit on one deck, as the web's deck settings. True when it was saved.
Future<bool> showDeckLimitSheet(BuildContext context, ApiClient api, Deck deck) async =>
    await showGlassSheet<bool>(
      context: context,
      builder: (_) => _LimitForm(
        title: 'New cards per day',
        description:
            'For ${deckDisplayName(deck.name)}. The daily limit is yours alone: other members '
            'keep theirs.',
        initial: deck.newCardsPerDay,
        save: (limit) => api.setDeckLimit(deck.id, limit),
      ),
    ) ??
    false;

/// Your new-card limit on every deck in a collection, as the web's collection settings. True when
/// it was saved.
Future<bool> showCollectionLimitSheet(
  BuildContext context,
  ApiClient api,
  String key,
  List<Deck> decks,
) async {
  final limits = decks.map((deck) => deck.newCardsPerDay).toSet();
  return await showGlassSheet<bool>(
        context: context,
        builder: (_) => _LimitForm(
          title: 'New cards per day, for each deck',
          description:
              'For every deck in ${deckDisplayName(key)}. The limit still counts per deck: 20 on '
              '${plural(decks.length, 'deck')} allows up to ${20 * decks.length} new cards a day.',
          // Decks with different limits show "Mixed" until a new one is typed.
          initial: limits.length == 1 ? limits.single : null,
          save: (limit) => api.setCollectionLimit(key, limit),
        ),
      ) ??
      false;
}

class _LimitForm extends StatefulWidget {
  const _LimitForm({
    required this.title,
    required this.description,
    required this.initial,
    required this.save,
  });

  final String title;
  final String description;
  final int? initial;
  final Future<Object?> Function(int limit) save;

  @override
  State<_LimitForm> createState() => _LimitFormState();
}

class _LimitFormState extends State<_LimitForm> {
  late final _field = TextEditingController(text: widget.initial?.toString() ?? '');
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final limit = int.tryParse(_field.text.trim());
    if (limit == null || limit < 0 || limit > _maxLimit) {
      setState(() => _error = const UserFacingError('Enter a number of new cards from 0 to 9999.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(limit);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(widget.description, style: TextStyle(color: context.colors.inkMuted)),
        const SizedBox(height: 20),
        TextField(
          controller: _field,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'New cards per day',
            hintText: widget.initial == null ? 'Mixed' : null,
            counterText: '',
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FormError(_error),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Save')),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
