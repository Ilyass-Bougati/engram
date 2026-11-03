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


class DeckRole(StrEnum):
    owner = "owner"
    editor = "editor"
    viewer = "viewer"


DECK_ROLE_RANK = {DeckRole.viewer: 0, DeckRole.editor: 1, DeckRole.owner: 2}


class Deck(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    name: str
    description: str = ""
    created_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)
    updated_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)


class DeckMember(SQLModel, table=True):
    __tablename__ = "deck_member"
    __table_args__ = (
        # Ownership lives here rather than on deck, so one check covers every role.
        sa.Index(
            "uq_deck_member_one_owner",
            "deck_id",
            unique=True,
            postgresql_where=sa.text("role = 'owner'"),
        ),
        sa.CheckConstraint("new_cards_per_day BETWEEN 0 AND 9999", name="new_cards_per_day_range"),
    )

    deck_id: uuid.UUID = Field(foreign_key="deck.id", ondelete="CASCADE", primary_key=True)
    user_id: uuid.UUID = Field(
        foreign_key="user.id", ondelete="CASCADE", primary_key=True, index=True
    )
    role: DeckRole = Field(
        sa_type=sa.Enum(DeckRole, native_enum=False, length=16, create_constraint=True)
    )
    new_cards_per_day: int = 20
    created_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)


class CardKind(StrEnum):
    basic = "basic"
    quiz = "quiz"


class Card(SQLModel, table=True):
    __table_args__ = (
        sa.Index("ix_card_deck_id_created_at", "deck_id", "created_at"),
        sa.Index(
            "ix_card_search_text_trgm",
            "search_text",
            postgresql_using="gin",
            postgresql_ops={"search_text": "gin_trgm_ops"},
        ),
        sa.CheckConstraint(
            "(kind = 'basic' AND answer IS NOT NULL AND explanation IS NULL AND NOT select_all)"
            " OR (kind = 'quiz' AND answer IS NULL)",
            name="fields_match_kind",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    deck_id: uuid.UUID = Field(foreign_key="deck.id", ondelete="CASCADE")
    kind: CardKind = Field(
        sa_type=sa.Enum(CardKind, native_enum=False, length=16, create_constraint=True)
    )
    # Front of a basic card, or the question of a quiz card.
    prompt: str
    # Back of a basic card; quiz answers live in quiz_option.
    answer: str | None = None
    explanation: str | None = None
    select_all: bool = False
    # Every text field of the card joined, so substring search hits a single trigram index.
    search_text: str
    created_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)
    updated_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)


class QuizOption(SQLModel, table=True):
    __tablename__ = "quiz_option"
    __table_args__ = (sa.UniqueConstraint("card_id", "position"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    card_id: uuid.UUID = Field(foreign_key="card.id", ondelete="CASCADE", index=True)
    position: int
    text: str
    is_correct: bool


class CardTag(SQLModel, table=True):
    __tablename__ = "card_tag"

    card_id: uuid.UUID = Field(foreign_key="card.id", ondelete="CASCADE", primary_key=True)
    tag: str = Field(primary_key=True, index=True)


class ReviewState(SQLModel, table=True):
    __tablename__ = "review_state"
    __table_args__ = (sa.Index("ix_review_state_user_id_due", "user_id", "due"),)

    user_id: uuid.UUID = Field(foreign_key="user.id", ondelete="CASCADE", primary_key=True)
    card_id: uuid.UUID = Field(foreign_key="card.id", ondelete="CASCADE", primary_key=True)
    # FSRS card fields, as py-fsrs defines them; state is fsrs.State (1 learning, 2 review,
    # 3 relearning).
    state: int
    step: int | None = None
    stability: float | None = None
    difficulty: float | None = None
    due: datetime = Field(sa_type=Timestamp)
    last_review: datetime | None = Field(default=None, sa_type=Timestamp)
    # When the card first entered this user's study; drives the daily new-card limit.
    introduced_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)
    # Set by a correct quiz answer and cleared by the rating that follows, so Hard/Good/Easy
    # on a quiz card is only accepted after the server graded it correct.
    quiz_correct_pending_at: datetime | None = Field(default=None, sa_type=Timestamp)


class ReviewLog(SQLModel, table=True):
    __tablename__ = "review_log"
    __table_args__ = (
        sa.Index("ix_review_log_user_id_card_id_reviewed_at", "user_id", "card_id", "reviewed_at"),
        sa.CheckConstraint("rating BETWEEN 1 AND 4", name="rating_range"),
    )

    id: int | None = Field(
        default=None, sa_column=sa.Column(sa.BigInteger, sa.Identity(), primary_key=True)
    )
    user_id: uuid.UUID = Field(foreign_key="user.id", ondelete="CASCADE")
    card_id: uuid.UUID = Field(foreign_key="card.id", ondelete="CASCADE")
    rating: int = Field(sa_type=sa.SmallInteger)
    reviewed_at: datetime = Field(default_factory=utcnow, sa_type=Timestamp)
