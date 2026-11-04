// Response shapes of the backend API, kept by hand like frontend/src/lib/types.ts. The reference
// to match is docs/openapi.json. Only what the mobile app uses is here.

typedef Json = Map<String, dynamic>;

enum GlobalRole { admin, user }

enum DeckRole { owner, editor, viewer }

class User {
  const User({
    required this.id,
    required this.username,
    required this.role,
    required this.timezone,
  });

  factory User.fromJson(Json json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    role: GlobalRole.values.byName(json['role'] as String),
    timezone: json['timezone'] as String,
  );

  final String id;
  final String username;
  final GlobalRole role;
  final String timezone;
}

class SessionResponse {
  const SessionResponse({required this.accessToken, required this.user});

  factory SessionResponse.fromJson(Json json) => SessionResponse(
    accessToken: json['access_token'] as String,
    user: User.fromJson(json['user'] as Json),
  );

  final String accessToken;
  final User user;
}

class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.description,
    required this.role,
    required this.cardCount,
    required this.dueCount,
    required this.newCount,
    required this.newCardsPerDay,
  });

  factory Deck.fromJson(Json json) => Deck(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    role: DeckRole.values.byName(json['role'] as String),
    cardCount: json['card_count'] as int,
    dueCount: json['due_count'] as int,
    newCount: json['new_count'] as int,
    newCardsPerDay: json['new_cards_per_day'] as int,
  );

  final String id;
  final String name;
  final String description;
  final DeckRole role;
  final int cardCount;
  final int dueCount;
  final int newCount;
  final int newCardsPerDay;
}

sealed class StudyCard {
  const StudyCard(this.id);

  factory StudyCard.fromJson(Json json) => switch (json['type']) {
    'basic' => BasicStudyCard(
      id: json['id'] as String,
      front: json['front'] as String,
      back: json['back'] as String,
    ),
    'quiz' => QuizStudyCard(
      id: json['id'] as String,
      question: json['question'] as String,
      selectAll: json['select_all'] as bool,
      options: [
        for (final option in json['options'] as List<dynamic>)
          StudyOption(id: (option as Json)['id'] as String, text: option['text'] as String),
      ],
    ),
    final type => throw FormatException('Unknown card type $type'),
  };

  final String id;
}

class BasicStudyCard extends StudyCard {
  const BasicStudyCard({required String id, required this.front, required this.back}) : super(id);

  final String front;
  final String back;
}

class StudyOption {
  const StudyOption({required this.id, required this.text});

  final String id;
  final String text;
}

class QuizStudyCard extends StudyCard {
  const QuizStudyCard({
    required String id,
    required this.question,
    required this.selectAll,
    required this.options,
  }) : super(id);

  final String question;
  final bool selectAll;
  final List<StudyOption> options;
}

class StudyNext {
  const StudyNext({
    required this.card,
    required this.dueCount,
    required this.newCount,
    required this.nextDueAt,
  });

  factory StudyNext.fromJson(Json json) => StudyNext(
    card: json['card'] == null ? null : StudyCard.fromJson(json['card'] as Json),
    dueCount: json['due_count'] as int,
    newCount: json['new_count'] as int,
    nextDueAt: json['next_due_at'] == null ? null : DateTime.parse(json['next_due_at'] as String),
  );

  final StudyCard? card;
  final int dueCount;
  final int newCount;

  /// When the session is over, the earliest time something becomes due again.
  final DateTime? nextDueAt;
}

class QuizResult {
  const QuizResult({
    required this.correct,
    required this.correctOptionIds,
    required this.explanation,
    required this.next,
  });

  factory QuizResult.fromJson(Json json) => QuizResult(
    correct: json['correct'] as bool,
    correctOptionIds: [for (final id in json['correct_option_ids'] as List<dynamic>) id as String],
    explanation: json['explanation'] as String,
    next: json['next'] == null ? null : StudyNext.fromJson(json['next'] as Json),
  );

  final bool correct;
  final List<String> correctOptionIds;
  final String explanation;

  /// Present after a wrong answer, which the server already rated Again.
  final StudyNext? next;
}

class InviteStatus {
  const InviteStatus({required this.expiresAt});

  factory InviteStatus.fromJson(Json json) =>
      InviteStatus(expiresAt: DateTime.parse(json['expires_at'] as String));

  final DateTime expiresAt;
}

class Retention {
  const Retention({required this.reviews, required this.remembered});

  factory Retention.fromJson(Json json) =>
      Retention(reviews: json['reviews'] as int, remembered: json['remembered'] as int);

  final int reviews;
  final int remembered;
}

class CardStates {
  const CardStates({
    required this.fresh,
    required this.learning,
    required this.young,
    required this.mature,
  });

  factory CardStates.fromJson(Json json) => CardStates(
    fresh: json['new'] as int,
    learning: json['learning'] as int,
    young: json['young'] as int,
    mature: json['mature'] as int,
  );

  final int fresh;
  final int learning;
  final int young;
  final int mature;

  int get total => fresh + learning + young + mature;
}

class DayCount {
  const DayCount({required this.date, required this.reviews});

  final String date;
  final int reviews;
}

class Activity {
  const Activity({
    required this.today,
    required this.days,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalReviews,
    required this.daysStudied,
  });

  factory Activity.fromJson(Json json) => Activity(
    today: json['today'] as String,
    days: [
      for (final day in json['days'] as List<dynamic>)
        DayCount(date: (day as Json)['date'] as String, reviews: day['reviews'] as int),
    ],
    currentStreak: json['current_streak'] as int,
    longestStreak: json['longest_streak'] as int,
    totalReviews: json['total_reviews'] as int,
    daysStudied: json['days_studied'] as int,
  );

  /// The current study day (YYYY-MM-DD) in the user's timezone, rolling over at 04:00.
  final String today;
  final List<DayCount> days;
  final int currentStreak;
  final int longestStreak;
  final int totalReviews;
  final int daysStudied;
}

class DeckStats {
  const DeckStats({
    required this.deckId,
    required this.name,
    required this.states,
    required this.retention,
  });

  factory DeckStats.fromJson(Json json) => DeckStats(
    deckId: json['deck_id'] as String,
    name: json['name'] as String,
    states: CardStates.fromJson(json['states'] as Json),
    retention: Retention.fromJson(json['retention'] as Json),
  );

  final String deckId;
  final String name;
  final CardStates states;
  final Retention retention;
}

class Stats {
  const Stats({
    required this.activity,
    required this.retentionLast30Days,
    required this.states,
    required this.decks,
  });

  factory Stats.fromJson(Json json) => Stats(
    activity: Activity.fromJson(json['activity'] as Json),
    retentionLast30Days: Retention.fromJson(json['retention_last_30_days'] as Json),
    states: CardStates.fromJson(json['states'] as Json),
    decks: [for (final deck in json['decks'] as List<dynamic>) DeckStats.fromJson(deck as Json)],
  );

  final Activity activity;
  final Retention retentionLast30Days;
  final CardStates states;
  final List<DeckStats> decks;
}
