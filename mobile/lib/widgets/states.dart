import 'package:flutter/material.dart';

import '../api/errors.dart';
import '../theme.dart';

/// Loading: a spinner with a label for screen readers.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label,
      liveRegion: true,
      child: const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
    ),
  );
}

/// A message with an icon, a title and an optional action. Used for empty and error states.
class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: c.pineSoft, shape: BoxShape.circle),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: iconColor ?? c.pine, size: 24),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: text.bodyLarge?.copyWith(color: c.inkMuted)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// An error with a retry button. The message is the server's sentence when it sent one.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry, this.title});

  final Object error;
  final VoidCallback onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) => MessageState(
    icon: Icons.error_outline,
    iconColor: context.colors.danger,
    title: title ?? "That didn't load",
    message: errorMessage(error),
    action: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    ),
  );
}

/// An error under a form, announced to screen readers.
class FormError extends StatelessWidget {
  const FormError(this.error, {super.key});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    if (error == null) return const SizedBox.shrink();
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, size: 18, color: c.danger),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(errorMessage(error), style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }
}
