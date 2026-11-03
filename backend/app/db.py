from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends
from sqlmodel import Session, create_engine

from app.config import settings

# Small pool: one backend process on a shared 4 GB node, Postgres capped at 30 connections.
engine = create_engine(settings.database_url, pool_size=5, max_overflow=5, pool_pre_ping=True)


def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session


SessionDep = Annotated[Session, Depends(get_session)]
