"""Decks, members, cards, quiz options and tags.

Revision ID: 0002
Revises: 0001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TIMESTAMP = sa.DateTime(timezone=True)


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    op.create_table(
        "deck",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("description", sa.String(), nullable=False),
        sa.Column("created_at", TIMESTAMP, nullable=False),
        sa.Column("updated_at", TIMESTAMP, nullable=False),
    )

    op.create_table(
        "deck_member",
        sa.Column(
            "deck_id",
            sa.Uuid(),
            sa.ForeignKey("deck.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("user.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "role",
            sa.Enum(
                "owner",
                "editor",
                "viewer",
                name="deckrole",
                native_enum=False,
                length=16,
                create_constraint=True,
            ),
            nullable=False,
        ),
        sa.Column("new_cards_per_day", sa.Integer(), nullable=False),
        sa.Column("created_at", TIMESTAMP, nullable=False),
        sa.CheckConstraint("new_cards_per_day BETWEEN 0 AND 9999", name="new_cards_per_day_range"),
    )
    op.create_index("ix_deck_member_user_id", "deck_member", ["user_id"])
    op.create_index(
        "uq_deck_member_one_owner",
        "deck_member",
        ["deck_id"],
        unique=True,
        postgresql_where=sa.text("role = 'owner'"),
    )

    op.create_table(
        "card",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "deck_id", sa.Uuid(), sa.ForeignKey("deck.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "kind",
            sa.Enum(
                "basic",
                "quiz",
                name="cardkind",
                native_enum=False,
                length=16,
                create_constraint=True,
            ),
            nullable=False,
        ),
        sa.Column("prompt", sa.String(), nullable=False),
        sa.Column("answer", sa.String(), nullable=True),
        sa.Column("explanation", sa.String(), nullable=True),
        sa.Column("select_all", sa.Boolean(), nullable=False),
        sa.Column("search_text", sa.String(), nullable=False),
        sa.Column("created_at", TIMESTAMP, nullable=False),
        sa.Column("updated_at", TIMESTAMP, nullable=False),
        sa.CheckConstraint(
            "(kind = 'basic' AND answer IS NOT NULL AND explanation IS NULL AND NOT select_all)"
            " OR (kind = 'quiz' AND answer IS NULL)",
            name="fields_match_kind",
        ),
    )
    op.create_index("ix_card_deck_id_created_at", "card", ["deck_id", "created_at"])
    op.create_index(
        "ix_card_search_text_trgm",
        "card",
        ["search_text"],
        postgresql_using="gin",
        postgresql_ops={"search_text": "gin_trgm_ops"},
    )

    op.create_table(
        "quiz_option",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "card_id", sa.Uuid(), sa.ForeignKey("card.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("text", sa.String(), nullable=False),
        sa.Column("is_correct", sa.Boolean(), nullable=False),
        sa.UniqueConstraint("card_id", "position"),
    )
    op.create_index("ix_quiz_option_card_id", "quiz_option", ["card_id"])

    op.create_table(
        "card_tag",
        sa.Column(
            "card_id",
            sa.Uuid(),
            sa.ForeignKey("card.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("tag", sa.String(), primary_key=True),
    )
    op.create_index("ix_card_tag_tag", "card_tag", ["tag"])


def downgrade() -> None:
    op.drop_table("card_tag")
    op.drop_table("quiz_option")
    op.drop_table("card")
    op.drop_table("deck_member")
    op.drop_table("deck")
