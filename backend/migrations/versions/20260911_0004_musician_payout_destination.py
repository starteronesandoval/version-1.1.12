"""add encrypted musician payout destination

Revision ID: 20260911_0004
Revises: 20260910_0003
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260911_0004"
down_revision: Union[str, Sequence[str], None] = "20260910_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "musician_payout_destinations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("musician_id", sa.Integer(), nullable=False),
        sa.Column("destination_type", sa.String(20), nullable=False),
        sa.Column("encrypted_number", sa.Text(), nullable=False),
        sa.Column("last4", sa.String(4), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["musician_id"], ["musician_profiles.id"]),
    )
    op.create_index(
        "ix_musician_payout_destinations_musician_id",
        "musician_payout_destinations", ["musician_id"], unique=True,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_musician_payout_destinations_musician_id",
        table_name="musician_payout_destinations",
    )
    op.drop_table("musician_payout_destinations")
