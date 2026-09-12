"""add Stripe Connect transfer references

Revision ID: 20260911_0006
Revises: 20260911_0005
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "20260911_0006"
down_revision: Union[str, Sequence[str], None] = "20260911_0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("musician_payout_destinations", sa.Column(
        "stripe_connected_account_id", sa.String(255), nullable=True))
    op.create_index(
        "ix_musician_payout_destinations_stripe_connected_account_id",
        "musician_payout_destinations", ["stripe_connected_account_id"],
        unique=True,
    )
    op.add_column("bookings", sa.Column(
        "stripe_transfer_id", sa.String(255), nullable=True))
    op.add_column("bookings", sa.Column("payout_error", sa.Text(), nullable=True))
    op.create_index("ix_bookings_stripe_transfer_id", "bookings",
                    ["stripe_transfer_id"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_bookings_stripe_transfer_id", table_name="bookings")
    op.drop_column("bookings", "payout_error")
    op.drop_column("bookings", "stripe_transfer_id")
    op.drop_index(
        "ix_musician_payout_destinations_stripe_connected_account_id",
        table_name="musician_payout_destinations",
    )
    op.drop_column("musician_payout_destinations",
                   "stripe_connected_account_id")
