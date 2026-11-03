import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlmodel import Session, select

from app.models import ReviewLog, ReviewState, utcnow
from app.scheduling import study_day_start
from tests.conftest import SignedIn, Team
from tests.helpers import BASIC_CARD, QUIZ_CARD, create_card, create_deck

SINGLE_ANSWER = {
    "type": "quiz",
    "question": "Capital of Morocco?",
    "options": [{"text": "Rabat", "correct": True}, {"text": "Fes", "correct": False}],
    "explanation": "Rabat has been the capital since 1956.",
}


def _next(client: TestClient, deck_id: str) -> dict[str, Any]:
    response = client.get(f"/api/decks/{deck_id}/study/next")
    assert response.status_code == 200
    payload: dict[str, Any] = response.json()
    return payload


def _answer(client: TestClient, deck_id: str, card_id: str, texts: set[str]) -> Any:
    card = _next(client, deck_id)["card"]
    assert card["id"] == card_id
    selected = [o["id"] for o in card["options"] if o["text"] in texts]
    return client.post(
        f"/api/decks/{deck_id}/reviews/quiz-answer",
        json={"card_id": card_id, "selected_option_ids": selected},
    )


def _rate(client: TestClient, deck_id: str, card_id: str, rating: int) -> Any:
    return client.post(f"/api/decks/{deck_id}/reviews", json={"card_id": card_id, "rating": rating})


def _ratings(db: Session, card_id: str) -> list[int]:
    logs = db.exec(select(ReviewLog).where(ReviewLog.card_id == uuid.UUID(card_id))).all()
    return [log.rating for log in logs]


@pytest.fixture
def quiz_deck(signed_in: SignedIn) -> tuple[TestClient, str, str]:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    return client, deck_id, create_card(client, deck_id, SINGLE_ANSWER)


def test_answer_key_is_absent_before_answering(quiz_deck: tuple[TestClient, str, str]) -> None:
    client, deck_id, _ = quiz_deck
    card = _next(client, deck_id)["card"]
    assert all(set(option) == {"id", "text"} for option in card["options"])
    assert "explanation" not in card
    assert "1956" not in str(card)


def test_wrong_answer_forces_again(quiz_deck: tuple[TestClient, str, str], db: Session) -> None:
    client, deck_id, card_id = quiz_deck
    result = _answer(client, deck_id, card_id, {"Fes"}).json()
    assert result["correct"] is False
    assert result["explanation"] == SINGLE_ANSWER["explanation"]
    assert len(result["correct_option_ids"]) == 1
    assert _ratings(db, card_id) == [1]
    # The user can't overrule the server's grade with a better rating.
    assert _rate(client, deck_id, card_id, 3).status_code == 409
    assert _ratings(db, card_id) == [1]


def test_correct_answer_allows_hard_good_easy_only(
    quiz_deck: tuple[TestClient, str, str], db: Session
) -> None:
    client, deck_id, card_id = quiz_deck
    assert _rate(client, deck_id, card_id, 3).status_code == 409
    result = _answer(client, deck_id, card_id, {"Rabat"}).json()
    assert (result["correct"], result["next"]) == (True, None)
    assert _ratings(db, card_id) == []
    assert _rate(client, deck_id, card_id, 1).status_code == 409
    assert _rate(client, deck_id, card_id, 3).status_code == 200
    assert _ratings(db, card_id) == [3]
    # The correct answer is consumed by that rating.
    assert _rate(client, deck_id, card_id, 4).status_code == 409


def test_select_all_needs_exactly_the_correct_set(signed_in: SignedIn, db: Session) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    card_id = create_card(client, deck_id, QUIZ_CARD)
    partial = _answer(client, deck_id, card_id, {"2"}).json()
    assert partial["correct"] is False
    db.connection().execute(text("UPDATE review_state SET due = now() - interval '1 minute'"))
    db.commit()
    assert _answer(client, deck_id, card_id, {"2", "7"}).json()["correct"] is True


