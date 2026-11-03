from typing import Annotated, Any

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.db import SessionDep
from app.models import GlobalRole, User
from app.security import decode_access_token

# Routes reachable without an access token carry this marker; tests/test_route_auth.py fails
# on any route that has neither the marker nor a get_current_user dependency.
PUBLIC: dict[str, Any] = {"x-public": True}

CSRF_HEADER = "X-Engram-CSRF"

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    session: SessionDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    unauthorized = HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        "Your session has expired. Sign in again.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized
    decoded = decode_access_token(credentials.credentials)
    if decoded is None:
        raise unauthorized
    user_id, token_version = decoded
    user = session.get(User, user_id)
    if user is None or not user.is_active or user.token_version != token_version:
        raise unauthorized
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_admin(user: CurrentUser) -> User:
    if user.role != GlobalRole.admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only admins can do this.")
    return user


AdminUser = Annotated[User, Depends(require_admin)]


def require_csrf_header(
    x_engram_csrf: Annotated[str | None, Header(alias=CSRF_HEADER)] = None,
) -> None:
    # The refresh cookie is sent automatically by the browser; a custom header can't be added
    # by a cross-site form or a no-CORS fetch, so its presence proves a same-origin caller.
    if x_engram_csrf != "1":
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"Missing {CSRF_HEADER} header.")
