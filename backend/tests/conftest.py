import os
import secrets
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from pathlib import Path

import pytest
from testcontainers.community.postgres import PostgresContainer

# The app reads its config at import time, so the database must exist before any app import.
_postgres = PostgresContainer("postgres:16-alpine", driver="psycopg").start()
os.environ["DATABASE_URL"] = _postgres.get_connection_url()
os.environ["JWT_SECRET"] = secrets.token_urlsafe(48)

from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402
from sqlmodel import Session, SQLModel  # noqa: E402

from app.db import engine  # noqa: E402
from app.models import GlobalRole, User  # noqa: E402
from app.rate_limit import ALL_LIMITERS  # noqa: E402
from tests.helpers import (  # noqa: E402
    BASIC_CARD,
    QUIZ_CARD,
    create_card,
    create_deck,
    create_user,
    new_client,
    share,
    sign_in,
)

BACKEND_DIR = Path(__file__).resolve().parent.parent

command.upgrade(Config(str(BACKEND_DIR / "alembic.ini")), "head")


def pytest_unconfigure() -> None:
    engine.dispose()
    _postgres.stop()


@pytest.fixture(autouse=True)
def _clean_state() -> Iterator[None]:
    yield
    tables = ", ".join(f'"{table.name}"' for table in SQLModel.metadata.sorted_tables)
    with engine.begin() as connection:
        connection.execute(text(f"TRUNCATE {tables} CASCADE"))
    for limiter in ALL_LIMITERS:
        limiter.reset()


@pytest.fixture
def db() -> Iterator[Session]:
    with Session(engine) as session:
        yield session


SignedIn = Callable[..., tuple[TestClient, User]]


@pytest.fixture
def signed_in() -> SignedIn:
    def make(username: str, role: GlobalRole = GlobalRole.user) -> tuple[TestClient, User]:
        user = create_user(username, role=role)
        client = new_client()
        sign_in(client, username)
        return client, user

    return make


@dataclass
class Team:
    owner: TestClient
    editor: TestClient
    viewer: TestClient
    outsider: TestClient
    owner_user: User
    editor_user: User
    viewer_user: User
    outsider_user: User
    deck_id: str
    card_id: str
    quiz_card_id: str


@pytest.fixture
def team(signed_in: SignedIn) -> Team:
    owner, owner_user = signed_in("alice")
    editor, editor_user = signed_in("erin")
    viewer, viewer_user = signed_in("vic")
    outsider, outsider_user = signed_in("bob")
    deck_id = create_deck(owner)
    share(owner, deck_id, "erin", "editor")
    share(owner, deck_id, "vic", "viewer")
    return Team(
        owner=owner,
        editor=editor,
        viewer=viewer,
        outsider=outsider,
        owner_user=owner_user,
        editor_user=editor_user,
        viewer_user=viewer_user,
        outsider_user=outsider_user,
        deck_id=deck_id,
        card_id=create_card(owner, deck_id, BASIC_CARD),
        quiz_card_id=create_card(owner, deck_id, QUIZ_CARD),
    )
