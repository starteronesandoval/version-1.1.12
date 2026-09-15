import hashlib
import hmac
import json
import os
import time as clock
import stripe
from datetime import date, datetime, time, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

from sqlalchemy import select

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
from app.billing import release_due_payouts, release_musician_funds
from app.main import app, booking_price_snapshot
from app.models import (Booking, ClientProfile, MusicianPayoutDestination,
                        MusicianProfile, User, UserRole)

client = TestClient(app)


def setup_module():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def teardown_module():
    Base.metadata.drop_all(engine)
    engine.dispose()
    Path("test_billing.db").unlink(missing_ok=True)


def create_booking_fixture(suffix: str = "") -> tuple[dict[str, str], int]:
    with SessionLocal() as db:
        client_user = User(email=f"billing{suffix}@example.com", password_hash="unused", role=UserRole.client)
        musician_user = User(email=f"group{suffix}@example.com", password_hash="unused", role=UserRole.musician)
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


def test_price_snapshot_multiplies_hours_then_adds_7_1_percent():
    price = booking_price_snapshot(1000, time(18, 0), time(21, 0))
    assert price == {
        "hourly_rate_cents": 100000,
        "duration_minutes": 180,
        "subtotal_cents": 300000,
        "service_fee_cents": 21300,
        "total_cents": 321300,
        "musician_earnings_cents": 291000,
        "platform_fee_cents": 18000,
        "stripe_fee_estimate_cents": 12300,
        "currency": "mxn",
        "payment_status": "pending",
        "payout_status": "awaiting_payment",
    }


def test_ten_thousand_peso_distribution_snapshot():
    price = booking_price_snapshot(10000, time(18, 0), time(19, 0))

    assert price["subtotal_cents"] == 1_000_000
    assert price["total_cents"] == 1_071_000
    assert price["platform_fee_cents"] == 60_000
    assert price["stripe_fee_estimate_cents"] == 41_000
    assert price["musician_earnings_cents"] == 970_000
    assert (
        price["platform_fee_cents"]
        + price["stripe_fee_estimate_cents"]
        + price["musician_earnings_cents"]
        == price["total_cents"]
    )


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
        assert kwargs["line_items"][0]["price_data"]["unit_amount"] == 321300
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


def test_approved_release_creates_idempotent_connect_transfer():
    _, booking_id = create_booking_fixture("-release")
    with SessionLocal() as db:
        booking = db.get(Booking, booking_id)
        booking.payment_status = "paid"
        booking.payout_status = "approved_for_payout"
        booking.stripe_payment_intent_id = "pi_release_test"
        db.add(MusicianPayoutDestination(
            musician_id=booking.musician_id,
            destination_type="clabe",
            encrypted_number="encrypted-test-value",
            last4="9719",
            stripe_connected_account_id="acct_release_test",
            stripe_payouts_enabled=True,
        ))
        db.commit()
        original_key = settings.stripe_secret_key
        settings.stripe_secret_key = "sk_test_placeholder"
        try:
            with patch("app.billing.stripe.PaymentIntent.retrieve") as retrieve, \
                    patch("app.billing.stripe.Transfer.create") as transfer:
                retrieve.return_value = SimpleNamespace(latest_charge="ch_release_test")
                transfer.return_value = SimpleNamespace(id="tr_release_test")
                assert release_musician_funds(booking_id, db) is True
                kwargs = transfer.call_args.kwargs
                assert kwargs["amount"] == booking.musician_earnings_cents
                assert kwargs["destination"] == "acct_release_test"
                assert kwargs["source_transaction"] == "ch_release_test"
                assert kwargs["idempotency_key"] == (
                    f"balam-booking-{booking_id}-musician-v1"
                )
            saved = db.get(Booking, booking_id)
            assert saved.payout_status == "transferred"
            assert saved.stripe_transfer_id == "tr_release_test"
        finally:
            settings.stripe_secret_key = original_key


