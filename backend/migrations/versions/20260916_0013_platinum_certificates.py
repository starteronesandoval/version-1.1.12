"""Administrator-issued platinum certificates and audit history."""
from alembic import op
import sqlalchemy as sa

revision = "20260916_0013"
down_revision = "20260916_0012"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("platinum_certificates",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("musician_id", sa.Integer(), sa.ForeignKey("musician_profiles.id"), nullable=False, unique=True),
        sa.Column("certificate_code", sa.String(60), nullable=False, unique=True),
        sa.Column("group_name_snapshot", sa.String(180), nullable=False),
        sa.Column("recommendation", sa.Text(), nullable=False),
        sa.Column("verification_method", sa.String(30), nullable=False),
        sa.Column("verified_on", sa.Date(), nullable=False),
        sa.Column("issued_at", sa.DateTime(), nullable=False),
        sa.Column("issued_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("revocation_reason", sa.Text(), nullable=True))
    op.create_table("platinum_audit",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("musician_id", sa.Integer(), sa.ForeignKey("musician_profiles.id"), nullable=False),
        sa.Column("admin_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("action", sa.String(20), nullable=False),
        sa.Column("certificate_code", sa.String(60), nullable=False),
        sa.Column("details", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False))
    op.create_index("ix_platinum_audit_musician_id", "platinum_audit", ["musician_id"])


def downgrade():
    op.drop_table("platinum_audit")
    op.drop_table("platinum_certificates")
