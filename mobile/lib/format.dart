// Text helpers shared by the screens, matching frontend/src/lib/format.ts.

String plural(int count, String singular, [String? pluralForm]) =>
    '$count ${count == 1 ? singular : (pluralForm ?? '${singular}s')}';

String studyCountsText(int due, int fresh) =>
    '${due == 0 ? 'Nothing due' : '$due due'} · $fresh new';

/// "in 3 hours", "in 2 days", "in a minute": how far [when] is from [now].
String formatRelative(DateTime when, {DateTime? now}) {
  final difference = when.difference(now ?? DateTime.now());
  final future = !difference.isNegative;
  final span = difference.abs();
  String amount;
  if (span.inDays >= 1) {
    amount = plural((span.inHours / 24).round(), 'day');
  } else if (span.inHours >= 1) {
    amount = plural((span.inMinutes / 60).round(), 'hour');
  } else {
    final minutes = (span.inSeconds / 60).round();
    if (minutes == 0) return 'now';
    amount = plural(minutes, 'minute');
  }
  return future ? 'in $amount' : '$amount ago';
}

String percent(int part, int whole) => whole == 0 ? '–' : '${(100 * part / whole).round()}%';
