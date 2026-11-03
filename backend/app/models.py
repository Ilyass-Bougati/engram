import uuid
from datetime import UTC, datetime
from enum import StrEnum

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import CITEXT
from sqlmodel import Field, SQLModel


def utcnow() -> datetime:
    return datetime.now(UTC)


class GlobalRole(StrEnum):
    admin = "admin"
    user = "user"


Timestamp = sa.DateTime(timezone=True)


class User(SQLModel, table=True):
    __tablename__ = "user"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    username: str = Field(sa_column=sa.Column(CITEXT, nullable=False, unique=True))
    password_hash: str
    role: GlobalRole = Field(
        default=GlobalRole.user,
        sa_type=sa.Enum(GlobalRole, native_enum=False, length=16, create_constraint=True),
    )
    is_active: bool = True
    # Embedded in access tokens; bumping it invalidates every token issued before.
    token_version: int = 0
    timezone: str = "UTC"
    created_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)


class Invite(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    token_hash: str = Field(unique=True)
    created_by_id: uuid.UUID = Field(foreign_key="user.id")
    created_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)
    expires_at: datetime = Field(sa_type=Timestamp)
    used_at: datetime | None = Field(default=None, sa_type=Timestamp)
    used_by_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")
    revoked_at: datetime | None = Field(default=None, sa_type=Timestamp)


class RefreshToken(SQLModel, table=True):
    __tablename__ = "refresh_token"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(foreign_key="user.id", ondelete="CASCADE", index=True)
    # All tokens descending from one login share a family, so reuse of any of them can
    # revoke the whole chain.
    family_id: uuid.UUID = Field(index=True)
    token_hash: str = Field(unique=True)
    created_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)
    expires_at: datetime = Field(sa_type=Timestamp)
    used_at: datetime | None = Field(default=None, sa_type=Timestamp)
    revoked_at: datetime | None = Field(default=None, sa_type=Timestamp)
