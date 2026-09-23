"""Add opt-in surprise group bookings.

Revision ID: 20260922_0020
Revises: 20260922_0019
"""

from alembic import op
import sqlalchemy as sa


revision = "20260922_0020"
down_revision = "20260922_0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "musician_profiles",
        sa.Column("surprise_group_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index(
        "ix_musician_profiles_surprise_group_enabled",
        "musician_profiles",
        ["surprise_group_enabled"],
    )
    op.add_column(
        "bookings",
        sa.Column("booking_type", sa.String(length=20), nullable=False, server_default="normal"),
    )
    op.add_column("bookings", sa.Column("surprise_genre", sa.String(length=100), nullable=True))
    op.add_column("bookings", sa.Column("surprise_budget_cents", sa.Integer(), nullable=True))
    op.add_column("bookings", sa.Column("surprise_revealed_at", sa.DateTime(), nullable=True))
    op.create_index("ix_bookings_booking_type", "bookings", ["booking_type"])


def downgrade() -> None:
    op.drop_index("ix_bookings_booking_type", table_name="bookings")
    op.drop_column("bookings", "surprise_revealed_at")
    op.drop_column("bookings", "surprise_budget_cents")
    op.drop_column("bookings", "surprise_genre")
    op.drop_column("bookings", "booking_type")
    op.drop_index(
        "ix_musician_profiles_surprise_group_enabled",
        table_name="musician_profiles",
    )
    op.drop_column("musician_profiles", "surprise_group_enabled")
