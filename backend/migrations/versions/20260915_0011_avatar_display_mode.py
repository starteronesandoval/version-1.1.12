"""allow switching between uploaded photo and animated avatar

Revision ID: 20260915_0011
Revises: 20260914_0010
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260915_0011"
down_revision: Union[str, Sequence[str], None] = "20260914_0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "avatar_choices",
        sa.Column("mode", sa.String(12), nullable=False, server_default="photo"),
    )


def downgrade() -> None:
    op.drop_column("avatar_choices", "mode")
