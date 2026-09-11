"""consolidate Stripe billing schema

Revision ID: 20260910_0003
Revises: 20260910_0002
"""

from datetime import time
from decimal import Decimal, ROUND_HALF_UP
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260910_0003"
down_revision: Union[str, Sequence[str], None] = "20260910_0002"
branch_labels = None
depends_on = None


def _names(inspector, table: str) -> set[str]:
    return {column["name"] for column in inspector.get_columns(table)}


def _indexes(inspector, table: str) -> set[str]:
    return {index["name"] for index in inspector.get_indexes(table)}


def _minutes(value) -> int:
    if isinstance(value, time):
        return value.hour * 60 + value.minute
    hours, minutes, *_ = str(value).split(":")
    return int(hours) * 60 + int(minutes)


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())

    if "billing_customers" not in tables:
        op.create_table(
            "billing_customers",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("stripe_customer_id", sa.String(255), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        )
        op.create_index(
            "ix_billing_customers_user_id", "billing_customers", ["user_id"],
            unique=True,
        )
        op.create_index(
            "ix_billing_customers_stripe_customer_id", "billing_customers",
            ["stripe_customer_id"], unique=True,
        )

    if "stripe_webhook_events" not in tables:
        op.create_table(
            "stripe_webhook_events",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("stripe_event_id", sa.String(255), nullable=False),
            sa.Column("event_type", sa.String(120), nullable=False),
            sa.Column("processed_at", sa.DateTime(), nullable=False),
        )
        op.create_index(
            "ix_stripe_webhook_events_stripe_event_id",
            "stripe_webhook_events", ["stripe_event_id"], unique=True,
        )

    booking_columns = _names(inspector, "bookings")
    additions = {
        "hourly_rate_cents": sa.Column(
            "hourly_rate_cents", sa.Integer(), nullable=False,
            server_default="0",
        ),
        "duration_minutes": sa.Column(
            "duration_minutes", sa.Integer(), nullable=False,
            server_default="0",
        ),
        "subtotal_cents": sa.Column(
            "subtotal_cents", sa.Integer(), nullable=False, server_default="0",
        ),
        "service_fee_cents": sa.Column(
            "service_fee_cents", sa.Integer(), nullable=False,
            server_default="0",
        ),
        "total_cents": sa.Column(
            "total_cents", sa.Integer(), nullable=False, server_default="0",
        ),
        "currency": sa.Column(
            "currency", sa.String(3), nullable=False, server_default="mxn",
        ),
        "payment_status": sa.Column(
            "payment_status", sa.String(30), nullable=False,
            server_default="pending",
        ),
        "stripe_checkout_session_id": sa.Column(
            "stripe_checkout_session_id", sa.String(255), nullable=True,
        ),
        "stripe_payment_intent_id": sa.Column(
            "stripe_payment_intent_id", sa.String(255), nullable=True,
        ),
    }
    for name, column in additions.items():
        if name not in booking_columns:
            op.add_column("bookings", column)

    inspector = sa.inspect(bind)
    indexes = _indexes(inspector, "bookings")
    for name, columns, unique in (
        ("ix_bookings_payment_status", ["payment_status"], False),
        ("ix_bookings_stripe_checkout_session_id", ["stripe_checkout_session_id"], True),
        ("ix_bookings_stripe_payment_intent_id", ["stripe_payment_intent_id"], True),
    ):
        if name not in indexes:
            op.create_index(name, "bookings", columns, unique=unique)

    rows = bind.execute(sa.text("""
        SELECT b.id, b.start_time, b.end_time, m.hourly_rate
        FROM bookings b
        JOIN musician_profiles m ON m.id = b.musician_id
        WHERE b.total_cents <= 0
    """)).mappings()
    for row in rows:
        duration = _minutes(row["end_time"]) - _minutes(row["start_time"])
        hourly = int(
            (Decimal(str(row["hourly_rate"])) * 100).quantize(
                Decimal("1"), rounding=ROUND_HALF_UP
            )
        )
        subtotal = int(
            (Decimal(hourly) * Decimal(duration) / Decimal(60)).quantize(
                Decimal("1"), rounding=ROUND_HALF_UP
            )
        )
        fee = int(
            (Decimal(subtotal) * Decimal("0.066")).quantize(
                Decimal("1"), rounding=ROUND_HALF_UP
            )
        )
        bind.execute(
            sa.text("""
                UPDATE bookings SET hourly_rate_cents=:hourly,
                    duration_minutes=:duration, subtotal_cents=:subtotal,
                    service_fee_cents=:fee, total_cents=:total,
                    currency='mxn'
                WHERE id=:id
            """),
            {"id": row["id"], "hourly": hourly, "duration": duration,
             "subtotal": subtotal, "fee": fee, "total": subtotal + fee},
        )


def downgrade() -> None:
    for name in (
        "ix_bookings_stripe_payment_intent_id",
        "ix_bookings_stripe_checkout_session_id",
        "ix_bookings_payment_status",
    ):
        op.drop_index(name, table_name="bookings")
    for column in (
        "stripe_payment_intent_id", "stripe_checkout_session_id",
        "payment_status", "currency", "total_cents", "service_fee_cents",
        "subtotal_cents", "duration_minutes", "hourly_rate_cents",
    ):
        op.drop_column("bookings", column)
    op.drop_table("stripe_webhook_events")
    op.drop_table("billing_customers")
