"""Per-user review state and the append-only review log.

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TIMESTAMP = sa.DateTime(timezone=True)


def upgrade() -> None:
    op.create_table(
        "review_state",
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("user.id", ondelete="CASCADE"), primary_key=True
        ),
        sa.Column(
            "card_id", sa.Uuid(), sa.ForeignKey("card.id", ondelete="CASCADE"), primary_key=True
        ),
        sa.Column("state", sa.Integer(), nullable=False),
        sa.Column("step", sa.Integer(), nullable=True),
        sa.Column("stability", sa.Float(), nullable=True),
        sa.Column("difficulty", sa.Float(), nullable=True),
        sa.Column("due", TIMESTAMP, nullable=False),
        sa.Column("last_review", TIMESTAMP, nullable=True),
        sa.Column("introduced_at", TIMESTAMP, nullable=False),
        sa.Column("quiz_correct_pending_at", TIMESTAMP, nullable=True),
    )
    op.create_index("ix_review_state_user_id_due", "review_state", ["user_id", "due"])

    op.create_table(
        "review_log",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("user.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "card_id", sa.Uuid(), sa.ForeignKey("card.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("rating", sa.SmallInteger(), nullable=False),
        sa.Column("reviewed_at", TIMESTAMP, nullable=False),
        sa.CheckConstraint("rating BETWEEN 1 AND 4", name="rating_range"),
    )
    op.create_index(
        "ix_review_log_user_id_card_id_reviewed_at",
        "review_log",
        ["user_id", "card_id", "reviewed_at"],
    )
    # Append-only at the database level: history can only disappear along with its card.
    op.execute(
        """
        CREATE FUNCTION review_log_reject_update() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'review_log is append-only';
        END;
        $$
        """
    )
    op.execute(
        "CREATE TRIGGER review_log_append_only BEFORE UPDATE ON review_log "
        "FOR EACH ROW EXECUTE FUNCTION review_log_reject_update()"
    )


def downgrade() -> None:
    op.drop_table("review_log")
    op.execute("DROP FUNCTION review_log_reject_update()")
    op.drop_table("review_state")
