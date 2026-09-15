"""add customizable music theme to musician cards

Revision ID: 20260914_0010
Revises: 20260913_0009
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260914_0010"
down_revision: Union[str, Sequence[str], None] = "20260913_0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "musician_profiles",
        sa.Column(
            "card_theme", sa.String(30), nullable=False,
            server_default="classic",
        ),
    )


def downgrade() -> None:
    op.drop_column("musician_profiles", "card_theme")
