"""Keep unpaid requests available; only paid bookings reserve a date."""
from alembic import op
import sqlalchemy as sa

revision = "20260918_0017"
down_revision = "20260916_0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    constraints = sa.inspect(bind).get_unique_constraints("bookings")
    # Old code created these calendar blocks in the same transaction as the
    # unpaid booking. Preserve manual dates (no booking) and every paid date.
    op.execute(sa.text("""
        DELETE FROM musician_busy_dates
        WHERE EXISTS (
            SELECT 1 FROM bookings b
            WHERE b.musician_id = musician_busy_dates.musician_id
              AND b.event_date = musician_busy_dates.busy_date
              AND b.payment_status <> 'paid'
        ) AND NOT EXISTS (
            SELECT 1 FROM bookings b
            WHERE b.musician_id = musician_busy_dates.musician_id
              AND b.event_date = musician_busy_dates.busy_date
              AND b.payment_status = 'paid'
        )
    """))
    # Restore a missing busy row for any historical paid booking.
    op.execute(sa.text("""
        INSERT INTO musician_busy_dates (musician_id, busy_date)
        SELECT b.musician_id, b.event_date FROM bookings b
        WHERE b.payment_status = 'paid' AND NOT EXISTS (
            SELECT 1 FROM musician_busy_dates d
            WHERE d.musician_id = b.musician_id AND d.busy_date = b.event_date
        )
    """))
    convention = {"uq": "uq_%(table_name)s_%(column_0_name)s_%(column_1_name)s"}
    with op.batch_alter_table("bookings", naming_convention=convention) as batch:
        for constraint in constraints:
            if set(constraint["column_names"]) == {"musician_id", "event_date"}:
                batch.drop_constraint(
                    constraint["name"] or "uq_bookings_musician_id_event_date",
                    type_="unique",
                )
    op.create_index(
        "uq_bookings_paid_date", "bookings", ["musician_id", "event_date"],
        unique=True, postgresql_where=sa.text("payment_status = 'paid'"),
        sqlite_where=sa.text("payment_status = 'paid'"),
    )


def downgrade() -> None:
    # Refuse destructive rollback when multiple requests now share a date.
    duplicates = op.get_bind().execute(sa.text(
        "SELECT 1 FROM bookings GROUP BY musician_id, event_date HAVING COUNT(*) > 1"
    )).first()
    if duplicates:
        raise RuntimeError("Cannot restore old uniqueness with multiple booking requests")
    op.drop_index("uq_bookings_paid_date", table_name="bookings")
    with op.batch_alter_table("bookings") as batch:
        batch.create_unique_constraint(
            "uq_bookings_musician_id_event_date", ["musician_id", "event_date"],
        )
