"""Musician requests for manual platinum certification."""
from alembic import op
import sqlalchemy as sa

revision = "20260916_0014"
down_revision = "20260916_0013"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("platinum_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("musician_id", sa.Integer(), sa.ForeignKey("musician_profiles.id"), unique=True, nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("response", sa.Text(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(), nullable=False),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.Column("reviewed_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True))
    op.create_index("ix_platinum_requests_status", "platinum_requests", ["status"])


def downgrade():
    op.drop_table("platinum_requests")
