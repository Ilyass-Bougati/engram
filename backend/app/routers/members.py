import uuid
from typing import Literal

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from sqlmodel import Session, col, select

from app.db import SessionDep
from app.deps import DeckAccess, OwnerAccess, ViewerAccess
from app.models import DeckMember, DeckRole, User
from app.schemas import StrictModel

router = APIRouter(prefix="/decks/{deck_id}/members", tags=["members"])

SharedRole = Literal[DeckRole.editor, DeckRole.viewer]


class MemberView(BaseModel):
    user_id: uuid.UUID
    username: str
    role: DeckRole


def _member(session: Session, access: DeckAccess, user_id: uuid.UUID) -> tuple[DeckMember, User]:
    row = session.exec(
        select(DeckMember, User)
        .join(User)
        .where(DeckMember.deck_id == access.deck.id, DeckMember.user_id == user_id)
    ).first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That person isn't a member of this deck.")
    return row


@router.get("")
def list_members(access: ViewerAccess, session: SessionDep) -> list[MemberView]:
    rows = session.exec(
        select(DeckMember, User)
        .join(User)
        .where(DeckMember.deck_id == access.deck.id)
        .order_by(col(DeckMember.created_at))
    ).all()
    return [
        MemberView(user_id=user.id, username=user.username, role=member.role)
        for member, user in rows
    ]


class ShareRequest(StrictModel):
    username: str
    role: SharedRole


@router.post("", status_code=status.HTTP_201_CREATED)
def share_deck(body: ShareRequest, access: OwnerAccess, session: SessionDep) -> MemberView:
    user = session.exec(
        select(User).where(User.username == body.username, col(User.is_active).is_(True))
    ).first()
    if user is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, f"No user named {body.username!r}. Check the spelling."
        )
    if session.get(DeckMember, (access.deck.id, user.id)):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"{user.username} already has access. Change their role instead.",
        )
    session.add(DeckMember(deck_id=access.deck.id, user_id=user.id, role=body.role))
    session.commit()
    return MemberView(user_id=user.id, username=user.username, role=body.role)


class RoleChange(StrictModel):
    role: SharedRole


@router.patch("/{user_id}")
def change_member_role(
    user_id: uuid.UUID, body: RoleChange, access: OwnerAccess, session: SessionDep
) -> MemberView:
    member, user = _member(session, access, user_id)
    if member.role == DeckRole.owner:
        raise HTTPException(status.HTTP_409_CONFLICT, "The owner's role can't be changed.")
    member.role = body.role
    session.add(member)
    session.commit()
    return MemberView(user_id=user.id, username=user.username, role=member.role)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(user_id: uuid.UUID, access: ViewerAccess, session: SessionDep) -> None:
    # The owner removes anyone else; everyone else can only remove themselves (leave).
    is_owner = access.member.role == DeckRole.owner
    if not is_owner and user_id != access.user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the deck owner can remove members.")
    member, _ = _member(session, access, user_id)
    if member.role == DeckRole.owner:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "The owner can't leave their own deck. Delete it instead."
        )
    session.delete(member)
    session.commit()
