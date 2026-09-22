"""Payment confirmation owns the date; unpaid requests never reserve it."""
import os
from datetime import date, time
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_calendar.db")
os.environ.setdefault("SECRET_KEY", "calendar-test-secret-with-at-least-32-characters")

import pytest
import stripe
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from app.auth import create_token
from app.billing import sync_checkout
from app.config import settings
from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import (User, UserRole, ClientProfile, MusicianProfile,
                        Booking, MusicianBusyDate)

client = TestClient(app)
EVENT_DATE = date(2099, 10, 19)


@pytest.fixture
def accounts():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        musician = User(email="calendar-band@example.com", password_hash="unused", role=UserRole.musician)
        customer = User(email="calendar-client@example.com", password_hash="unused", role=UserRole.client)
        db.add_all([musician, customer])
        db.flush()
        profile = MusicianProfile(user_id=musician.id, contact_name="Calendar", group_name="Calendar band",
                                  group_type="Banda", musical_style="Regional", member_count=5,
                                  hourly_rate=1000, equipment_brands="[]", description="Test")
        db.add_all([profile, ClientProfile(user_id=customer.id, name="Client", admin_phone="8111111111",
                                          city="Monterrey", municipality="Monterrey", state="Nuevo Leon")])
        db.commit()
        result = (profile.id, {"Authorization": f"Bearer {create_token(customer)}"},
                  {"Authorization": f"Bearer {create_token(musician)}"})
    yield result
    Base.metadata.drop_all(engine)


def request_booking(accounts):
    musician_id, headers, _ = accounts
    response = client.post("/api/bookings", headers=headers, json={
        "musician_id": musician_id, "event_date": EVENT_DATE.isoformat(), "venue": "Salon",
        "start_time": "18:00", "end_time": "21:00",
    })
    assert response.status_code == 201, response.text
    booking_id = response.json()["id"]
    with SessionLocal() as db:
        db.get(Booking, booking_id).stripe_checkout_session_id = f"cs_calendar_{booking_id}"
        db.commit()
    return booking_id


def event(booking_id, payment_status="paid"):
    return {"id": f"cs_calendar_{booking_id}", "metadata": {"booking_id": str(booking_id)},
            "payment_status": payment_status, "payment_intent": f"pi_calendar_{booking_id}"}


def available(accounts):
    result = client.get(f"/api/musicians/{accounts[0]}/availability?date={EVENT_DATE}", headers=accounts[1])
    assert result.status_code == 200
    return result.json()["available"]


def test_unpaid_requests_do_not_block_and_payment_validation_reserves_date(accounts):
    first = request_booking(accounts)
    second = request_booking(accounts)
    assert first != second and available(accounts)
    with SessionLocal() as db:
        sync_checkout("checkout.session.completed", event(first, "unpaid"), db)
        db.commit()
    assert not available(accounts)
    status = client.get(
        f"/api/billing/bookings/{first}/status", headers=accounts[1]
    )
    assert status.status_code == 200
    assert status.json()["payment_status"] == "validating_payment"
    # An unsigned request cannot confirm a date.
    with patch.object(settings, "stripe_webhook_secret", "whsec_calendar"):
        assert client.post("/api/billing/webhooks/stripe", json={"type": "checkout.session.completed",
                           "data": {"object": event(first)}}).status_code == 400
    assert not available(accounts)
    with SessionLocal() as db:
        sync_checkout("checkout.session.async_payment_succeeded", event(first), db)
        db.commit()
        sync_checkout("checkout.session.completed", event(first), db)
        sync_checkout("checkout.session.async_payment_failed", event(first), db)
        db.commit()
        assert db.get(Booking, first).payment_status == "paid"
        assert len(db.scalars(select(MusicianBusyDate)).all()) == 1
    assert not available(accounts)
    assert client.put(f"/api/musicians/me/busy-dates/{EVENT_DATE}", headers=accounts[2],
                      json={"busy": False}).status_code == 409
    with patch.object(settings, "stripe_secret_key", "sk_test_mock"), patch("app.billing.stripe.checkout.Session.create") as checkout:
        assert client.post("/api/billing/checkout-sessions", headers=accounts[1],
                           json={"booking_id": second}).status_code == 409
        checkout.assert_not_called()


