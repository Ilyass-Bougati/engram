from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel
from sqlmodel import Session, select

from app.db import SessionDep
from app.deps import PUBLIC
from app.models import Invite, User, utcnow
from app.rate_limit import invite_ip_limiter, limit_by_ip
from app.routers.auth import start_session
from app.schemas import Password, SessionResponse, StrictModel, Timezone, Username
from app.security import hash_opaque_token, hash_password

router = APIRouter(
    prefix="/invites",
    tags=["invites"],
    dependencies=[Depends(limit_by_ip(invite_ip_limiter))],
)

# Used, expired, revoked and unknown tokens all look the same from outside.
INVALID_INVITE = "This invite link is invalid or has expired. Ask your admin for a new one."


def _usable_invite(session: Session, token: str, *, lock: bool) -> Invite:
    query = select(Invite).where(Invite.token_hash == hash_opaque_token(token))
    if lock:
        query = query.with_for_update()
    invite = session.exec(query).first()
    if (
        invite is None
        or invite.used_at is not None
        or invite.revoked_at is not None
        or invite.expires_at <= utcnow()
    ):
        raise HTTPException(status.HTTP_404_NOT_FOUND, INVALID_INVITE)
    return invite


class InviteStatus(BaseModel):
    expires_at: datetime


@router.get("/{token}", openapi_extra=PUBLIC)
def get_invite(token: str, session: SessionDep) -> InviteStatus:
    return InviteStatus(expires_at=_usable_invite(session, token, lock=False).expires_at)


class RedeemRequest(StrictModel):
    username: Username
    password: Password
    timezone: Timezone


@router.post("/{token}/redeem", openapi_extra=PUBLIC, status_code=status.HTTP_201_CREATED)
def redeem_invite(
    token: str, body: RedeemRequest, session: SessionDep, response: Response
) -> SessionResponse:
    # The row lock makes the invite single-use even under concurrent redemptions.
    invite = _usable_invite(session, token, lock=True)
    if session.exec(select(User).where(User.username == body.username)).first():
        raise HTTPException(status.HTTP_409_CONFLICT, "That username is taken. Pick another.")
    user = User(
        username=body.username,
        password_hash=hash_password(body.password),
        timezone=body.timezone,
    )
    session.add(user)
    session.flush()
    invite.used_at = utcnow()
    invite.used_by_id = user.id
    session.add(invite)
    return start_session(session, user, response)
