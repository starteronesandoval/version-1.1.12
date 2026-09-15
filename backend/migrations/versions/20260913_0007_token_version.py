"""add token version for session revocation

Revision ID: 20260913_0007
Revises: 20260911_0006
"""

from alembic import op
import sqlalchemy as sa


revision = "20260913_0007"
down_revision = "20260911_0006"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "users",
        sa.Column("token_version", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade():
    op.drop_column("users", "token_version")