@pytest.mark.parametrize("status", ["succeeded", "pending", "failed"])
def test_late_payment_refunds_without_double_booking(accounts, status):
    first, second = request_booking(accounts), request_booking(accounts)
    with SessionLocal() as db:
        sync_checkout("checkout.session.completed", event(first), db)
        db.commit()
    with patch.object(settings, "stripe_secret_key", "sk_test_mock"), patch(
        "app.billing.stripe.Refund.create", return_value=SimpleNamespace(id="re_conflict", status=status),
    ) as refund:
        with SessionLocal() as db:
            sync_checkout("checkout.session.completed", event(second), db)
            db.commit()
            sync_checkout("checkout.session.async_payment_succeeded", event(second), db)
            db.commit()
            assert db.get(Booking, first).payment_status == "paid"
            assert db.get(Booking, second).payment_status == {
                "succeeded": "refunded", "pending": "refund_pending", "failed": "refund_failed",
            }[status]
            assert db.get(Booking, second).payout_status == "date_conflict"
            assert len(db.scalars(select(MusicianBusyDate)).all()) == 1
        refund.assert_called_once()
        assert refund.call_args.kwargs["payment_intent"] == f"pi_calendar_{second}"
        assert "amount" not in refund.call_args.kwargs  # full refund


def test_manual_dates_preserved_but_unpaid_requests_can_be_released(accounts):
    booking_id = request_booking(accounts)
    assert client.put(f"/api/musicians/me/busy-dates/{EVENT_DATE}", headers=accounts[2],
                      json={"busy": True}).status_code == 200
    assert not available(accounts)
    assert client.put(f"/api/musicians/me/busy-dates/{EVENT_DATE}", headers=accounts[2],
                      json={"busy": False}).status_code == 200
    assert available(accounts)
    with SessionLocal() as db:
        assert db.get(Booking, booking_id).payment_status == "pending"


def test_refund_error_rolls_back_and_retries_with_same_key(accounts):
    first, second = request_booking(accounts), request_booking(accounts)
    with SessionLocal() as db:
        sync_checkout("checkout.session.completed", event(first), db)
        db.commit()
    with patch.object(settings, "stripe_secret_key", "sk_test_mock"), patch(
        "app.billing.stripe.Refund.create", side_effect=[stripe.error.APIConnectionError("offline"),
                                                        SimpleNamespace(status="succeeded")],
    ) as refund:
        with SessionLocal() as db:
            with pytest.raises(stripe.error.APIConnectionError):
                sync_checkout("checkout.session.completed", event(second), db)
            db.rollback()
            assert db.get(Booking, second).payment_status == "pending"
            sync_checkout("checkout.session.completed", event(second), db)
            db.commit()
            assert db.get(Booking, second).payment_status == "refunded"
        assert refund.call_args_list[0].kwargs == refund.call_args_list[1].kwargs


def test_database_rejects_two_paid_bookings_for_one_date(accounts):
    first, second = request_booking(accounts), request_booking(accounts)
    with SessionLocal() as db:
        db.get(Booking, first).payment_status = "paid"
        db.commit()
        db.get(Booking, second).payment_status = "paid"
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()


def test_refund_status_webhook_completes_pending_refund(accounts):
    first, second = request_booking(accounts), request_booking(accounts)
    with SessionLocal() as db:
        sync_checkout("checkout.session.completed", event(first), db)
        db.commit()
    with patch.object(settings, "stripe_secret_key", "sk_test_mock"), patch(
        "app.billing.stripe.Refund.create", return_value=SimpleNamespace(status="pending"),
    ):
        with SessionLocal() as db:
            sync_checkout("checkout.session.completed", event(second), db)
            db.commit()
    update = {"id": "evt_refund_update", "type": "refund.updated", "data": {"object": {
        "id": "re_calendar", "payment_intent": f"pi_calendar_{second}", "status": "succeeded",
    }}}
    with patch.object(settings, "stripe_webhook_secret", "whsec_mock"), patch(
        "app.billing.stripe.Webhook.construct_event", return_value=update,
    ):
        assert client.post("/api/billing/webhooks/stripe", content=b"signed").status_code == 200
    with SessionLocal() as db:
        assert db.get(Booking, second).payment_status == "refunded"
        assert db.get(Booking, first).payment_status == "paid"


