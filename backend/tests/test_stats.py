import uuid
from datetime import UTC, date, datetime, timedelta

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.models import ReviewLog, ReviewState, User
from app.stats import user_stats
from tests.conftest import SignedIn
from tests.test_deck_roles import EXAMPLE_DECK

NOW = datetime(2026, 11, 3, 12, 0, tzinfo=UTC)


def deck_with_cards(client: TestClient, name: str = "Algebra") -> tuple[str, list[uuid.UUID]]:
    deck = client.post("/api/decks/import", json={**EXAMPLE_DECK, "deck": {"name": name}}).json()
    cards = client.get(f"/api/decks/{deck['id']}/cards").json()["cards"]
    return deck["id"], [uuid.UUID(card["id"]) for card in cards]


def log(db: Session, user: User, card_id: uuid.UUID, at: datetime, rating: int = 3) -> None:
    db.add(ReviewLog(user_id=user.id, card_id=card_id, rating=rating, reviewed_at=at))


def test_activity_uses_study_days_and_counts_streaks(signed_in: SignedIn, db: Session) -> None:
    client, alice = signed_in("alice")
    _, [card, *_] = deck_with_cards(client)
    for at in (
        datetime(2026, 10, 1, 9, tzinfo=UTC),
        datetime(2026, 10, 2, 9, tzinfo=UTC),
        datetime(2026, 10, 30, 9, tzinfo=UTC),
        datetime(2026, 10, 31, 9, tzinfo=UTC),
        datetime(2026, 11, 1, 9, tzinfo=UTC),
        datetime(2026, 11, 1, 22, tzinfo=UTC),
        # 03:30 is before the 04:00 rollover, so this belongs to November 2.
        datetime(2026, 11, 3, 3, 30, tzinfo=UTC),
        # Older than a year: counts toward totals and streaks, not the heatmap.
        datetime(2025, 6, 1, 9, tzinfo=UTC),
    ):
        log(db, alice, card, at)
    db.commit()

    activity = user_stats(db, alice, NOW).activity
    assert activity.today == date(2026, 11, 3)
    assert [(day.date, day.reviews) for day in activity.days] == [
        (date(2026, 10, 1), 1),
        (date(2026, 10, 2), 1),
        (date(2026, 10, 30), 1),
        (date(2026, 10, 31), 1),
        (date(2026, 11, 1), 2),
        (date(2026, 11, 2), 1),
    ]
    # Nothing studied yet today, but the streak through yesterday still stands.
    assert (activity.current_streak, activity.longest_streak) == (4, 4)
    assert (activity.total_reviews, activity.days_studied) == (8, 7)

    # The same answers in Tokyo (UTC+9): 22:00 UTC on Nov 1 is Nov 2 there, and 03:30 UTC
    # on Nov 3 is midday, so today has a review and the streak runs Oct 30 to Nov 3.
    alice.timezone = "Asia/Tokyo"
    tokyo = user_stats(db, alice, NOW).activity
    assert [day.date for day in tokyo.days[-3:]] == [
        date(2026, 11, 1),
        date(2026, 11, 2),
        date(2026, 11, 3),
    ]
    assert tokyo.current_streak == 5


def test_retention_counts_answers_from_a_later_day_only(signed_in: SignedIn, db: Session) -> None:
    client, alice = signed_in("alice")
    deck_id, [card, other, *_] = deck_with_cards(client)
    day = datetime(2026, 10, 20, 9, tzinfo=UTC)
    log(db, alice, card, day, rating=1)  # first answer: nothing to remember yet
    log(db, alice, card, day + timedelta(minutes=10))  # same day: a learning step
    log(db, alice, card, day + timedelta(days=2))  # remembered
    log(db, alice, card, day + timedelta(days=9), rating=1)  # forgotten
    log(db, alice, other, datetime(2026, 9, 1, 9, tzinfo=UTC))
    log(db, alice, other, datetime(2026, 9, 5, 9, tzinfo=UTC))  # remembered, in September
    db.commit()

    stats = user_stats(db, alice, NOW)
    by_month = {
        month.month: (month.reviews, month.remembered) for month in stats.retention_by_month
    }
    assert len(by_month) == 12
    assert (by_month["2026-09"], by_month["2026-10"], by_month["2026-11"]) == (
        (1, 1),
        (2, 1),
        (0, 0),
    )
    assert (stats.retention_last_30_days.reviews, stats.retention_last_30_days.remembered) == (2, 1)
    [deck] = stats.decks
    assert (str(deck.deck_id), deck.retention.reviews, deck.retention.remembered) == (deck_id, 3, 2)


def test_card_states_cover_my_decks_and_my_progress_only(signed_in: SignedIn, db: Session) -> None:
    client, alice = signed_in("alice")
    _, cards = deck_with_cards(client)
    bob_client, bob = signed_in("bob")
    deck_with_cards(bob_client, "Bob's deck")

    def state(user: User, card_id: uuid.UUID, fsrs_state: int, interval_days: int) -> None:
        db.add(
            ReviewState(
                user_id=user.id,
                card_id=card_id,
                state=fsrs_state,
                due=NOW + timedelta(days=interval_days),
                last_review=NOW,
            )
        )

    state(alice, cards[1], 1, 0)  # learning
    state(alice, cards[2], 2, 5)  # young
    state(alice, cards[3], 2, 30)  # mature
    state(bob, cards[0], 2, 30)  # Bob's progress on a card he can't even see
    db.commit()

    response = client.get("/api/me/stats")
    assert response.status_code == 200
    stats = response.json()
    expected = {"new": 1, "learning": 1, "young": 1, "mature": 1}
    assert stats["states"] == expected
    assert [(deck["name"], deck["states"]) for deck in stats["decks"]] == [("Algebra", expected)]
