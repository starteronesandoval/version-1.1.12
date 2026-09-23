"""Backfill geographic data for existing real musician profiles.

This migration never opts a group into Grupo Sorpresa.  It only derives a
base location from the profile's existing municipality/state when the catalog
can resolve it, and caps previously configured service radii at 30 km.
"""

from alembic import op
import sqlalchemy as sa

from app.geography import municipality_coordinates


revision = "20260923_0025"
down_revision = "20260923_0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    musicians = sa.table(
        "musician_profiles",
        sa.column("id", sa.Integer),
        sa.column("municipality", sa.String),
        sa.column("state", sa.String),
        sa.column("base_latitude", sa.Float),
        sa.column("base_longitude", sa.Float),
        sa.column("radio_servicio_sorpresa_km", sa.Integer),
    )
    rows = bind.execute(
        sa.select(
            musicians.c.id,
            musicians.c.municipality,
            musicians.c.state,
            musicians.c.base_latitude,
            musicians.c.base_longitude,
            musicians.c.radio_servicio_sorpresa_km,
        )
    ).mappings()
    for row in rows:
        updates: dict[str, object] = {}
        coordinates = municipality_coordinates(row["state"], row["municipality"])
        if coordinates and (
            row["base_latitude"] is None or row["base_longitude"] is None
        ):
            updates["base_latitude"], updates["base_longitude"] = coordinates
        if (
            row["radio_servicio_sorpresa_km"] is None
            or row["radio_servicio_sorpresa_km"] > 30
        ):
            updates["radio_servicio_sorpresa_km"] = 30
        if updates:
            bind.execute(
                musicians.update().where(musicians.c.id == row["id"]).values(**updates)
            )


def downgrade() -> None:
    # This is an intentional data backfill.  Original empty values cannot be
    # reconstructed safely, so schema state remains unchanged on downgrade.
    pass
