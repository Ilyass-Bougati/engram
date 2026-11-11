import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, StringConstraints
from sqlmodel import col, select

from app.db import SessionDep
from app.deck_paths import SEPARATOR, deck_path, moved_name
from app.deps import CollectionDep
from app.models import DeckMember, DeckRole, User, utcnow
from app.routers.decks import DeckView, MyDeckSettings, deck_views
from app.routers.members import ShareRequest
from app.routers.reviews import (
    QuizAnswer,
    QuizResult,
    Rating,
    StudyNext,
    StudyScope,
    grade_quiz,
    rate,
    study_next,
)
from app.schemas import StrictModel

# A collection is a path in deck names (app/deck_paths.py), passed as ?path=. Each route acts
# on the collection's decks you're a member of; changes to a deck's name or members need you
# to own that deck, and decks you don't own are left alone and counted as skipped.
router = APIRouter(prefix="/collections", tags=["collections"])


class CollectionView(BaseModel):
    path: str
    decks: list[DeckView]


class CollectionChange(BaseModel):
    # Decks the change was made to, and decks it left alone because you don't own them.
    changed: int
    skipped: int


@router.get("")
def get_collection(access: CollectionDep, session: SessionDep) -> CollectionView:
    """A collection's decks that you're a member of, with your role and today's counts."""
    return CollectionView(
        path=SEPARATOR.join(access.path), decks=deck_views(session, access.user, access.decks)
    )


class CollectionRename(StrictModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


@router.patch("")
def rename_collection(
    body: CollectionRename, access: CollectionDep, session: SessionDep
) -> CollectionChange:
    """Rename or move a collection.

    The new name may contain `::` to move it into another collection. Only the decks you own
    are renamed.
    """
    owned = access.owned("rename it")
    if not any(part.strip() for part in body.name.split(SEPARATOR)):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "A collection name needs more than ::. Type a name such as Java or Java::Basics.",
        )
    destination = deck_path(body.name)
    now = utcnow()
    for deck in owned:
        name = moved_name(deck.name, access.path, destination)
        if len(name) > 200:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT,
                f'The deck name "{name}" would be longer than 200 characters. Choose a shorter '
                "collection name.",
            )
        deck.name = name
        deck.updated_at = now
        session.add(deck)
    session.commit()
    return CollectionChange(changed=len(owned), skipped=len(access.decks) - len(owned))


@router.delete("")
def delete_collection(access: CollectionDep, session: SessionDep) -> CollectionChange:
    """Delete every deck you own in a collection.

    Their cards and every member's progress on them go too. Decks shared with you stay.
    """
    owned = access.owned("delete it")
    for deck in owned:
        # Members, cards and their review history go with it through ON DELETE CASCADE.
        session.delete(deck)
    session.commit()
    return CollectionChange(changed=len(owned), skipped=len(access.decks) - len(owned))


@router.put("/me")
def update_my_collection_settings(
    body: MyDeckSettings, access: CollectionDep, session: SessionDep
) -> CollectionView:
    """Set your new-card limit on every deck in a collection.

    The limit still counts per deck: 20 on a collection of three decks allows up to 60 new
    cards a day.
    """
    for _, member in access.decks:
        member.new_cards_per_day = body.new_cards_per_day
        session.add(member)
    session.commit()
    return get_collection(access, session)


@router.get("/study/next")
def get_next_collection_card(access: CollectionDep, session: SessionDep) -> StudyNext:
    """The next card to study from any deck in a collection, and what's left today.

    Due cards come first, from whichever deck; then new cards, one deck after another in the
    deck list's order, each up to your limit for that deck.
    """
    return study_next(session, StudyScope.of_collection(access))


@router.post("/reviews")
def rate_collection_card(body: Rating, access: CollectionDep, session: SessionDep) -> StudyNext:
    """Rate a card studied from a collection, and get the collection's next one.

    The same rules as rating in a deck apply.
    """
    return rate(session, StudyScope.of_collection(access), body)


@router.post("/reviews/quiz-answer")
def answer_collection_quiz(
    body: QuizAnswer, access: CollectionDep, session: SessionDep
) -> QuizResult:
    """Answer a quiz card studied from a collection.

    The same rules as answering in a deck apply; `next` comes from the collection.
    """
    return grade_quiz(session, StudyScope.of_collection(access), body)


class CollectionMember(BaseModel):
    user_id: uuid.UUID
    username: str
    # How many of the collection's decks they have each role on.
    roles: dict[DeckRole, int]


@router.get("/members")
def list_collection_members(access: CollectionDep, session: SessionDep) -> list[CollectionMember]:
    """Everyone with access to at least one deck in the collection, and their roles."""
    rows = session.exec(
        select(DeckMember, User)
        .join(User)
        .where(col(DeckMember.deck_id).in_([deck.id for deck, _ in access.decks]))
    ).all()
    members: dict[uuid.UUID, CollectionMember] = {}
    for member, user in rows:
        entry = members.setdefault(
            user.id, CollectionMember(user_id=user.id, username=user.username, roles={})
        )
        entry.roles[member.role] = entry.roles.get(member.role, 0) + 1
    # You first, then everyone else by name.
    return sorted(
        members.values(),
        key=lambda m: (m.user_id != access.user.id, m.username.casefold()),
    )


@router.post("/members")
def share_collection(
    body: ShareRequest, access: CollectionDep, session: SessionDep
) -> CollectionChange:
    """Give an existing user editor or viewer access to every deck you own in a collection.

    Anyone who already has access to one of those decks gets the new role on it.
    """
    owned = access.owned("share it")
    user = session.exec(
        select(User).where(User.username == body.username, col(User.is_active).is_(True))
    ).first()
    if user is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, f"No user named {body.username!r}. Check the spelling."
        )
    if user.id == access.user.id:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "That's you. You already own the decks you'd share."
        )
    changed = 0
    for deck in owned:
        member = session.get(DeckMember, (deck.id, user.id))
        if member is None:
            session.add(DeckMember(deck_id=deck.id, user_id=user.id, role=body.role))
        elif member.role != body.role:
            member.role = body.role
            session.add(member)
        else:
            continue
        changed += 1
    if changed == 0:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"{user.username} already has {body.role} access to every deck you own here.",
        )
    session.commit()
    return CollectionChange(changed=changed, skipped=len(access.decks) - len(owned))


@router.delete("/members/{user_id}")
def remove_collection_member(
    user_id: uuid.UUID, access: CollectionDep, session: SessionDep
) -> CollectionChange:
    """Remove someone from every deck you own in a collection, or leave its shared decks.

    Removing yourself leaves every deck in the collection that you don't own.
    """
    if user_id == access.user.id:
        shared = [m for _, m in access.decks if m.role != DeckRole.owner]
        if not shared:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "You own every deck in this collection, so there's nothing to leave. Delete "
                "them instead.",
            )
        for member in shared:
            session.delete(member)
        session.commit()
        return CollectionChange(changed=len(shared), skipped=len(access.decks) - len(shared))

    owned = access.owned("remove people from it")
    members = session.exec(
        select(DeckMember).where(
            DeckMember.user_id == user_id,
            col(DeckMember.deck_id).in_([deck.id for deck in owned]),
            DeckMember.role != DeckRole.owner,
        )
    ).all()
    if not members:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "That person doesn't have access to any deck you own in this collection.",
        )
    for member in members:
        session.delete(member)
    session.commit()
    return CollectionChange(changed=len(members), skipped=len(access.decks) - len(owned))
