"""Set the default Surprise Group service radius to 30 km.

Existing profiles keep their explicitly configured radius.  This only changes
the database default applied to newly created musician profiles.
"""

from alembic import op
import sqlalchemy as sa


revision = "20260923_0023"
down_revision = "20260923_0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # SQLite cannot alter a column default in place.  The ORM default already
    # applies to its new rows, while PostgreSQL receives the server default.
    if op.get_bind().dialect.name == "sqlite":
        return
    op.alter_column(
        "musician_profiles",
        "radio_servicio_sorpresa_km",
        existing_type=sa.Integer(),
        server_default="30",
        existing_nullable=False,
    )


def downgrade() -> None:
    if op.get_bind().dialect.name == "sqlite":
        return
    op.alter_column(
        "musician_profiles",
        "radio_servicio_sorpresa_km",
        existing_type=sa.Integer(),
        server_default="40",
        existing_nullable=False,
    )
