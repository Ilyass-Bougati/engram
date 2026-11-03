import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import fsrs
from sqlmodel import Session, col, func, select

from app.models import Card, ReviewLog, ReviewState, User

scheduler = fsrs.Scheduler()

# Like Anki: a study day rolls over at 04:00 local time, so a late-night session counts
# toward the day it started in.
DAY_ROLLOVER_HOUR = 4
# When nothing is due, learning cards due within this window are shown early instead of
# ending the session a minute before the next step comes up.
LEARN_AHEAD = timedelta(minutes=20)


def study_day_start(now: datetime, timezone: str) -> datetime:
    local_now = now.astimezone(ZoneInfo(timezone))
    start = local_now.replace(hour=DAY_ROLLOVER_HOUR, minute=0, second=0, microsecond=0)
    if local_now < start:
        start -= timedelta(days=1)
    return start.astimezone(UTC)


@dataclass
class StudyCounts:
    due: int
    new: int


def study_counts(
    session: Session,
    user: User,
    limits: dict[uuid.UUID, int],
    now: datetime,
) -> dict[uuid.UUID, StudyCounts]:
    # `limits` maps each deck ID to the user's new_cards_per_day for it.
    deck_ids = list(limits)
    if not deck_ids:
        return {}
    day_start = study_day_start(now, user.timezone)
    states = (
        select(Card.deck_id, func.count())
        .join(ReviewState, col(ReviewState.card_id) == Card.id)
        .where(ReviewState.user_id == user.id, col(Card.deck_id).in_(deck_ids))
        .group_by(col(Card.deck_id))
    )
    due = dict(session.exec(states.where(ReviewState.due <= now)).all())
    introduced = dict(session.exec(states.where(ReviewState.introduced_at >= day_start)).all())
    unseen = dict(
        session.exec(
            select(Card.deck_id, func.count())
            .outerjoin(
                ReviewState,
                (col(ReviewState.card_id) == Card.id) & (col(ReviewState.user_id) == user.id),
            )
            .where(col(Card.deck_id).in_(deck_ids), col(ReviewState.card_id).is_(None))
            .group_by(col(Card.deck_id))
        ).all()
    )
    return {
        deck_id: StudyCounts(
            due=due.get(deck_id, 0),
            new=max(0, min(limit - introduced.get(deck_id, 0), unseen.get(deck_id, 0))),
        )
        for deck_id, limit in limits.items()
    }


def next_card(
    session: Session, user: User, deck_id: uuid.UUID, counts: StudyCounts, now: datetime
) -> Card | None:
    reviewed = (
        select(Card)
        .join(ReviewState, col(ReviewState.card_id) == Card.id)
        .where(Card.deck_id == deck_id, ReviewState.user_id == user.id)
    )
    due_card = session.exec(
        reviewed.where(ReviewState.due <= now).order_by(col(ReviewState.due)).limit(1)
    ).first()
    if due_card:
        return due_card
    if counts.new > 0:
        return session.exec(
            select(Card)
            .where(
                Card.deck_id == deck_id,
                col(Card.id).not_in(
                    select(ReviewState.card_id).where(ReviewState.user_id == user.id)
                ),
            )
            .order_by(col(Card.created_at), col(Card.id))
            .limit(1)
        ).first()
    return session.exec(
        reviewed.where(
            col(ReviewState.state) != fsrs.State.Review,
            ReviewState.due <= now + LEARN_AHEAD,
        )
        .order_by(col(ReviewState.due))
        .limit(1)
    ).first()


def next_due_at(session: Session, user: User, deck_id: uuid.UUID) -> datetime | None:
    return session.exec(
        select(func.min(ReviewState.due))
        .join(Card, col(ReviewState.card_id) == Card.id)
        .where(Card.deck_id == deck_id, ReviewState.user_id == user.id)
    ).one()


def apply_rating(session: Session, state: ReviewState, rating: fsrs.Rating, now: datetime) -> None:
    scheduled, _ = scheduler.review_card(
        fsrs.Card(
            state=fsrs.State(state.state),
            step=state.step,
            stability=state.stability,
            difficulty=state.difficulty,
            due=state.due,
            last_review=state.last_review,
        ),
        rating,
        review_datetime=now,
    )
    state.state = scheduled.state.value
    state.step = scheduled.step
    state.stability = scheduled.stability
    state.difficulty = scheduled.difficulty
    state.due = scheduled.due
    state.last_review = scheduled.last_review
    state.quiz_correct_pending_at = None
    session.add(state)
    session.add(
        ReviewLog(
            user_id=state.user_id, card_id=state.card_id, rating=rating.value, reviewed_at=now
        )
    )


def new_review_state(user: User, card: Card, now: datetime) -> ReviewState:
    blank = fsrs.Card()
    return ReviewState(
        user_id=user.id,
        card_id=card.id,
        state=blank.state.value,
        step=blank.step,
        due=now,
        introduced_at=now,
    )


def shuffled[T](items: list[T]) -> list[T]:
    copy = list(items)
    secrets.SystemRandom().shuffle(copy)
    return copy
