import uuid
from collections.abc import Callable
from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import select

from app.db import SessionDep
from app.models import DECK_ROLE_RANK, Deck, DeckMember, DeckRole, GlobalRole, User
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


@dataclass
class DeckAccess:
    deck: Deck
    member: DeckMember
    user: User


def require_deck_role(min_role: DeckRole) -> Callable[..., DeckAccess]:
    def dependency(deck_id: uuid.UUID, user: CurrentUser, session: SessionDep) -> DeckAccess:
        row = session.exec(
            select(Deck, DeckMember)
            .join(DeckMember)
            .where(Deck.id == deck_id, DeckMember.user_id == user.id)
        ).first()
        # Non-members get the same 404 as for a deck that doesn't exist, so IDs can't be probed.
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Deck not found.")
        deck, member = row
        if DECK_ROLE_RANK[member.role] < DECK_ROLE_RANK[min_role]:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                f"This needs {min_role} access to the deck; you are a {member.role}.",
            )
        return DeckAccess(deck=deck, member=member, user=user)

    return dependency


# Every route with {deck_id} in its path must depend on one of these;
# tests/test_route_auth.py enforces it.
deck_viewer = require_deck_role(DeckRole.viewer)
deck_editor = require_deck_role(DeckRole.editor)
deck_owner = require_deck_role(DeckRole.owner)
DECK_ROLE_DEPENDENCIES = (deck_viewer, deck_editor, deck_owner)

ViewerAccess = Annotated[DeckAccess, Depends(deck_viewer)]
EditorAccess = Annotated[DeckAccess, Depends(deck_editor)]
OwnerAccess = Annotated[DeckAccess, Depends(deck_owner)]
