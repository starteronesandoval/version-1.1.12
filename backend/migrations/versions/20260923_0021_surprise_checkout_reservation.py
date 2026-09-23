"""Reserve a surprise group while its checkout is active.

Revision ID: 20260923_0021
Revises: 20260922_0020
"""

from alembic import op
import sqlalchemy as sa


revision = "20260923_0021"
down_revision = "20260922_0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    predicate = (
        "booking_type = 'surprise' AND payment_status IN "
        "('checkout_created', 'validating_payment', 'paid')"
    )
    op.create_index(
        "uq_surprise_bookings_reserved_date",
        "bookings",
        ["musician_id", "event_date"],
        unique=True,
        postgresql_where=sa.text(predicate),
        sqlite_where=sa.text(predicate),
    )


def downgrade() -> None:
    op.drop_index("uq_surprise_bookings_reserved_date", table_name="bookings")
