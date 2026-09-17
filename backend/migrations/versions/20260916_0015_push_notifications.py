"""Durable in-app notices and device push deliveries."""
from alembic import op
import sqlalchemy as sa

revision = "20260916_0015"
down_revision = "20260916_0014"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("push_devices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("installation_id", sa.String(100), unique=True, nullable=False),
        sa.Column("token", sa.String(512), unique=True, nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False))
    op.create_index("ix_push_devices_user_id", "push_devices", ["user_id"])
    op.create_table("user_notifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("event_key", sa.String(160), nullable=False),
        sa.Column("kind", sa.String(40), nullable=False),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("body", sa.String(250), nullable=False),
        sa.Column("data_json", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("read_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("user_id", "event_key"))
    op.create_index("ix_user_notifications_user_id", "user_notifications", ["user_id"])
    op.create_table("push_deliveries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("notification_id", sa.Integer(), sa.ForeignKey("user_notifications.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_id", sa.Integer(), sa.ForeignKey("push_devices.id", ondelete="CASCADE"), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(), nullable=False),
        sa.Column("delivered_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("notification_id", "device_id"))
    op.create_index("ix_push_deliveries_notification_id", "push_deliveries", ["notification_id"])
    op.create_index("ix_push_deliveries_device_id", "push_deliveries", ["device_id"])


def downgrade():
    op.drop_table("push_deliveries")
    op.drop_table("user_notifications")
    op.drop_table("push_devices")
