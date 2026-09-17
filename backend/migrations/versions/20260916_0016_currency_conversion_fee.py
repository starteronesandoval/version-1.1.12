"""Store the Stripe currency conversion surcharge on each booking.

Revision ID: 20260916_0016
Revises: 20260916_0015
"""

from alembic import op
import sqlalchemy as sa


revision = "20260916_0016"
down_revision = "20260916_0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "bookings",
        sa.Column("currency_conversion_fee_cents", sa.Integer(), nullable=False,
                  server_default="0"),
    )
    op.alter_column("bookings", "currency_conversion_fee_cents", server_default=None)


def downgrade() -> None:
    op.drop_column("bookings", "currency_conversion_fee_cents")
