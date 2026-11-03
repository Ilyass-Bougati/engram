import uuid
from datetime import datetime, timedelta
from typing import Annotated, Literal

import fsrs
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field
from sqlmodel import Session, col, select

from app.db import SessionDep
from app.deps import DeckAccess, ViewerAccess
from app.models import Card, CardKind, QuizOption, ReviewState, utcnow
from app.scheduling import (
    apply_rating,
    new_review_state,
    next_card,
    next_due_at,
    shuffled,
    study_counts,
)
from app.schemas import StrictModel

router = APIRouter(prefix="/decks/{deck_id}", tags=["reviews"])

QUIZ_ANSWER_TTL = timedelta(hours=1)


class StudyOption(BaseModel):
    id: uuid.UUID
    text: str


class BasicStudyCard(BaseModel):
    id: uuid.UUID
    type: Literal["basic"] = "basic"
    front: str
    back: str


class QuizStudyCard(BaseModel):
    # No correct flags and no explanation: grading happens on the server after answering.
    id: uuid.UUID
    type: Literal["quiz"] = "quiz"
    question: str
    select_all: bool
    options: list[StudyOption]


StudyCard = Annotated[BasicStudyCard | QuizStudyCard, Field(discriminator="type")]


class StudyNext(BaseModel):
    card: StudyCard | None
    due_count: int
    new_count: int
    # When the session is over, the earliest time something becomes due again.
    next_due_at: datetime | None


def _study_next(session: Session, access: DeckAccess) -> StudyNext:
    now = utcnow()
    deck_id = access.deck.id
    counts = study_counts(session, access.user, {deck_id: access.member.new_cards_per_day}, now)[
        deck_id
    ]
    card = next_card(session, access.user, deck_id, counts, now)
    study_card: StudyCard | None = None
    if card is not None and card.kind == CardKind.basic:
        study_card = BasicStudyCard(id=card.id, front=card.prompt, back=card.answer or "")
    elif card is not None:
        options = session.exec(select(QuizOption).where(QuizOption.card_id == card.id)).all()
        study_card = QuizStudyCard(
            id=card.id,
            question=card.prompt,
            select_all=card.select_all,
            # Reshuffled on every review so an answer can't be remembered by its position.
            options=[StudyOption(id=o.id, text=o.text) for o in shuffled(list(options))],
        )
    return StudyNext(
        card=study_card,
        due_count=counts.due,
        new_count=counts.new,
        next_due_at=None if card else next_due_at(session, access.user, deck_id),
    )


@router.get("/study/next")
def get_next_card(access: ViewerAccess, session: SessionDep) -> StudyNext:
    """The next card to study, and what's left today.

    Due cards come first, then new cards up to your daily limit. `card` is null when you're done
    for now. Quiz options are shuffled and carry no answer key.
    """
    return _study_next(session, access)


def _review_target(
    session: Session, access: DeckAccess, card_id: uuid.UUID
) -> tuple[Card, ReviewState]:
    card = session.exec(
        select(Card).where(Card.id == card_id, Card.deck_id == access.deck.id)
    ).first()
    if card is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Card not found.")
    state = session.exec(
        select(ReviewState)
        .where(ReviewState.user_id == access.user.id, ReviewState.card_id == card.id)
        .with_for_update()
    ).first()
    if state is not None:
        return card, state
    now = utcnow()
    deck_id = access.deck.id
    counts = study_counts(session, access.user, {deck_id: access.member.new_cards_per_day}, now)[
        deck_id
    ]
    if counts.new == 0:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "You've reached today's new-card limit for this deck. Raise it in deck settings.",
        )
    return card, new_review_state(access.user, card, now)


class Rating(StrictModel):
    card_id: uuid.UUID
    rating: Annotated[int, Field(ge=1, le=4, description="1 Again, 2 Hard, 3 Good, 4 Easy")]


@router.post("/reviews")
def rate_card(body: Rating, access: ViewerAccess, session: SessionDep) -> StudyNext:
    """Rate the card you just studied, and get the next one.

    The server schedules the next review. A quiz card can be rated only after a correct answer,
    and then only Hard, Good or Easy.
    """
    card, state = _review_target(session, access, body.card_id)
    now = utcnow()
    if card.kind == CardKind.quiz:
        pending = state.quiz_correct_pending_at
        if body.rating == fsrs.Rating.Again or pending is None or pending < now - QUIZ_ANSWER_TTL:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Answer the quiz question first; after a correct answer, rate it Hard, Good "
                "or Easy.",
            )
    apply_rating(session, state, fsrs.Rating(body.rating), now)
    session.commit()
    return _study_next(session, access)


class QuizAnswer(StrictModel):
    card_id: uuid.UUID
    selected_option_ids: Annotated[list[uuid.UUID], Field(min_length=1, max_length=8)]


class QuizResult(BaseModel):
    correct: bool
    correct_option_ids: list[uuid.UUID]
    explanation: str
    # Present after a wrong answer (already rated Again); after a correct one the client
    # sends a rating and gets the next card from that.
    next: StudyNext | None


@router.post("/reviews/quiz-answer")
def answer_quiz(body: QuizAnswer, access: ViewerAccess, session: SessionDep) -> QuizResult:
    """Answer a quiz card.

    A wrong answer counts as Again and `next` holds the next card. After a correct one, rate the
    card within an hour.
    """
    card, state = _review_target(session, access, body.card_id)
    if card.kind != CardKind.quiz:
        raise HTTPException(status.HTTP_409_CONFLICT, "This card isn't a quiz card.")
    options = session.exec(
        select(QuizOption).where(QuizOption.card_id == card.id).order_by(col(QuizOption.position))
    ).all()
    selected = set(body.selected_option_ids)
    if len(selected) != len(body.selected_option_ids) or not selected <= {o.id for o in options}:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "The selected options don't belong to this card. It may have been edited; reload.",
        )
    if not card.select_all and len(selected) != 1:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "This question takes exactly one answer."
        )
    correct_ids = [o.id for o in options if o.is_correct]
    correct = selected == set(correct_ids)
    now = utcnow()
    if correct:
        state.quiz_correct_pending_at = now
        session.add(state)
    else:
        apply_rating(session, state, fsrs.Rating.Again, now)
    session.commit()
    return QuizResult(
        correct=correct,
        correct_option_ids=correct_ids,
        explanation=card.explanation or "",
        next=None if correct else _study_next(session, access),
    )
