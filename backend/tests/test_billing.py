import hashlib
import hmac
import json
import os
import time as clock
from datetime import date, time
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_billing.db")
os.environ.setdefault("UPLOAD_DIR", "test_uploads")
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault(
    "SECRET_KEY", "test-only-secret-key-with-at-least-32-characters"
)

from fastapi.testclient import TestClient

from app.auth import create_token
from app.config import settings
from app.database import Base, SessionLocal, engine
from app.main import app, booking_price_snapshot
from app.models import Booking, ClientProfile, MusicianProfile, User, UserRole

client = TestClient(app)


def setup_module():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def teardown_module():
    Base.metadata.drop_all(engine)
    engine.dispose()
    Path("test_billing.db").unlink(missing_ok=True)


def create_booking_fixture() -> tuple[dict[str, str], int]:
    with SessionLocal() as db:
        client_user = User(email="billing@example.com", password_hash="unused", role=UserRole.client)
        musician_user = User(email="group@example.com", password_hash="unused", role=UserRole.musician)
        db.add_all([client_user, musician_user])
        db.flush()
        client_profile = ClientProfile(
            user_id=client_user.id, name="Cliente", admin_phone="8111111111",
            city="Monterrey", municipality="Monterrey", state="Nuevo León",
        )
        musician = MusicianProfile(
            user_id=musician_user.id, contact_name="Ana", group_name="Grupo Balam",
            group_type="Banda", musical_style="Regional", member_count=5,
            hourly_rate=1000, equipment_brands="[]", description="Grupo de prueba",
        )
        db.add_all([client_profile, musician])
        db.flush()
        booking = Booking(
            musician_id=musician.id, client_id=client_profile.id,
            event_date=date(2099, 1, 1), venue="Salón",
            start_time=time(18, 0), end_time=time(21, 0),
            **booking_price_snapshot(1000, time(18, 0), time(21, 0)),
        )
        db.add(booking)
        db.commit()
        db.refresh(booking)
        return {"Authorization": f"Bearer {create_token(client_user)}"}, booking.id


def test_price_snapshot_multiplies_hours_then_adds_6_6_percent():
    price = booking_price_snapshot(1000, time(18, 0), time(21, 0))
    assert price == {
        "hourly_rate_cents": 100000,
        "duration_minutes": 180,
        "subtotal_cents": 300000,
        "service_fee_cents": 19800,
        "total_cents": 319800,
        "currency": "mxn",
        "payment_status": "pending",
    }


def test_checkout_charges_frozen_booking_total():
    headers, booking_id = create_booking_fixture()
    original_key = settings.stripe_secret_key
    settings.stripe_secret_key = "test-placeholder"
    try:
        with patch("app.billing.stripe.Customer.create") as customer_create, patch(
            "app.billing.stripe.checkout.Session.create"
        ) as checkout_create:
            customer_create.return_value = SimpleNamespace(id="cus_test")
            checkout_create.return_value = SimpleNamespace(id="cs_test", url="https://checkout.test")
            response = client.post(
                "/api/billing/checkout-sessions", headers=headers,
                json={"booking_id": booking_id},
            )
        assert response.status_code == 201
        kwargs = checkout_create.call_args.kwargs
        assert kwargs["line_items"][0]["price_data"]["unit_amount"] == 319800
        assert kwargs["mode"] == "payment"
        assert kwargs["invoice_creation"] == {"enabled": True}
        with SessionLocal() as db:
            booking = db.get(Booking, booking_id)
            assert booking.payment_status == "checkout_created"
            assert booking.stripe_checkout_session_id == "cs_test"
    finally:
        settings.stripe_secret_key = original_key


def test_signed_webhook_accepts_stripe_object_payload():
    original_secret = settings.stripe_webhook_secret
    settings.stripe_webhook_secret = "whsec_test"
    try:
        timestamp = int(clock.time())
        payload = json.dumps({
            "id": "evt_signed_test",
            "type": "checkout.session.completed",
            "data": {"object": {"metadata": {}}},
        }, separators=(",", ":"))
        signature = hmac.new(
            settings.stripe_webhook_secret.encode(),
            f"{timestamp}.{payload}".encode(),
            hashlib.sha256,
        ).hexdigest()
        response = client.post(
            "/api/billing/webhooks/stripe",
            content=payload,
            headers={"stripe-signature": f"t={timestamp},v1={signature}"},
        )
        assert response.status_code == 200
        assert response.json() == {"received": True}
    finally:
        settings.stripe_webhook_secret = original_secret
