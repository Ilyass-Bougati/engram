from fastapi import APIRouter, HTTPException, Response, status

from app.db import SessionDep
from app.deps import CurrentUser
from app.models import utcnow
from app.routers.auth import revoke_all_user_tokens, start_session
from app.schemas import Password, SessionResponse, StrictModel, Timezone, UserPublic
from app.security import hash_password, verify_password
from app.stats import Stats, user_stats

router = APIRouter(prefix="/me", tags=["me"])


@router.get("")
def get_me(user: CurrentUser) -> UserPublic:
    return UserPublic.model_validate(user)


class ProfileUpdate(StrictModel):
    timezone: Timezone


@router.patch("")
def update_me(body: ProfileUpdate, user: CurrentUser, session: SessionDep) -> UserPublic:
    user.timezone = body.timezone
    session.add(user)
    session.commit()
    session.refresh(user)
    return UserPublic.model_validate(user)


class PasswordChange(StrictModel):
    current_password: str
    new_password: Password


@router.post("/password")
def change_password(
    body: PasswordChange, user: CurrentUser, session: SessionDep, response: Response
) -> SessionResponse:
    if not verify_password(user.password_hash, body.current_password):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Your current password is incorrect.")
    user.password_hash = hash_password(body.new_password)
    user.token_version += 1
    revoke_all_user_tokens(session, user.id)
    session.add(user)
    # Every other session ends; this one continues with a fresh token pair.
    return start_session(session, user, response)


@router.get("/stats")
def get_my_stats(user: CurrentUser, session: SessionDep) -> Stats:
    return user_stats(session, user, utcnow())