def test_migration_frees_only_legacy_unpaid_dates():
    import importlib.util
    from pathlib import Path
    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import create_engine, MetaData, UniqueConstraint, text

    legacy = MetaData()
    for table in Base.metadata.sorted_tables:
        table.to_metadata(legacy)
    bookings = legacy.tables["bookings"]
    bookings.indexes.remove(next(i for i in bookings.indexes if i.name == "uq_bookings_paid_date"))
    bookings.append_constraint(UniqueConstraint("musician_id", "event_date"))
    scratch = create_engine("sqlite://")
    legacy.create_all(scratch)
    path = Path(__file__).parents[1] / "migrations/versions/20260918_0017_confirm_calendar_after_payment.py"
    spec = importlib.util.spec_from_file_location("calendar_migration", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with scratch.begin() as conn:
        # Core inserts apply model defaults; SQLite FK checking is off in this
        # isolated schema fixture, so no real customer records are needed.
        for day, status in [(1, "pending"), (2, "paid"), (4, "paid")]:
            conn.execute(bookings.insert().values(musician_id=1, client_id=1,
                         event_date=date(2099, 1, day), start_time=time(18), end_time=time(21),
                         venue="Test", payment_status=status))
        for day in [1, 2, 3]:
            conn.execute(legacy.tables["musician_busy_dates"].insert().values(
                musician_id=1, busy_date=date(2099, 1, day)))
        with Operations.context(MigrationContext.configure(conn)):
            migration.upgrade()
        dates = conn.execute(text("SELECT busy_date FROM musician_busy_dates ORDER BY busy_date")).scalars().all()
        assert dates == ["2099-01-02", "2099-01-03", "2099-01-04"]
        # Duplicate unpaid requests are allowed after migration.
        conn.execute(bookings.insert().values(musician_id=1, client_id=1,
                     event_date=date(2099, 1, 1), start_time=time(18), end_time=time(21), venue="Test"))
        with pytest.raises(IntegrityError):
            conn.execute(bookings.insert().values(musician_id=1, client_id=1,
                         event_date=date(2099, 1, 2), start_time=time(18), end_time=time(21),
                         venue="Test", payment_status="paid"))
    scratch.dispose()


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="PostgreSQL locking")
def test_simultaneous_payments_only_confirm_one_date(accounts):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    first, second = request_booking(accounts), request_booking(accounts)
    barrier = Barrier(2)

    def confirm(booking_id):
        with SessionLocal() as db:
            barrier.wait(timeout=10)
            sync_checkout("checkout.session.completed", event(booking_id), db)
            db.commit()

    with patch.object(settings, "stripe_secret_key", "sk_test_mock"), patch(
        "app.billing.stripe.Refund.create", return_value=SimpleNamespace(status="succeeded"),
    ) as refund:
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(confirm, [first, second]))
        refund.assert_called_once()
    with SessionLocal() as db:
        assert sorted(db.get(Booking, i).payment_status for i in [first, second]) == ["paid", "refunded"]
        assert len(db.scalars(select(MusicianBusyDate)).all()) == 1


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="PostgreSQL migration")
def test_postgres_migration_preserves_paid_and_manual_dates(accounts):
    import importlib.util
    from pathlib import Path
    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import text
    booking_id = request_booking(accounts)
    with SessionLocal() as db:
        db.add(MusicianBusyDate(musician_id=accounts[0], busy_date=EVENT_DATE))
        db.add(MusicianBusyDate(musician_id=accounts[0], busy_date=date(2099, 10, 20)))
        db.commit()
    path = Path(__file__).parents[1] / "migrations/versions/20260918_0017_confirm_calendar_after_payment.py"
    spec = importlib.util.spec_from_file_location("pg_calendar_migration", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with engine.begin() as conn:
        conn.execute(text("DROP INDEX uq_bookings_paid_date"))
        conn.execute(text("ALTER TABLE bookings ADD CONSTRAINT bookings_musician_id_event_date_key UNIQUE (musician_id, event_date)"))
        with Operations.context(MigrationContext.configure(conn)):
            migration.upgrade()
    assert available(accounts)
    assert request_booking(accounts) != booking_id
    with SessionLocal() as db:
        assert list(db.scalars(select(MusicianBusyDate.busy_date))) == [date(2099, 10, 20)]
