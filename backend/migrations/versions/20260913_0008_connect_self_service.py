"""add self-service Stripe Connect onboarding state

Revision ID: 20260913_0008
Revises: 20260913_0007
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "20260913_0008"
down_revision: Union[str, Sequence[str], None] = "20260913_0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("musician_payout_destinations") as batch:
        batch.alter_column("destination_type", nullable=True)
        batch.alter_column("encrypted_number", nullable=True)
        batch.alter_column("last4", nullable=True)
        batch.add_column(sa.Column(
            "stripe_details_submitted", sa.Boolean(), nullable=False,
            server_default=sa.false(),
        ))
        batch.add_column(sa.Column(
            "stripe_payouts_enabled", sa.Boolean(), nullable=False,
            server_default=sa.false(),
        ))
        batch.add_column(sa.Column(
            "stripe_requirements_due", sa.Text(), nullable=False, server_default="",
        ))
        batch.add_column(sa.Column(
            "last_stripe_payout_id", sa.String(255), nullable=True,
        ))
        batch.add_column(sa.Column(
            "last_stripe_payout_status", sa.String(30), nullable=True,
        ))
        batch.add_column(sa.Column(
            "last_stripe_payout_error", sa.Text(), nullable=True,
        ))


def downgrade() -> None:
    with op.batch_alter_table("musician_payout_destinations") as batch:
        for name in (
            "last_stripe_payout_error", "last_stripe_payout_status",
            "last_stripe_payout_id", "stripe_requirements_due",
            "stripe_payouts_enabled", "stripe_details_submitted",
        ):
            batch.drop_column(name)
        batch.alter_column("last4", nullable=False)
        batch.alter_column("encrypted_number", nullable=False)
        batch.alter_column("destination_type", nullable=False)