def test_auto_release_waits_two_hours_then_transfers_exactly_once():
    _, booking_id = create_booking_fixture("-auto-release")
    event_timezone = ZoneInfo(settings.event_timezone)
    event_day = date(2035, 5, 20)
    deadline = datetime(2035, 5, 20, 23, 0, tzinfo=event_timezone)
    with SessionLocal() as db:
        booking = db.get(Booking, booking_id)
        booking.event_date = event_day
        booking.end_time = time(21, 0)
        booking.payment_status = "paid"
        booking.payout_status = "musician_funds_held"
        booking.stripe_payment_intent_id = "pi_auto_release"
        db.add(MusicianPayoutDestination(
            musician_id=booking.musician_id,
            destination_type="clabe",
            encrypted_number="encrypted-auto-release",
            last4="9719",
            stripe_connected_account_id="acct_auto_release",
            stripe_payouts_enabled=True,
        ))
        db.commit()

        assert release_due_payouts(
            db, now=deadline - timedelta(seconds=1)
        ) == 0
        assert db.get(Booking, booking_id).payout_status == "musician_funds_held"

        original_key = settings.stripe_secret_key
        settings.stripe_secret_key = "sk_test_auto_release"
        try:
            with patch(
                "app.billing.stripe.PaymentIntent.retrieve",
                return_value=SimpleNamespace(latest_charge="ch_auto_release"),
            ), patch(
                "app.billing.stripe.Transfer.create",
                return_value=SimpleNamespace(id="tr_auto_release"),
            ) as transfer:
                assert release_due_payouts(db, now=deadline) == 1
                assert release_due_payouts(
                    db, now=deadline + timedelta(minutes=5)
                ) == 0
            transfer.assert_called_once()
            assert transfer.call_args.kwargs["destination"] == "acct_auto_release"
            saved = db.get(Booking, booking_id)
            assert saved.payout_status == "transferred"
            assert saved.stripe_transfer_id == "tr_auto_release"
            assert saved.approved_for_payout_at is not None
        finally:
            settings.stripe_secret_key = original_key


def test_dispute_is_rejected_after_two_hour_window():
    headers, booking_id = create_booking_fixture("-late-dispute")
    with SessionLocal() as db:
        booking = db.get(Booking, booking_id)
        booking.event_date = date.today() - timedelta(days=1)
        booking.payment_status = "paid"
        booking.payout_status = "musician_funds_held"
        db.commit()

    response = client.post(
        f"/api/bookings/{booking_id}/dispute",
        headers=headers,
        json={"reason": "El servicio no se completó como se acordó."},
    )
    assert response.status_code == 409
    assert "plazo de 2 horas" in response.json()["detail"]
    with SessionLocal() as db:
        assert db.get(Booking, booking_id).payout_status == "musician_funds_held"


