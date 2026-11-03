import uuid
from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import tuple_
from sqlmodel import Session, col, func, select

from app.cards import CardDetails, add_cards, replace_card_content
from app.db import SessionDep
from app.deck_format import CardData
from app.deps import DeckAccess, EditorAccess, ViewerAccess
from app.models import DECK_ROLE_RANK, Card, CardKind, CardTag, DeckRole

router = APIRouter(prefix="/decks/{deck_id}", tags=["cards"])


class QuizOptionView(BaseModel):
    id: uuid.UUID
    text: str


class QuizOptionWithKey(QuizOptionView):
    correct: bool


class BasicCardView(BaseModel):
    id: uuid.UUID
    type: Literal["basic"] = "basic"
    front: str
    back: str
    tags: list[str]
    created_at: datetime
    updated_at: datetime


class QuizCardView(BaseModel):
    id: uuid.UUID
    type: Literal["quiz"] = "quiz"
    question: str
    select_all: bool
    # Viewers get options without `correct` and no explanation: the only way they see the
    # answer is by answering in review.
    options: list[QuizOptionWithKey] | list[QuizOptionView]
    explanation: str | None = None
    tags: list[str]
    created_at: datetime
    updated_at: datetime


CardView = Annotated[BasicCardView | QuizCardView, Field(discriminator="type")]


def _card_views(session: Session, access: DeckAccess, cards: list[Card]) -> list[CardView]:
    details = CardDetails(session, [card.id for card in cards])
    show_key = DECK_ROLE_RANK[access.member.role] >= DECK_ROLE_RANK[DeckRole.editor]
    views: list[CardView] = []
    for card in cards:
        if card.kind == CardKind.basic:
            views.append(
                BasicCardView(
                    id=card.id,
                    front=card.prompt,
                    back=card.answer or "",
                    tags=details.tags[card.id],
                    created_at=card.created_at,
                    updated_at=card.updated_at,
                )
            )
            continue
        options = details.options[card.id]
        views.append(
            QuizCardView(
                id=card.id,
                question=card.prompt,
                select_all=card.select_all,
                options=(
                    [QuizOptionWithKey(id=o.id, text=o.text, correct=o.is_correct) for o in options]
                    if show_key
                    else [QuizOptionView(id=o.id, text=o.text) for o in options]
                ),
                explanation=card.explanation if show_key else None,
                tags=details.tags[card.id],
                created_at=card.created_at,
                updated_at=card.updated_at,
            )
        )
    return views


def _card_in_deck(session: Session, access: DeckAccess, card_id: uuid.UUID) -> Card:
    # Filtering on deck_id stops a card ID from another deck being reached through this one.
    card = session.exec(
        select(Card).where(Card.id == card_id, Card.deck_id == access.deck.id)
    ).first()
    if card is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Card not found.")
    return card


class CardPage(BaseModel):
    cards: list[CardView]
    # Pass back as `cursor` to get the next page; null on the last page.
    next_cursor: str | None


def _escape_like(text: str) -> str:
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


@router.get("/cards")
def list_cards(
    access: ViewerAccess,
    session: SessionDep,
    *,
    q: Annotated[str | None, Query(max_length=200)] = None,
    tag: Annotated[str | None, Query(max_length=50)] = None,
    cursor: Annotated[str | None, Query(max_length=100)] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> CardPage:
    """Cards in the deck, oldest first.

    `q` matches any text on the card and `tag` one tag. Pass `next_cursor` back as `cursor`
    for the next page. Quiz options carry `is_correct` only for editors and the owner.
    """
    query = select(Card).where(Card.deck_id == access.deck.id)
    if q and q.strip():
        query = query.where(
            col(Card.search_text).ilike(f"%{_escape_like(q.strip())}%", escape="\\")
        )
    if tag:
        query = query.where(
            col(Card.id).in_(select(CardTag.card_id).where(CardTag.tag == tag.strip().lower()))
        )
    if cursor:
        created_at, card_id = _parse_cursor(cursor)
        query = query.where(tuple_(col(Card.created_at), col(Card.id)) > (created_at, card_id))
    cards = list(
        session.exec(query.order_by(col(Card.created_at), col(Card.id)).limit(limit + 1)).all()
    )
    has_more = len(cards) > limit
    cards = cards[:limit]
    last = cards[-1] if has_more else None
    next_cursor = f"{last.created_at.isoformat()}_{last.id}" if last else None
    return CardPage(cards=_card_views(session, access, cards), next_cursor=next_cursor)


def _parse_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    created_at, _, card_id = cursor.rpartition("_")
    try:
        return datetime.fromisoformat(created_at), uuid.UUID(card_id)
    except ValueError as error:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Invalid cursor. Start again from page one."
        ) from error


@router.post("/cards", status_code=status.HTTP_201_CREATED)
def create_card(body: CardData, access: EditorAccess, session: SessionDep) -> CardView:
    """Add a card."""
    [card] = add_cards(session, access.deck.id, [body])
    session.commit()
    return _card_views(session, access, [card])[0]


@router.get("/cards/{card_id}")
def get_card(card_id: uuid.UUID, access: ViewerAccess, session: SessionDep) -> CardView:
    """A card. Quiz options carry `is_correct` only for editors and the owner."""
    return _card_views(session, access, [_card_in_deck(session, access, card_id)])[0]


@router.put("/cards/{card_id}")
def update_card(
    card_id: uuid.UUID, body: CardData, access: EditorAccess, session: SessionDep
) -> CardView:
    """Replace a card's content.

    The body is the whole card; options and tags are replaced. Review progress is kept.
    """
    card = _card_in_deck(session, access, card_id)
    replace_card_content(session, card, body)
    session.commit()
    return _card_views(session, access, [card])[0]


@router.delete("/cards/{card_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_card(card_id: uuid.UUID, access: EditorAccess, session: SessionDep) -> None:
    """Delete a card and every member's progress on it."""
    session.delete(_card_in_deck(session, access, card_id))
    session.commit()


class TagCount(BaseModel):
    tag: str
    card_count: int


@router.get("/tags")
def list_tags(access: ViewerAccess, session: SessionDep) -> list[TagCount]:
    """Tags used in the deck, with card counts."""
    rows = session.exec(
        select(CardTag.tag, func.count())
        .join(Card)
        .where(Card.deck_id == access.deck.id)
        .group_by(col(CardTag.tag))
        .order_by(col(CardTag.tag))
    ).all()
    return [TagCount(tag=tag, card_count=card_count) for tag, card_count in rows]
