"""Track when Stripe payment validation begins.

Revision ID: 20260922_0019
Revises: 20260921_0018
"""

from alembic import op
import sqlalchemy as sa


revision = "20260922_0019"
down_revision = "20260921_0018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "bookings",
        sa.Column("payment_validation_started_at", sa.DateTime(), nullable=True),
    )
    op.create_index(
        "ix_bookings_payment_validation_started_at",
        "bookings",
        ["payment_validation_started_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_bookings_payment_validation_started_at", table_name="bookings")
    op.drop_column("bookings", "payment_validation_started_at")
