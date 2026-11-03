import re
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Response, status
from pydantic import BaseModel, Field, StringConstraints
from sqlmodel import Session, col, func, select

from app.cards import CardDetails, add_cards
from app.db import SessionDep
from app.deck_format import DeckFile, DeckMeta
from app.deps import CurrentUser, DeckAccess, EditorAccess, OwnerAccess, ViewerAccess
from app.models import Card, Deck, DeckMember, DeckRole, User, utcnow
from app.schemas import StrictModel

router = APIRouter(prefix="/decks", tags=["decks"])


class DeckView(BaseModel):
    id: uuid.UUID
    name: str
    description: str
    role: DeckRole
    card_count: int
    new_cards_per_day: int
    created_at: datetime
    updated_at: datetime


def _deck_view(deck: Deck, member: DeckMember, card_count: int) -> DeckView:
    return DeckView(
        id=deck.id,
        name=deck.name,
        description=deck.description,
        role=member.role,
        card_count=card_count,
        new_cards_per_day=member.new_cards_per_day,
        created_at=deck.created_at,
        updated_at=deck.updated_at,
    )


def _card_count(session: Session, deck_id: uuid.UUID) -> int:
    return session.exec(select(func.count()).where(Card.deck_id == deck_id)).one()


def _create_owned_deck(session: Session, user: User, meta: DeckMeta) -> tuple[Deck, DeckMember]:
    deck = Deck(name=meta.name, description=meta.description)
    session.add(deck)
    session.flush()
    member = DeckMember(deck_id=deck.id, user_id=user.id, role=DeckRole.owner)
    session.add(member)
    return deck, member


@router.get("")
def list_decks(user: CurrentUser, session: SessionDep) -> list[DeckView]:
    card_counts = (
        select(Card.deck_id, func.count().label("card_count"))
        .group_by(col(Card.deck_id))
        .subquery()
    )
    rows = session.exec(
        select(Deck, DeckMember, func.coalesce(card_counts.c.card_count, 0))
        .join(DeckMember)
        .outerjoin(card_counts, card_counts.c.deck_id == Deck.id)
        .where(DeckMember.user_id == user.id)
        .order_by(func.lower(Deck.name), col(Deck.created_at))
    ).all()
    return [_deck_view(deck, member, card_count) for deck, member, card_count in rows]


@router.post("", status_code=status.HTTP_201_CREATED)
def create_deck(body: DeckMeta, user: CurrentUser, session: SessionDep) -> DeckView:
    deck, member = _create_owned_deck(session, user, body)
    session.commit()
    return _deck_view(deck, member, 0)


@router.post("/import", status_code=status.HTTP_201_CREATED)
def import_new_deck(body: DeckFile, user: CurrentUser, session: SessionDep) -> DeckView:
    deck, member = _create_owned_deck(session, user, body.deck)
    add_cards(session, deck.id, body.cards)
    session.commit()
    return _deck_view(deck, member, len(body.cards))


@router.get("/{deck_id}")
def get_deck(access: ViewerAccess, session: SessionDep) -> DeckView:
    return _deck_view(access.deck, access.member, _card_count(session, access.deck.id))


class DeckUpdate(StrictModel):
    name: Annotated[
        str | None, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)
    ] = None
    description: Annotated[str | None, StringConstraints(max_length=2_000)] = None


@router.patch("/{deck_id}")
def update_deck(body: DeckUpdate, access: OwnerAccess, session: SessionDep) -> DeckView:
    deck = access.deck
    if body.name is not None:
        deck.name = body.name
    if body.description is not None:
        deck.description = body.description
    deck.updated_at = utcnow()
    session.add(deck)
    session.commit()
    return _deck_view(deck, access.member, _card_count(session, deck.id))


@router.delete("/{deck_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_deck(access: OwnerAccess, session: SessionDep) -> None:
    # Members, cards and their review history go with it through ON DELETE CASCADE.
    session.delete(access.deck)
    session.commit()


class MyDeckSettings(StrictModel):
    new_cards_per_day: int = Field(ge=0, le=9999)


@router.put("/{deck_id}/me")
def update_my_deck_settings(
    body: MyDeckSettings, access: ViewerAccess, session: SessionDep
) -> DeckView:
    access.member.new_cards_per_day = body.new_cards_per_day
    session.add(access.member)
    session.commit()
    return _deck_view(access.deck, access.member, _card_count(session, access.deck.id))


def _deck_file(session: Session, access: DeckAccess) -> DeckFile:
    cards = session.exec(
        select(Card)
        .where(Card.deck_id == access.deck.id)
        .order_by(col(Card.created_at), col(Card.id))
    ).all()
    details = CardDetails(session, [card.id for card in cards])
    return DeckFile(
        format="engram-deck",
        version=1,
        deck=DeckMeta(name=access.deck.name, description=access.deck.description),
        cards=[details.to_data(card) for card in cards],
    )


@router.post("/{deck_id}/fork", status_code=status.HTTP_201_CREATED)
def fork_deck(access: ViewerAccess, session: SessionDep) -> DeckView:
    # A fork is a plain copy with fresh IDs and no link back; progress isn't copied because
    # review state is keyed by card ID.
    source = _deck_file(session, access)
    meta = DeckMeta(name=f"{source.deck.name} (fork)"[:200], description=source.deck.description)
    deck, member = _create_owned_deck(session, access.user, meta)
    add_cards(session, deck.id, source.cards)
    session.commit()
    return _deck_view(deck, member, len(source.cards))


@router.get("/{deck_id}/export")
def export_deck(access: ViewerAccess, session: SessionDep, response: Response) -> DeckFile:
    slug = re.sub(r"[^a-z0-9]+", "-", access.deck.name.lower()).strip("-") or "deck"
    response.headers["Content-Disposition"] = f'attachment; filename="{slug}.engram.json"'
    return _deck_file(session, access)


class ImportResult(BaseModel):
    imported: int
    deck: DeckView


@router.post("/{deck_id}/import")
def import_into_deck(body: DeckFile, access: EditorAccess, session: SessionDep) -> ImportResult:
    add_cards(session, access.deck.id, body.cards)
    session.commit()
    deck_view = _deck_view(access.deck, access.member, _card_count(session, access.deck.id))
    return ImportResult(imported=len(body.cards), deck=deck_view)
