import uuid
from typing import Annotated

from fastapi import APIRouter, Cookie, Depends, HTTPException, Response, status
from fastapi.responses import JSONResponse
from sqlmodel import Session, col, select, update

from app.db import SessionDep
from app.deps import PUBLIC, require_csrf_header
from app.models import RefreshToken, User, utcnow
from app.rate_limit import (
    limit_by_ip,
    login_failure_limiter,
    login_ip_limiter,
    refresh_ip_limiter,
)
from app.schemas import SessionResponse, StrictModel, UserPublic
from app.security import (
    DUMMY_PASSWORD_HASH,
    create_access_token,
    hash_opaque_token,
    new_opaque_token,
    refresh_token_expiry,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])

REFRESH_COOKIE = "engram_refresh"
REFRESH_COOKIE_PATH = "/api/auth"


def start_session(
    session: Session, user: User, response: Response, family_id: uuid.UUID | None = None
) -> SessionResponse:
    token, token_hash = new_opaque_token()
    refresh_token = RefreshToken(
        user_id=user.id,
        family_id=family_id or uuid.uuid4(),
        token_hash=token_hash,
        expires_at=refresh_token_expiry(),
    )
    session.add(refresh_token)
    session.commit()
    response.set_cookie(
        REFRESH_COOKIE,
        token,
        max_age=int((refresh_token.expires_at - utcnow()).total_seconds()),
        path=REFRESH_COOKIE_PATH,
        secure=True,
        httponly=True,
        samesite="lax",
    )
    return SessionResponse(
        access_token=create_access_token(user.id, user.token_version),
        user=UserPublic.model_validate(user),
    )


def revoke_token_family(session: Session, family_id: uuid.UUID) -> None:
    session.exec(
        update(RefreshToken)
        .where(col(RefreshToken.family_id) == family_id, col(RefreshToken.revoked_at).is_(None))
        .values(revoked_at=utcnow())
    )


def revoke_all_user_tokens(session: Session, user_id: uuid.UUID) -> None:
    session.exec(
        update(RefreshToken)
        .where(col(RefreshToken.user_id) == user_id, col(RefreshToken.revoked_at).is_(None))
        .values(revoked_at=utcnow())
    )


def _signed_out(detail: str) -> JSONResponse:
    response = JSONResponse({"detail": detail}, status.HTTP_401_UNAUTHORIZED)
    response.delete_cookie(REFRESH_COOKIE, path=REFRESH_COOKIE_PATH, secure=True, httponly=True)
    return response


class LoginRequest(StrictModel):
    username: str
    password: str


@router.post(
    "/login",
    openapi_extra=PUBLIC,
    dependencies=[Depends(limit_by_ip(login_ip_limiter))],
)
def login(body: LoginRequest, session: SessionDep, response: Response) -> SessionResponse:
    """Sign in.

    Returns an access token and sets the refresh cookie. An unknown username, a wrong
    password and a deactivated account all get the same 401.
    """
    username_key = body.username.casefold()
    login_failure_limiter.check(username_key)
    user = session.exec(select(User).where(User.username == body.username)).first()
    password_ok = verify_password(
        user.password_hash if user else DUMMY_PASSWORD_HASH, body.password
    )
    if user is None or not password_ok or not user.is_active:
        login_failure_limiter.record(username_key)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect username or password.")
    return start_session(session, user, response)


@router.post(
    "/refresh",
    openapi_extra=PUBLIC,
    dependencies=[Depends(require_csrf_header), Depends(limit_by_ip(refresh_ip_limiter))],
    response_model=SessionResponse,
)
def refresh(
    session: SessionDep,
    response: Response,
    refresh_cookie: Annotated[str | None, Cookie(alias=REFRESH_COOKIE)] = None,
) -> SessionResponse | JSONResponse:
    """Get a new access token from the refresh cookie.

    The cookie is rotated: each refresh token works once. Presenting one that was already used
    signs out every session that came from the same sign-in.
    """
    if refresh_cookie is None:
        return _signed_out("You are signed out.")
    # Row lock: two concurrent refreshes with the same token must not both succeed.
    presented = session.exec(
        select(RefreshToken)
        .where(RefreshToken.token_hash == hash_opaque_token(refresh_cookie))
        .with_for_update()
    ).first()
    if presented is None or presented.revoked_at is not None or presented.expires_at <= utcnow():
        return _signed_out("Your session has expired. Sign in again.")
    if presented.used_at is not None:
        # A rotated token came back: someone holds a copy. End every session in the chain.
        revoke_token_family(session, presented.family_id)
        session.commit()
        return _signed_out("Your session has expired. Sign in again.")
    user = session.get(User, presented.user_id)
    if user is None or not user.is_active:
        return _signed_out("Your session has expired. Sign in again.")
    presented.used_at = utcnow()
    session.add(presented)
    return start_session(session, user, response, family_id=presented.family_id)


@router.post(
    "/logout",
    openapi_extra=PUBLIC,
    dependencies=[Depends(require_csrf_header)],
    status_code=status.HTTP_204_NO_CONTENT,
)
def logout(
    session: SessionDep,
    response: Response,
    refresh_cookie: Annotated[str | None, Cookie(alias=REFRESH_COOKIE)] = None,
) -> None:
    """Sign out.

    Revokes this sign-in's refresh tokens and clears the cookie. Succeeds without a cookie too.
    """
    if refresh_cookie is not None:
        presented = session.exec(
            select(RefreshToken).where(RefreshToken.token_hash == hash_opaque_token(refresh_cookie))
        ).first()
        if presented is not None:
            revoke_token_family(session, presented.family_id)
            session.commit()
    response.delete_cookie(REFRESH_COOKIE, path=REFRESH_COOKIE_PATH, secure=True, httponly=True)
