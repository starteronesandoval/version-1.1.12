"""Do not reserve a musician date until Stripe confirms payment."""

from alembic import op


revision = "20260926_0027"
down_revision = "20260924_0026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_index("uq_surprise_bookings_reserved_date", table_name="bookings")


def downgrade() -> None:
    op.create_index(
        "uq_surprise_bookings_reserved_date",
        "bookings",
        ["musician_id", "event_date"],
        unique=True,
        postgresql_where=(
            "booking_type = 'surprise' AND payment_status IN "
            "('checkout_created', 'validating_payment', 'paid')"
        ),
        sqlite_where=(
            "booking_type = 'surprise' AND payment_status IN "
            "('checkout_created', 'validating_payment', 'paid')"
        ),
    )
