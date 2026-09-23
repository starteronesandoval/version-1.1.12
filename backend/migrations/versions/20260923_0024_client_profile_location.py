"""Store the internally resolved approximate location of client profiles."""

from alembic import op
import sqlalchemy as sa


revision = "20260923_0024"
down_revision = "20260923_0023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("client_profiles", sa.Column("location_latitude", sa.Float(), nullable=True))
    op.add_column("client_profiles", sa.Column("location_longitude", sa.Float(), nullable=True))


def downgrade() -> None:
    op.drop_column("client_profiles", "location_longitude")
    op.drop_column("client_profiles", "location_latitude")