def test_money_flow_from_stripe_webhook_to_group_connect_account():
    client_headers, booking_id = create_booking_fixture("-money-flow")
    with SessionLocal() as db:
        booking = db.get(Booking, booking_id)
        booking.event_date = date.today() - timedelta(days=1)
        booking.stripe_checkout_session_id = "cs_money_flow"
        musician = db.get(MusicianProfile, booking.musician_id)
        musician_user = db.get(User, musician.user_id)
        admin_user = User(
            email="money-flow-admin@example.com",
            password_hash="unused",
            role=UserRole.admin,
        )
        db.add(admin_user)
        db.commit()
        musician_headers = {
            "Authorization": f"Bearer {create_token(musician_user)}"
        }
        admin_headers = {
            "Authorization": f"Bearer {create_token(admin_user)}"
        }
        musician_id = musician.id
        expected_earnings = booking.musician_earnings_cents

    original_webhook_secret = settings.stripe_webhook_secret
    original_stripe_key = settings.stripe_secret_key
    settings.stripe_webhook_secret = "whsec_money_flow"
    settings.stripe_secret_key = "sk_test_money_flow"
    try:
        paid_event = {
            "id": "evt_money_flow_paid",
            "type": "checkout.session.completed",
            "data": {"object": {
                "id": "cs_money_flow",
                "metadata": {"booking_id": str(booking_id)},
                "payment_status": "paid",
                "payment_intent": "pi_money_flow",
            }},
        }
        with patch(
            "app.billing.stripe.Webhook.construct_event",
            return_value=paid_event,
        ):
            webhook = client.post(
                "/api/billing/webhooks/stripe",
                content=b"signed-stripe-payload",
                headers={"stripe-signature": "test-signature"},
            )
        assert webhook.status_code == 200
        with SessionLocal() as db:
            paid_booking = db.get(Booking, booking_id)
            assert paid_booking.payment_status == "paid"
            assert paid_booking.payout_status == "musician_funds_held"
            assert paid_booking.stripe_payment_intent_id == "pi_money_flow"

        created_account = SimpleNamespace(
            id="acct_moneyflowgroup",
            to_dict_recursive=lambda: {
                "id": "acct_moneyflowgroup", "country": "MX",
                "details_submitted": False, "payouts_enabled": False,
                "metadata": {"balam_musician_id": str(musician_id)},
                "requirements": {"currently_due": ["external_account"]},
            },
        )
        with patch("app.billing.stripe.Account.create", return_value=created_account), \
                patch(
                    "app.billing.stripe.AccountLink.create",
                    return_value=SimpleNamespace(
                        url="https://connect.stripe.test/onboard", expires_at=12345,
                    ),
                ):
            onboarding = client.post(
                "/api/billing/connect/onboarding", headers=musician_headers, json={},
            )
        assert onboarding.status_code == 201
        assert onboarding.json()["url"] == "https://connect.stripe.test/onboard"

        account_ready_event = {
            "id": "evt_money_flow_account_ready", "type": "account.updated",
            "data": {"object": {
                "id": "acct_moneyflowgroup", "country": "MX",
                "details_submitted": True, "payouts_enabled": True,
                "metadata": {"balam_musician_id": str(musician_id)},
                "requirements": {"currently_due": [], "past_due": []},
            }},
        }
        with patch(
            "app.billing.stripe.Webhook.construct_event",
            return_value=account_ready_event,
        ):
            connected = client.post(
                "/api/billing/webhooks/stripe", content=b"signed-account-event",
                headers={"stripe-signature": "test-signature"},
            )
        assert connected.status_code == 200
        status = client.get(
            "/api/musicians/me/payout-destination", headers=musician_headers,
        )
        assert status.json()["stripe_connect_ready"] is True
        assert status.json()["onboarding_status"] == "ready"

        with patch(
            "app.billing.stripe.PaymentIntent.retrieve",
            return_value=SimpleNamespace(latest_charge="ch_money_flow"),
        ) as retrieve, patch(
            "app.billing.stripe.Transfer.create",
            return_value=SimpleNamespace(id="tr_money_flow"),
        ) as transfer:
            review = client.post(
                f"/api/bookings/{booking_id}/review",
                headers=client_headers,
                json={
                    "agreed_duration": 5,
                    "punctuality": 5,
                    "uniform": 5,
                    "atmosphere": 5,
                    "kindness": 5,
                    "song_requests": 5,
                    "would_hire_again": 5,
                    "recommendation": "Servicio completo y pago autorizado.",
                },
            )
            with SessionLocal() as db:
                assert db.get(Booking, booking_id).payout_status == (
                    "musician_funds_held"
                )
            released = client.post(
                f"/api/bookings/{booking_id}/release",
                headers=client_headers,
                json={},
            )
        assert review.status_code == 201
        assert released.status_code == 200
        assert released.json()["payout_status"] == "transferred"
        retrieve.assert_called_once_with("pi_money_flow")
        transfer.assert_called_once()
        transfer_args = transfer.call_args.kwargs
        assert transfer_args["amount"] == expected_earnings
        assert transfer_args["currency"] == "mxn"
        assert transfer_args["destination"] == "acct_moneyflowgroup"
        assert transfer_args["source_transaction"] == "ch_money_flow"
        assert transfer_args["transfer_group"] == f"balam_booking_{booking_id}"
        assert transfer_args["idempotency_key"] == (
            f"balam-booking-{booking_id}-musician-v1"
        )

        with SessionLocal() as db:
            transferred = db.get(Booking, booking_id)
            assert transferred.payout_status == "transferred"
            assert transferred.stripe_transfer_id == "tr_money_flow"
            assert transferred.paid_out_at is None
            assert transferred.payout_error is None
    finally:
        settings.stripe_webhook_secret = original_webhook_secret
        settings.stripe_secret_key = original_stripe_key


