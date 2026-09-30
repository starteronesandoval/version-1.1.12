"""Store event addresses and distance-compensation pricing snapshots."""

from alembic import op
import sqlalchemy as sa


revision = "20260930_0028"
down_revision = "20260926_0027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    for name in (
        "distance_compensation_local", "distance_compensation_medium",
        "distance_compensation_medium_high", "distance_compensation_high",
        "distance_compensation_long",
    ):
        op.add_column("musician_profiles", sa.Column(name, sa.Numeric(12, 2), nullable=False, server_default="0"))
    columns = (
        ("event_city", sa.String(120)), ("event_municipality", sa.String(120)),
        ("event_state", sa.String(120)), ("event_street", sa.String(180)),
        ("event_number", sa.String(40)), ("haversine_distance_km", sa.Float()),
        ("corrected_distance_km", sa.Float()), ("distance_zone", sa.String(30)),
        ("distance_compensation_cents", sa.Integer()), ("base_price_cents", sa.Integer()),
    )
    for name, kind in columns:
        op.add_column("bookings", sa.Column(name, kind, nullable=True, server_default="0" if name.endswith("_cents") else None))


def downgrade() -> None:
    for name in ("base_price_cents", "distance_compensation_cents", "distance_zone", "corrected_distance_km", "haversine_distance_km", "event_number", "event_street", "event_state", "event_municipality", "event_city"):
        op.drop_column("bookings", name)
    for name in ("distance_compensation_long", "distance_compensation_high", "distance_compensation_medium_high", "distance_compensation_medium", "distance_compensation_local"):
        op.drop_column("musician_profiles", name)
