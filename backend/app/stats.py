"""A user's own study statistics.

Days are study days: in the user's timezone, rolling over at 04:00 like the review queue.
Retention counts only answers given on a later study day than the card's previous answer, so
the same-day steps of learning a card don't count as remembering it. That needs no extra
column, so it works on history imported from Anki as well.
"""

import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import fsrs
import sqlalchemy as sa
from pydantic import BaseModel
from sqlalchemy.orm import Mapped
from sqlmodel import Session, col, func, select

from app.models import Card, Deck, DeckMember, ReviewLog, ReviewState, User
from app.scheduling import DAY_ROLLOVER_HOUR

ACTIVITY_DAYS = 365
RETENTION_MONTHS = 12
# Anki's line between young and mature cards.
MATURE_INTERVAL = timedelta(days=21)


class DayCount(BaseModel):
    date: date
    reviews: int


class Activity(BaseModel):
    today: date
    # Days with at least one review in the last 365, oldest first.
    days: list[DayCount]
    current_streak: int
    longest_streak: int
    total_reviews: int
    days_studied: int


class Retention(BaseModel):
    reviews: int
    remembered: int


class MonthRetention(Retention):
    month: str


class CardStates(BaseModel):
    new: int = 0
    learning: int = 0
    young: int = 0
    mature: int = 0


class DeckStats(BaseModel):
    deck_id: uuid.UUID
    name: str
    states: CardStates
    # Over the past year.
    retention: Retention


class Stats(BaseModel):
    activity: Activity
    retention_last_30_days: Retention
    retention_by_month: list[MonthRetention]
    states: CardStates
    decks: list[DeckStats]


def _study_day(
    timestamp: Mapped[datetime] | sa.ColumnElement[datetime], timezone: str
) -> sa.ColumnElement[date]:
    local = func.timezone(timezone, timestamp)
    return sa.cast(local - timedelta(hours=DAY_ROLLOVER_HOUR), sa.Date)


def _streaks(days: list[date], today: date) -> tuple[int, int]:
    longest = run = 0
    previous: date | None = None
    for day in days:
        run = run + 1 if previous == day - timedelta(days=1) else 1
        longest = max(longest, run)
        previous = day
    studied = set(days)
    # Today still counts toward the streak before its first review.
    day = today if today in studied else today - timedelta(days=1)
    current = 0
    while day in studied:
        current += 1
        day -= timedelta(days=1)
    return current, longest


def _months_back(today: date, count: int) -> list[str]:
    year, month = today.year, today.month
    months = []
    for _ in range(count):
        months.append(f"{year:04d}-{month:02d}")
        year, month = (year, month - 1) if month > 1 else (year - 1, 12)
    return months[::-1]


def user_stats(session: Session, user: User, now: datetime) -> Stats:
    today = (now.astimezone(ZoneInfo(user.timezone)) - timedelta(hours=DAY_ROLLOVER_HOUR)).date()
    mine = col(ReviewLog.user_id) == user.id

    review_day = _study_day(col(ReviewLog.reviewed_at), user.timezone)
    per_day = session.exec(
        select(review_day, func.count()).where(mine).group_by(review_day).order_by(review_day)
    ).all()
    current_streak, longest_streak = _streaks([day for day, _ in per_day], today)
    year_ago = today - timedelta(days=ACTIVITY_DAYS - 1)
    activity = Activity(
        today=today,
        days=[DayCount(date=day, reviews=count) for day, count in per_day if day >= year_ago],
        current_streak=current_streak,
        longest_streak=longest_streak,
        total_reviews=sum(count for _, count in per_day),
        days_studied=len(per_day),
    )

    # Each answer next to the card's previous one, then only those from a later study day.
    previous = func.lag(ReviewLog.reviewed_at).over(
        partition_by=col(ReviewLog.card_id),
        order_by=(col(ReviewLog.reviewed_at), col(ReviewLog.id)),
    )
    answers = (
        select(
            col(ReviewLog.card_id).label("card_id"),
            col(ReviewLog.rating).label("rating"),
            review_day.label("day"),
            _study_day(previous, user.timezone).label("previous_day"),
        )
        .where(mine)
        .subquery()
    )
    retention_rows = session.exec(
        select(
            Card.deck_id,
            answers.c.day,
            func.count(),
            func.count().filter(answers.c.rating > fsrs.Rating.Again),
        )
        .join(Card, col(Card.id) == answers.c.card_id)
        .where(answers.c.previous_day < answers.c.day, answers.c.day >= year_ago)
        .group_by(col(Card.deck_id), answers.c.day)
    ).all()

    months = _months_back(today, RETENTION_MONTHS)
    by_month = {month: MonthRetention(month=month, reviews=0, remembered=0) for month in months}
    by_deck: defaultdict[uuid.UUID, Retention] = defaultdict(
        lambda: Retention(reviews=0, remembered=0)
    )
    last_30_days = Retention(reviews=0, remembered=0)
    for deck_id, day, reviews, remembered in retention_rows:
        for bucket in (
            by_month.get(f"{day.year:04d}-{day.month:02d}"),
            by_deck[deck_id],
            last_30_days if day > today - timedelta(days=30) else None,
        ):
            if bucket is not None:
                bucket.reviews += reviews
                bucket.remembered += remembered

    # Card states, for decks the user can study now.
    state = col(ReviewState.state)
    interval = col(ReviewState.due) - col(ReviewState.last_review)
    learning = state.in_([fsrs.State.Learning, fsrs.State.Relearning])
    in_review = state == fsrs.State.Review
    deck_rows = (
        session.connection()
        .execute(
            sa.select(
                col(Deck.id),
                col(Deck.name),
                func.count(col(Card.id)).filter(col(ReviewState.card_id).is_(None)),
                func.count().filter(learning),
                func.count().filter(in_review & (interval < MATURE_INTERVAL)),
                func.count().filter(in_review & (interval >= MATURE_INTERVAL)),
            )
            .join(
                DeckMember, (col(DeckMember.deck_id) == Deck.id) & (DeckMember.user_id == user.id)
            )
            .outerjoin(Card, col(Card.deck_id) == Deck.id)
            .outerjoin(
                ReviewState,
                (col(ReviewState.card_id) == Card.id) & (col(ReviewState.user_id) == user.id),
            )
            .group_by(col(Deck.id))
            .order_by(func.lower(Deck.name), col(Deck.id))
        )
        .all()
    )
    decks = [
        DeckStats(
            deck_id=deck_id,
            name=name,
            states=CardStates(new=new, learning=learning_count, young=young, mature=mature),
            retention=by_deck.get(deck_id, Retention(reviews=0, remembered=0)),
        )
        for deck_id, name, new, learning_count, young, mature in deck_rows
    ]
    totals = CardStates()
    for deck in decks:
        totals.new += deck.states.new
        totals.learning += deck.states.learning
        totals.young += deck.states.young
        totals.mature += deck.states.mature

    return Stats(
        activity=activity,
        retention_last_30_days=last_30_days,
        retention_by_month=list(by_month.values()),
        states=totals,
        decks=decks,
    )
