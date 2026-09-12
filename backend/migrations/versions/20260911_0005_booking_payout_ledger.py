"""add booking payout ledger and dispute state

Revision ID: 20260911_0005
Revises: 20260911_0004
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260911_0005"
down_revision: Union[str, Sequence[str], None] = "20260911_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    additions = (
        sa.Column("musician_earnings_cents", sa.Integer(), nullable=False,
                  server_default="0"),
        sa.Column("platform_fee_cents", sa.Integer(), nullable=False,
                  server_default="0"),
        sa.Column("stripe_fee_estimate_cents", sa.Integer(), nullable=False,
                  server_default="0"),
        sa.Column("payout_status", sa.String(40), nullable=False,
                  server_default="awaiting_payment"),
        sa.Column("dispute_reason", sa.Text(), nullable=True),
        sa.Column("dispute_opened_at", sa.DateTime(), nullable=True),
        sa.Column("approved_for_payout_at", sa.DateTime(), nullable=True),
        sa.Column("paid_out_at", sa.DateTime(), nullable=True),
    )
    for column in additions:
        op.add_column("bookings", column)
    op.create_index("ix_bookings_payout_status", "bookings",
                    ["payout_status"], unique=False)
    bind = op.get_bind()
    bind.execute(sa.text("""
        UPDATE bookings SET
          musician_earnings_cents = CAST(subtotal_cents * 0.97 + 0.5 AS INTEGER),
          platform_fee_cents =
            subtotal_cents - CAST(subtotal_cents * 0.97 + 0.5 AS INTEGER)
            + CAST(subtotal_cents * 0.03 + 0.5 AS INTEGER),
          stripe_fee_estimate_cents = service_fee_cents
            - CAST(subtotal_cents * 0.03 + 0.5 AS INTEGER),
          payout_status = CASE
            WHEN payment_status = 'paid' THEN 'musician_funds_held'
            ELSE 'awaiting_payment'
          END
    """))
    bind.execute(sa.text("""
        UPDATE bookings SET payout_status = 'approved_for_payout'
        WHERE id IN (SELECT booking_id FROM booking_reviews)
          AND payment_status = 'paid'
    """))


def downgrade() -> None:
    op.drop_index("ix_bookings_payout_status", table_name="bookings")
    for name in (
        "paid_out_at", "approved_for_payout_at", "dispute_opened_at",
        "dispute_reason", "payout_status", "stripe_fee_estimate_cents",
        "platform_fee_cents", "musician_earnings_cents",
    ):
        op.drop_column("bookings", name)
