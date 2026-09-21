"""Add locality and low-season prices to group and booking records.

Revision ID: 20260921_0018
Revises: 20260918_0017
"""

from alembic import op
import sqlalchemy as sa

revision = "20260921_0018"
down_revision = "20260918_0017"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("musician_profiles", sa.Column("local_hourly_rate", sa.Numeric(12, 2), nullable=True))
    op.add_column("musician_profiles", sa.Column("low_season_hourly_rate", sa.Numeric(12, 2), nullable=True))
    op.add_column("musician_profiles", sa.Column("low_season_dates", sa.Text(), nullable=False, server_default="[]"))
    op.add_column("bookings", sa.Column("price_type", sa.String(20), nullable=False, server_default="normal"))
    # SQLite does not support ALTER COLUMN ... DROP DEFAULT.
    if op.get_bind().dialect.name != "sqlite":
        op.alter_column("musician_profiles", "low_season_dates", server_default=None)
        op.alter_column("bookings", "price_type", server_default=None)


def downgrade():
    op.drop_column("bookings", "price_type")
    op.drop_column("musician_profiles", "low_season_dates")
    op.drop_column("musician_profiles", "low_season_hourly_rate")
    op.drop_column("musician_profiles", "local_hourly_rate")