def test_connect_onboarding_is_available_before_first_paid_contract():
    with SessionLocal() as db:
        client_user = User(
            email="payout-client@example.com", password_hash="unused",
            role=UserRole.client,
        )
        musician_user = User(
            email="payout-group@example.com", password_hash="unused",
            role=UserRole.musician,
        )
        db.add_all([client_user, musician_user])
        db.flush()
        client_profile = ClientProfile(
            user_id=client_user.id, name="Cliente pago",
            admin_phone="8111111111", city="Monterrey",
            municipality="Monterrey", state="Nuevo León",
        )
        musician = MusicianProfile(
            user_id=musician_user.id, contact_name="Grupo pago",
            group_name="Grupo destino", group_type="Banda",
            musical_style="Regional", member_count=5, hourly_rate=1000,
            equipment_brands="[]", description="Grupo de prueba",
        )
        db.add_all([client_profile, musician])
        db.flush()
        booking = Booking(
            musician_id=musician.id, client_id=client_profile.id,
            event_date=date(2099, 2, 1), venue="Salón",
            start_time=time(18, 0), end_time=time(21, 0),
            **booking_price_snapshot(1000, time(18, 0), time(21, 0)),
        )
        db.add(booking)
        db.commit()
        musician_headers = {
            "Authorization": f"Bearer {create_token(musician_user)}"
        }
        payout_client_headers = {
            "Authorization": f"Bearer {create_token(client_user)}"
        }
        booking_id = booking.id
        musician_id = musician.id

    locked = client.get(
        "/api/musicians/me/payout-destination", headers=musician_headers,
    )
    assert locked.status_code == 200
    assert locked.json()["eligible"] is True
    assert locked.json()["configured"] is False
    assert locked.json()["onboarding_status"] == "not_started"
    assert client.put(
        "/api/musicians/me/payout-destination", headers=musician_headers,
        json={"destination_type": "clabe",
              "account_number": "032180000118359719"},
    ).status_code == 410

    created_account = SimpleNamespace(
        id="acct_early_setup",
        to_dict_recursive=lambda: {
            "id": "acct_early_setup", "details_submitted": False,
            "payouts_enabled": False,
            "metadata": {"balam_musician_id": str(musician_id)},
            "requirements": {"currently_due": ["external_account"]},
        },
    )
    with patch("app.billing.stripe.Account.create", return_value=created_account), \
            patch(
                "app.billing.stripe.AccountLink.create",
                return_value=SimpleNamespace(url="https://connect.test/setup", expires_at=1),
            ):
        saved = client.post(
            "/api/billing/connect/onboarding", headers=musician_headers, json={},
        )
    assert saved.status_code == 201
    with patch(
        "app.billing.stripe.Account.retrieve",
        side_effect=stripe.error.APIConnectionError("Stripe sin conexión"),
    ):
        unavailable = client.post(
            "/api/billing/connect/onboarding", headers=musician_headers, json={},
        )
    assert unavailable.status_code == 502
    assert unavailable.json()["detail"].startswith(
        "No fue posible comunicarse con Stripe"
    )
    with patch(
        "app.billing.stripe.Account.retrieve",
        side_effect=stripe.error.InvalidRequestError(
            "You can only create new accounts if you've signed up for Connect",
            param=None,
        ),
    ):
        connect_disabled = client.post(
            "/api/billing/connect/onboarding", headers=musician_headers, json={},
        )
    assert connect_disabled.status_code == 502
    assert connect_disabled.json()["detail"].startswith("Activa Stripe Connect")
    with SessionLocal() as db:
        destination = db.scalar(select(MusicianPayoutDestination).where(
            MusicianPayoutDestination.musician_id == musician_id
        ))
        assert destination.encrypted_number is None
        assert destination.stripe_connected_account_id == "acct_early_setup"
        recently_finished = datetime.now(
            ZoneInfo(settings.event_timezone)
        ) - timedelta(hours=1)
        db.get(Booking, booking_id).event_date = recently_finished.date()
        db.get(Booking, booking_id).end_time = recently_finished.time().replace(
            tzinfo=None, microsecond=0
        )
        db.get(Booking, booking_id).payment_status = "paid"
        db.get(Booking, booking_id).payout_status = "musician_funds_held"
        db.commit()
    disputed = client.post(
        f"/api/bookings/{booking_id}/dispute",
        headers=payout_client_headers,
        json={"reason": "La agrupación no terminó el tiempo contratado."},
    )
    assert disputed.status_code == 200
    assert disputed.json()["payout_status"] == "disputed"


def test_connected_account_payout_webhooks_update_bank_deposit_status():
    _, booking_id = create_booking_fixture("-bank-payout")
    with SessionLocal() as db:
        booking = db.get(Booking, booking_id)
        destination = MusicianPayoutDestination(
            musician_id=booking.musician_id,
            stripe_connected_account_id="acct_bank_payout",
            stripe_details_submitted=True,
            stripe_payouts_enabled=True,
        )
        db.add(destination)
        db.commit()
        destination_id = destination.id

    original_secret = settings.stripe_webhook_secret
    settings.stripe_webhook_secret = "whsec_bank_payout"
    try:
        failed_event = {
            "id": "evt_bank_payout_failed", "type": "payout.failed",
            "account": "acct_bank_payout",
            "data": {"object": {
                "id": "po_bank_payout", "failure_code": "account_closed",
            }},
        }
        with patch(
            "app.billing.stripe.Webhook.construct_event", return_value=failed_event,
        ):
            response = client.post(
                "/api/billing/webhooks/stripe", content=b"signed-payout-failed",
                headers={"stripe-signature": "test-signature"},
            )
        assert response.status_code == 200
        with SessionLocal() as db:
            destination = db.get(MusicianPayoutDestination, destination_id)
            assert destination.last_stripe_payout_status == "failed"
            assert destination.last_stripe_payout_error == "account_closed"

        paid_event = {
            "id": "evt_bank_payout_paid", "type": "payout.paid",
            "account": "acct_bank_payout",
            "data": {"object": {"id": "po_bank_payout"}},
        }
        with patch(
            "app.billing.stripe.Webhook.construct_event", return_value=paid_event,
        ):
            response = client.post(
                "/api/billing/webhooks/stripe", content=b"signed-payout-paid",
                headers={"stripe-signature": "test-signature"},
            )
        assert response.status_code == 200
        with SessionLocal() as db:
            destination = db.get(MusicianPayoutDestination, destination_id)
            assert destination.last_stripe_payout_status == "paid"
            assert destination.last_stripe_payout_error is None
    finally:
        settings.stripe_webhook_secret = original_secret
