"""Client Ajua reactions and group inbox."""
from alembic import op
import sqlalchemy as sa

revision = "20260916_0012"
down_revision = "20260915_0011"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("media_ajuas",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("media_id", sa.Integer(), sa.ForeignKey("media.id", ondelete="CASCADE"), nullable=False),
        sa.Column("client_id", sa.Integer(), sa.ForeignKey("client_profiles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("read", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("media_id", "client_id"))
    op.create_index("ix_media_ajuas_media_id", "media_ajuas", ["media_id"])
    op.create_index("ix_media_ajuas_client_id", "media_ajuas", ["client_id"])
    op.create_table("media_shares",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("media_id", sa.Integer(), sa.ForeignKey("media.id", ondelete="CASCADE"), nullable=False),
        sa.Column("client_id", sa.Integer(), sa.ForeignKey("client_profiles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("media_id", "client_id"))
    op.create_index("ix_media_shares_media_id", "media_shares", ["media_id"])
    op.create_index("ix_media_shares_client_id", "media_shares", ["client_id"])


def downgrade():
    op.drop_table("media_shares")
    op.drop_table("media_ajuas")
