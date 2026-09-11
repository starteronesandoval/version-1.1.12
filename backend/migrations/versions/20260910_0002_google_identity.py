"""add Google identity to users

Revision ID: 20260910_0002
Revises: 20260909_0001
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260910_0002"
down_revision: Union[str, Sequence[str], None] = "20260909_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users", sa.Column("google_subject", sa.String(length=255), nullable=True)
    )
    op.create_index(
        op.f("ix_users_google_subject"),
        "users",
        ["google_subject"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_users_google_subject"), table_name="users")
    op.drop_column("users", "google_subject")