def test_server_schedules_and_ignores_client_scheduling(signed_in: SignedIn, db: Session) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    card_id = create_card(client, deck_id, BASIC_CARD)
    sneaky = client.post(
        f"/api/decks/{deck_id}/reviews",
        json={"card_id": card_id, "rating": 3, "due": "2099-01-01T00:00:00Z"},
    )
    assert sneaky.status_code == 422
    assert _rate(client, deck_id, card_id, 4).status_code == 200
    state = db.exec(select(ReviewState)).one()
    assert state.due > utcnow() + timedelta(days=1)
    assert state.stability is not None
    assert _next(client, deck_id)["card"] is None


def test_progress_on_a_shared_deck_is_per_user(team: Team, db: Session) -> None:
    # A limit of 1 and a due card make any leak of the owner's progress visible in the
    # viewer's counts.
    team.viewer.put(f"/api/decks/{team.deck_id}/me", json={"new_cards_per_day": 1})
    owner_next = _next(team.owner, team.deck_id)["card"]
    assert _rate(team.owner, team.deck_id, owner_next["id"], 3).status_code == 200
    db.connection().execute(text("UPDATE review_state SET due = now() - interval '1 minute'"))
    db.commit()

    def counts(client: TestClient) -> tuple[int, int]:
        deck = next(d for d in client.get("/api/decks").json() if d["id"] == team.deck_id)
        return deck["due_count"], deck["new_count"]

    assert counts(team.owner) == (1, 1)
    assert counts(team.viewer) == (0, 1)
    # With no new cards allowed, the owner's due card must not show up in the viewer's queue.
    team.viewer.put(f"/api/decks/{team.deck_id}/me", json={"new_cards_per_day": 0})
    assert _next(team.viewer, team.deck_id)["card"] is None
    assert {log.user_id for log in db.exec(select(ReviewLog))} == {team.owner_user.id}


def test_fork_starts_with_no_progress(team: Team) -> None:
    card = _next(team.viewer, team.deck_id)["card"]
    _rate(team.viewer, team.deck_id, card["id"], 3)
    fork = team.viewer.post(f"/api/decks/{team.deck_id}/fork").json()
    assert (fork["new_count"], fork["due_count"]) == (2, 0)


def test_daily_new_card_limit(signed_in: SignedIn, db: Session) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    first = create_card(client, deck_id, BASIC_CARD)
    second = create_card(client, deck_id, {**BASIC_CARD, "front": "Capital of Peru?"})
    client.put(f"/api/decks/{deck_id}/me", json={"new_cards_per_day": 1})

    # Easy sends it straight to review in days, so the learn-ahead window can't bring it back.
    assert _rate(client, deck_id, first, 4).status_code == 200
    study = _next(client, deck_id)
    assert (study["card"], study["new_count"]) == (None, 0)
    assert study["next_due_at"] is not None
    # Calling the API directly can't get around the limit either.
    assert _rate(client, deck_id, second, 3).status_code == 409

    db.connection().execute(
        text("UPDATE review_state SET introduced_at = now() - interval '1 day'")
    )
    db.commit()
    assert _next(client, deck_id)["new_count"] == 1


@pytest.mark.parametrize(
    ("now", "timezone", "expected"),
    [
        # 02:00 in Berlin (UTC+1) is still the previous study day, which began at 03:00 UTC.
        (
            datetime(2026, 11, 3, 1, 0, tzinfo=UTC),
            "Europe/Berlin",
            datetime(2026, 11, 2, 3, 0, tzinfo=UTC),
        ),
        # 05:00 in Tokyo (UTC+9) is past the rollover: today's 04:00 local is 19:00 UTC.
        (
            datetime(2026, 11, 3, 20, 0, tzinfo=UTC),
            "Asia/Tokyo",
            datetime(2026, 11, 3, 19, 0, tzinfo=UTC),
        ),
    ],
)
def test_study_day_rolls_over_at_4am_local(
    now: datetime, timezone: str, expected: datetime
) -> None:
    assert study_day_start(now, timezone) == expected


def test_review_log_is_append_only(quiz_deck: tuple[TestClient, str, str], db: Session) -> None:
    client, deck_id, card_id = quiz_deck
    _answer(client, deck_id, card_id, {"Fes"})
    with pytest.raises(DBAPIError, match="append-only"):
        db.connection().execute(text("UPDATE review_log SET rating = 4"))
