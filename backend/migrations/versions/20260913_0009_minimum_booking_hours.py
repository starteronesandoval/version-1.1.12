"""add minimum booking hours to musician profiles

Revision ID: 20260913_0009
Revises: 20260913_0008
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "20260913_0009"
down_revision: Union[str, Sequence[str], None] = "20260913_0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "musician_profiles",
        sa.Column(
            "minimum_booking_hours", sa.Integer(), nullable=False,
            server_default="2",
        ),
    )


def downgrade() -> None:
    op.drop_column("musician_profiles", "minimum_booking_hours")
