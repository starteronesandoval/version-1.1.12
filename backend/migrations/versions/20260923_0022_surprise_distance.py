"""Add geographic matching data for surprise bookings.

Revision ID: 20260923_0022
Revises: 20260923_0021
"""

from alembic import op
import sqlalchemy as sa


revision = "20260923_0022"
down_revision = "20260923_0021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("musician_profiles", sa.Column("base_latitude", sa.Float(), nullable=True))
    op.add_column("musician_profiles", sa.Column("base_longitude", sa.Float(), nullable=True))
    op.add_column(
        "musician_profiles",
        sa.Column("radio_servicio_sorpresa_km", sa.Integer(), nullable=False, server_default="30"),
    )
    op.add_column("bookings", sa.Column("event_latitude", sa.Float(), nullable=True))
    op.add_column("bookings", sa.Column("event_longitude", sa.Float(), nullable=True))
    op.add_column("bookings", sa.Column("surprise_distance_km", sa.Float(), nullable=True))


def downgrade() -> None:
    op.drop_column("bookings", "surprise_distance_km")
    op.drop_column("bookings", "event_longitude")
    op.drop_column("bookings", "event_latitude")
    op.drop_column("musician_profiles", "radio_servicio_sorpresa_km")
    op.drop_column("musician_profiles", "base_longitude")
    op.drop_column("musician_profiles", "base_latitude")
