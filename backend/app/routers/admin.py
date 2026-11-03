import uuid
from datetime import datetime, timedelta
from enum import StrEnum

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import aliased
from sqlmodel import col, select

from app.db import SessionDep
from app.deps import AdminUser, require_admin
from app.models import GlobalRole, Invite, User, utcnow
from app.routers.auth import revoke_all_user_tokens
from app.schemas import StrictModel
from app.security import new_opaque_token

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])

INVITE_TTL = timedelta(days=7)


class InviteState(StrEnum):
    pending = "pending"
    used = "used"
    expired = "expired"
    revoked = "revoked"


class InviteSummary(BaseModel):
    id: uuid.UUID
    state: InviteState
    created_at: datetime
    expires_at: datetime
    created_by: str
    used_by: str | None
    used_at: datetime | None


class CreatedInvite(BaseModel):
    invite: InviteSummary
    # Returned once; only its hash is stored.
    token: str


def _invite_state(invite: Invite) -> InviteState:
    if invite.used_at is not None:
        return InviteState.used
    if invite.revoked_at is not None:
        return InviteState.revoked
    if invite.expires_at <= utcnow():
        return InviteState.expired
    return InviteState.pending


def _summarize(invite: Invite, created_by: str, used_by: str | None) -> InviteSummary:
    return InviteSummary(
        id=invite.id,
        state=_invite_state(invite),
        created_at=invite.created_at,
        expires_at=invite.expires_at,
        created_by=created_by,
        used_by=used_by,
        used_at=invite.used_at,
    )


@router.get("/invites")
def list_invites(session: SessionDep) -> list[InviteSummary]:
    creator = aliased(User)
    redeemer = aliased(User)
    rows = session.exec(
        select(Invite, creator.username, redeemer.username)
        .join(creator, col(Invite.created_by_id) == creator.id)
        .outerjoin(redeemer, col(Invite.used_by_id) == redeemer.id)
        .order_by(col(Invite.created_at).desc())
    ).all()
    return [_summarize(invite, created_by, used_by) for invite, created_by, used_by in rows]


@router.post("/invites", status_code=status.HTTP_201_CREATED)
def create_invite(admin: AdminUser, session: SessionDep) -> CreatedInvite:
    token, token_hash = new_opaque_token()
    invite = Invite(token_hash=token_hash, created_by_id=admin.id, expires_at=utcnow() + INVITE_TTL)
    session.add(invite)
    session.commit()
    session.refresh(invite)
    return CreatedInvite(invite=_summarize(invite, admin.username, None), token=token)


@router.delete("/invites/{invite_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_invite(invite_id: uuid.UUID, session: SessionDep) -> None:
    invite = session.get(Invite, invite_id)
    if invite is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Invite not found.")
    if invite.used_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "This invite was already used.")
    if invite.revoked_at is None:
        invite.revoked_at = utcnow()
        session.add(invite)
        session.commit()


class AdminUserView(BaseModel):
    id: uuid.UUID
    username: str
    role: GlobalRole
    is_active: bool
    created_at: datetime


@router.get("/users")
def list_users(session: SessionDep) -> list[AdminUserView]:
    users = session.exec(select(User).order_by(col(User.username))).all()
    return [AdminUserView.model_validate(user, from_attributes=True) for user in users]


class UserUpdate(StrictModel):
    is_active: bool | None = None
    role: GlobalRole | None = None


@router.patch("/users/{user_id}")
def update_user(
    user_id: uuid.UUID, body: UserUpdate, admin: AdminUser, session: SessionDep
) -> AdminUserView:
    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found.")
    # Blocking self-changes also guarantees at least one active admin always remains.
    if user.id == admin.id and (body.is_active is False or body.role == GlobalRole.user):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "You can't deactivate or demote yourself. Ask another admin.",
        )
    if body.role is not None:
        user.role = body.role
    if body.is_active is not None and body.is_active != user.is_active:
        user.is_active = body.is_active
        if not body.is_active:
            user.token_version += 1
            revoke_all_user_tokens(session, user.id)
    session.add(user)
    session.commit()
    session.refresh(user)
    return AdminUserView.model_validate(user, from_attributes=True)
