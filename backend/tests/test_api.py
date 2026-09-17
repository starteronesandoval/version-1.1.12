import os
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

os.environ["DATABASE_URL"] = "sqlite:///./test_balam.db"
os.environ["UPLOAD_DIR"] = "test_uploads"
os.environ["APP_ENV"] = "test"
os.environ["SECRET_KEY"] = "test-only-secret-key-with-at-least-32-characters"
os.environ["EXPOSE_PASSWORD_RESET_CODE"] = "true"

from fastapi.testclient import TestClient
from app.database import Base, engine
from app.main import app
from app.config import settings

client = TestClient(app)


def setup_module():
    Base.metadata.drop_all(engine); Base.metadata.create_all(engine)


def teardown_module():
    Base.metadata.drop_all(engine)
    engine.dispose()
    Path("test_balam.db").unlink(missing_ok=True)


def test_login_rate_limit_is_bound_to_the_account():
    registered = client.post("/api/auth/register", json={
        "email": "rate-limit@example.com",
        "password": "segura123",
        "role": "client",
    })
    assert registered.status_code == 201
    previous_limit = settings.auth_rate_limit_per_minute
    settings.auth_rate_limit_per_minute = 2
    try:
        payload = {
            "identifier": "rate-limit@example.com",
            "password": "incorrecta",
        }
        assert client.post("/api/auth/login", json=payload).status_code == 401
        assert client.post("/api/auth/login", json=payload).status_code == 401
        assert client.post("/api/auth/login", json=payload).status_code == 429
    finally:
        settings.auth_rate_limit_per_minute = previous_limit


def test_full_registration_and_search_flow():
    musician = client.post("/api/auth/register", json={"email":"musico@example.com","password":"segura123","role":"musician"})
    assert musician.status_code == 201
    mh = {"Authorization": f"Bearer {musician.json()['access_token']}"}
    rules = client.get("/api/musicians/me/rules", headers=mh)
    assert rules.status_code == 200
    assert rules.json()["accepted"] is False
    assert rules.json()["rules_version"] == "GARIBALDY_GROUP_RULES_V1"
    accepted_rules = client.post("/api/musicians/me/rules/accept", headers=mh)
    assert accepted_rules.status_code == 200
    assert accepted_rules.json()["accepted"] is True
    assert accepted_rules.json()["accepted_at"] is not None
    profile = client.put("/api/musicians/me", headers=mh, json={
        "contact_name":"Ana López","admin_phone":"8111111111","city":"Monterrey","municipality":"Monterrey","state":"Nuevo León","group_name":"Los del Valle","group_type":"Norteño",
        "musical_style":"Norteño tradicional","member_count":5,"hourly_rate":3500,
        "minimum_booking_hours":3,
        "includes_sound":True,"subwoofer_count":2,"mid_speaker_count":4,
        "equipment_brands":["JBL","QSC"],"audience_capacity":500,"description":"Música para eventos"
    })
    assert profile.status_code == 200
    accepted_reference = client.get("/api/musicians/me/rules", headers=mh).json()
    assert accepted_reference["accepted_group_name"] == "Los del Valle"
    choice = client.put("/api/users/me/avatar-preset", headers=mh,
        json={"preset":"jaguar_accordion","color":"#20C9B5"})
    assert choice.status_code == 200
    restored = client.get("/api/musicians/me", headers=mh)
    assert restored.status_code == 200
    assert restored.json()["equipment_brands"] == ["JBL", "QSC"]
    assert restored.json()["minimum_booking_hours"] == 3
    assert restored.json()["avatar_preset"] == "jaguar_accordion"
    assert restored.json()["avatar_mode"] == "preset"
    busy = client.put(
        "/api/musicians/me/busy-dates/2099-10-18",
        headers=mh,
        json={"busy": True},
    )
    assert busy.status_code == 200 and busy.json()["busy"] is True
    agenda = client.get("/api/musicians/me/busy-dates", headers=mh)
    assert agenda.status_code == 200
    assert agenda.json() == [{"date": "2099-10-18", "busy": True}]
    found = client.get("/api/musicians?q=Valle")
    assert found.status_code == 200 and found.json()[0]["group_name"] == "Los del Valle"
    assert found.json()[0]["hourly_rate"] == 3823.47
    assert found.json()[0]["avatar_color"] == "#20C9B5"
    assert "busy_dates" not in found.json()[0]
    customer = client.post("/api/auth/register", json={"email":"cliente@example.com","password":"segura123","role":"client"})
    ch = {"Authorization": f"Bearer {customer.json()['access_token']}"}
    result = client.put("/api/clients/me", headers=ch, json={"name":"Luis","admin_phone":"8122222222","city":"Guadalupe","municipality":"Guadalupe","state":"Nuevo León","musical_tastes":["Norteño"],"favorite_groups":["Intocable"]})
    assert result.status_code == 200 and result.json()["musical_tastes"] == ["Norteño"]
    restored_client = client.get("/api/clients/me", headers=ch)
    assert restored_client.status_code == 200
    assert restored_client.json()["favorite_groups"] == ["Intocable"]
    unavailable = client.get(
        f"/api/musicians/{profile.json()['id']}/availability?date=2099-10-18",
        headers=ch,
    )
    assert unavailable.status_code == 200
    assert unavailable.json()["available"] is False
    assert unavailable.json()["message"] == "Lo sentimos, el grupo ya tiene compromiso ese día."
    available = client.get(
        f"/api/musicians/{profile.json()['id']}/availability?date=2099-10-19",
        headers=ch,
    )
    assert available.status_code == 200 and available.json()["available"] is True
    too_short = client.post(
        "/api/bookings",
        headers=ch,
        json={
            "musician_id": profile.json()["id"],
            "event_date": "2099-10-19",
            "venue": "Salón Balam, Monterrey",
            "start_time": "18:30",
            "end_time": "20:30",
        },
    )
    assert too_short.status_code == 422
    assert "a partir de 3 horas" in too_short.json()["detail"]
    booking = client.post(
        "/api/bookings",
        headers=ch,
        json={
            "musician_id": profile.json()["id"],
            "event_date": "2099-10-19",
            "venue": "Salón Balam, Monterrey",
            "start_time": "18:30",
            "end_time": "23:45",
        },
    )
    assert booking.status_code == 201
    assert booking.json()["venue"] == "Salón Balam, Monterrey"
    assert booking.json()["client_name"] == "Luis"
    sold_date = client.get(
        f"/api/musicians/{profile.json()['id']}/availability?date=2099-10-19",
        headers=ch,
    )
    assert sold_date.status_code == 200
    assert sold_date.json()["available"] is False
    musician_notifications = client.get("/api/musicians/me/bookings", headers=mh)
    assert musician_notifications.status_code == 200
    assert musician_notifications.json()[0]["event_date"] == "2099-10-19"
    assert musician_notifications.json()[0]["start_time"] == "18:30:00"
    assert musician_notifications.json()[0]["is_new_sale"] is True
    client_bookings = client.get("/api/clients/me/bookings", headers=ch)
    assert client_bookings.status_code == 200
    booking_id = booking.json()["id"]
    locked_chat = client.get(f"/api/bookings/{booking_id}/messages", headers=ch)
    assert locked_chat.status_code == 403
    assert "se activará durante el evento" in locked_chat.json()["detail"]
    with patch(
        "app.main.booking_chat_state",
        return_value=(True, "Chat activo durante el horario del evento."),
    ):
        song_request = client.post(
            f"/api/bookings/{booking_id}/messages",
            headers=ch,
            json={"text": "¿Pueden tocar El Rey a las 21:00?"},
        )
        assert song_request.status_code == 201
        assert song_request.json()["mine"] is True
        musician_chat = client.get(
            f"/api/bookings/{booking_id}/messages", headers=mh
        )
        assert musician_chat.status_code == 200
        assert musician_chat.json()[0]["mine"] is False
        assert musician_chat.json()[0]["sender_name"] == "Luis"
        reply = client.post(
            f"/api/bookings/{booking_id}/messages",
            headers=mh,
            json={"text": "Sí, la agregamos al repertorio."},
        )
        assert reply.status_code == 201
        full_chat = client.get(f"/api/bookings/{booking_id}/messages", headers=ch)
        assert len(full_chat.json()) == 2
        assert full_chat.json()[1]["sender_name"] == "Los del Valle"
    stranger = client.post("/api/auth/register", json={
        "email": "otro@example.com", "password": "segura123", "role": "client"
    })
    stranger_headers = {"Authorization": f"Bearer {stranger.json()['access_token']}"}
    forbidden = client.get(
        f"/api/bookings/{booking_id}/messages", headers=stranger_headers
    )
    assert forbidden.status_code == 403
    with patch(
        "app.main.booking_chat_state",
        return_value=(True, "Chat activo durante el horario del evento."),
    ):
        invite = client.post(
            f"/api/bookings/{booking_id}/chat-invite", headers=ch
        )
        assert invite.status_code == 200
        assert invite.json()["qr_value"].startswith("GARIBALDI_EVENT:")
        musician_invite = client.post(
            f"/api/bookings/{booking_id}/chat-invite", headers=mh
        )
        assert musician_invite.status_code == 200
        assert musician_invite.json()["qr_value"].startswith("GARIBALDI_EVENT:")
        invite_token = invite.json()["token"]
        guest_access = client.get(
            f"/api/event-chat/{invite_token}", headers=stranger_headers
        )
        assert guest_access.status_code == 200
        guest_request = client.post(
            f"/api/event-chat/{invite_token}/messages",
            headers=stranger_headers,
            json={"text": "¿Pueden tocar una cumbia?"},
        )
        assert guest_request.status_code == 201
        assert guest_request.json()["sender_name"] == "otro"
    closed_guest_chat = client.get(
        f"/api/event-chat/{invite_token}/messages", headers=stranger_headers
    )
    assert closed_guest_chat.status_code == 403
    early_review = client.post(
        f"/api/bookings/{booking_id}/review", headers=ch,
        json={
            "agreed_duration": 5, "punctuality": 4.5, "uniform": 4,
            "atmosphere": 5, "kindness": 5, "song_requests": 4.5,
            "would_hire_again": 5, "recommendation": "Sigan así, gran ambiente.",
        },
    )
    assert early_review.status_code == 403
    stranger_review = client.post(
        f"/api/bookings/{booking_id}/review", headers=stranger_headers,
        json={
            "agreed_duration": 5, "punctuality": 5, "uniform": 5,
            "atmosphere": 5, "kindness": 5, "song_requests": 5,
            "would_hire_again": 5, "recommendation": "Excelente grupo.",
        },
    )
    assert stranger_review.status_code == 403
    from app.database import SessionLocal
    from app.models import Booking
    with SessionLocal() as db:
        stored_booking = db.get(Booking, booking_id)
        # Keep the event unambiguously in the past across UTC/local-date boundaries.
        stored_booking.event_date = date.today() - timedelta(days=2)
        stored_booking.payment_status = "paid"
        stored_booking.payout_status = "musician_funds_held"
        db.commit()
    review = client.post(
        f"/api/bookings/{booking_id}/review", headers=ch,
        json={
            "agreed_duration": 5, "punctuality": 4.5, "uniform": 4,
            "atmosphere": 5, "kindness": 5, "song_requests": 4.5,
            "would_hire_again": 5, "recommendation": "Sigan así, gran ambiente.",
        },
    )
    assert review.status_code == 201
    assert review.json()["overall_score"] == 4.77
    with SessionLocal() as db:
        assert db.get(Booking, booking_id).payout_status == "musician_funds_held"
    released = client.post(
        f"/api/bookings/{booking_id}/release", headers=ch, json={}
    )
    assert released.status_code == 200
    assert released.json()["payout_status"] == "pending_connect_account"
    assert client.post(
        f"/api/bookings/{booking_id}/review", headers=ch,
        json={
            "agreed_duration": 5, "punctuality": 5, "uniform": 5,
            "atmosphere": 5, "kindness": 5, "song_requests": 5,
            "would_hire_again": 5, "recommendation": "Otra reseña.",
        },
    ).status_code == 409
    reviewed_booking = client.get("/api/clients/me/bookings", headers=ch).json()[0]
    assert reviewed_booking["can_review"] is False
    assert reviewed_booking["review_score"] == 4.77
    assert reviewed_booking["review_recommendation"] is None
    private_review = client.get(f"/api/bookings/{booking_id}/review", headers=mh)
    assert private_review.status_code == 200
    assert private_review.json()["recommendation"] == "Sigan así, gran ambiente."
    assert client.get(
        f"/api/bookings/{booking_id}/review", headers=ch
    ).status_code == 403
    musician_contract = client.get("/api/musicians/me/bookings", headers=mh).json()[0]
    assert musician_contract["review_recommendation"] == "Sigan así, gran ambiente."
    with SessionLocal() as db:
        stored_booking = db.get(Booking, booking_id)
        stored_booking.created_at = (
            datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(hours=25)
        )
        db.commit()
    archived_contract = client.get("/api/musicians/me/bookings", headers=mh).json()[0]
    assert archived_contract["is_new_sale"] is False
    public_group = client.get("/api/musicians?q=Valle").json()[0]
    assert public_group["rating"] == 4.77 and public_group["review_count"] == 1
    with SessionLocal() as db:
        stored_booking = db.get(Booking, booking_id)
        stored_booking.event_date = date(2099, 10, 19)
        db.commit()
    cannot_release = client.put(
        "/api/musicians/me/busy-dates/2099-10-19",
        headers=mh,
        json={"busy": False},
    )
    assert cannot_release.status_code == 409
    avatar = client.post("/api/clients/me/avatar", headers=ch,
        files={"file": ("avatar.jpg", b"\xff\xd8\xfffake-image", "image/jpeg")})
    assert avatar.status_code == 201
    client_with_photo = client.get("/api/clients/me", headers=ch).json()
    assert client_with_photo["avatar_url"].startswith("/uploads/clients/")
    assert client_with_photo["avatar_mode"] == "photo"
    selected_avatar = client.put(
        "/api/users/me/avatar-preset",
        headers=ch,
        json={"preset": "jaguar_dj", "color": "#0EA5E9"},
    )
    assert selected_avatar.status_code == 200
    assert selected_avatar.json()["mode"] == "preset"
    switched = client.get("/api/clients/me", headers=ch).json()
    assert switched["avatar_url"].startswith("/uploads/clients/")
    assert switched["avatar_mode"] == "preset"


def test_login_flow_and_invalid_credentials():
    registered = client.post("/api/auth/register", json={
        "email": "login@example.com", "password": "segura123", "role": "client"
    })
    assert registered.status_code == 201
    logged_in = client.post("/api/auth/login", json={
        "email": "LOGIN@example.com", "password": "segura123"
    })
    assert logged_in.status_code == 200
    headers = {"Authorization": f"Bearer {logged_in.json()['access_token']}"}
    me = client.get("/api/users/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["email"] == "login@example.com"
    assert me.json()["role"] == "client"

    invalid = client.post("/api/auth/login", json={
        "email": "login@example.com", "password": "incorrecta"
    })
    assert invalid.status_code == 401
    assert invalid.json()["detail"] == "Correo, celular o contraseña incorrectos"


def test_google_registration_login_and_email_collision():
    google_claims = {
        "sub": "google-user-123",
        "email": "google@example.com",
        "email_verified": True,
    }
    with patch("app.main.verify_google_token", return_value=google_claims):
        registered = client.post("/api/auth/google", json={
            "id_token": "x" * 100,
            "create_account": True,
            "role": "client",
        })
        assert registered.status_code == 200
        headers = {
            "Authorization": f"Bearer {registered.json()['access_token']}"
        }
        me = client.get("/api/users/me", headers=headers)
        assert me.status_code == 200
        assert me.json()["email"] == "google@example.com"
        assert me.json()["role"] == "client"

        changed_role = client.post("/api/auth/google", json={
            "id_token": "y" * 100,
            "create_account": True,
            "role": "musician",
        })
        assert changed_role.status_code == 200
        changed_headers = {
            "Authorization": f"Bearer {changed_role.json()['access_token']}"
        }
        changed_me = client.get("/api/users/me", headers=changed_headers)
        assert changed_me.json()["role"] == "musician"

        logged_in = client.post("/api/auth/google", json={
            "id_token": "y" * 100,
            "create_account": False,
        })
        assert logged_in.status_code == 200

    local = client.post("/api/auth/register", json={
        "email": "local@example.com",
        "password": "segura123",
        "role": "client",
    })
    assert local.status_code == 201
    collision_claims = {
        "sub": "different-google-user",
        "email": "local@example.com",
        "email_verified": True,
    }
    with patch("app.main.verify_google_token", return_value=collision_claims):
        collision = client.post("/api/auth/google", json={
            "id_token": "z" * 100,
            "create_account": True,
            "role": "client",
        })
    assert collision.status_code == 409


def test_login_with_damaged_password_hash_returns_unauthorized():
    from sqlalchemy import select
    from app.database import SessionLocal
    from app.models import User

    registered = client.post("/api/auth/register", json={
        "email": "damaged@example.com", "password": "segura123", "role": "client"
    })
    assert registered.status_code == 201
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.email == "damaged@example.com"))
        user.password_hash = "not-a-valid-password-hash"
        db.commit()

    response = client.post("/api/auth/login", json={
        "email": "damaged@example.com", "password": "segura123"
    })
    assert response.status_code == 401


def test_phone_registration_is_not_available():
    registered = client.post("/api/auth/register", json={
        "phone": "81 1234 5678",
        "password": "claveInicial123",
        "role": "client",
    })
    assert registered.status_code == 422


def test_email_password_reset():
    registered = client.post("/api/auth/register", json={
        "email": "recuperacion@example.com",
        "password": "claveInicial123",
        "role": "client",
    })
    assert registered.status_code == 201
    old_headers = {
        "Authorization": f"Bearer {registered.json()['access_token']}"
    }
    requested = client.post("/api/auth/password-reset/request", json={
        "email": "recuperacion@example.com",
    })
    assert requested.status_code == 200
    code = requested.json()["dev_code"]
    assert len(code) == 6
    changed = client.post("/api/auth/password-reset/confirm", json={
        "email": "recuperacion@example.com",
        "code": code,
        "new_password": "claveNueva123",
    })
    assert changed.status_code == 200
    assert client.get("/api/users/me", headers=old_headers).status_code == 401
    assert client.post("/api/auth/login", json={
        "identifier": "recuperacion@example.com", "password": "claveNueva123",
    }).status_code == 200
    assert client.post("/api/auth/password-reset/confirm", json={
        "email": "recuperacion@example.com",
        "code": code,
        "new_password": "noDebeCambiar123",
    }).status_code == 400


def test_musician_cannot_create_profile_without_accepting_rules():
    registered = client.post("/api/auth/register", json={
        "email": "reglas@example.com",
        "password": "segura123",
        "role": "musician",
    })
    headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
    response = client.put("/api/musicians/me", headers=headers, json={
        "contact_name": "Grupo Reglas",
        "admin_phone": "8133333333",
        "city": "Ameca",
        "municipality": "Ameca",
        "state": "Jalisco",
        "group_name": "Grupo sin aceptar",
        "group_type": "Banda",
        "musical_style": "Regional",
        "member_count": 5,
        "hourly_rate": 3000,
        "equipment_brands": [],
        "description": "Perfil bloqueado hasta aceptar las reglas.",
    })
    assert response.status_code == 403
    assert "Reglas para Agrupaciones" in response.json()["detail"]


def test_admin_panel_and_contract_messaging():
    from app.auth import hash_password
    from app.database import SessionLocal
    from app.models import User, UserRole

    with SessionLocal() as db:
        admin = User(
            email="admin@garibaldy.local",
            password_hash=hash_password("AdminSegura123"),
            role=UserRole.admin,
        )
        db.add(admin)
        db.commit()
    login = client.post("/api/auth/login", json={
        "identifier": "admin@garibaldy.local",
        "password": "AdminSegura123",
    })
    assert login.status_code == 200
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    admin_me = client.get("/api/users/me", headers=headers)
    assert admin_me.status_code == 200
    assert admin_me.json()["role"] == "admin"
    assert client.get("/api/admin/clients", headers=headers).status_code == 200
    assert client.get("/api/admin/groups", headers=headers).status_code == 200
    contracts = client.get("/api/admin/bookings", headers=headers)
    assert contracts.status_code == 200
    booking_id = contracts.json()[0]["id"]
    message = client.post(
        f"/api/bookings/{booking_id}/messages",
        headers=headers,
        json={"text": "Mensaje de seguimiento administrativo."},
    )
    assert message.status_code == 201
    assert message.json()["sender_role"] == "admin"
    assert message.json()["sender_name"] == "Administración Garibaldy"
    public_admin = client.post("/api/auth/register", json={
        "email": "intruso@example.com",
        "password": "segura123",
        "role": "admin",
    })
    assert public_admin.status_code == 403


def test_security_headers_and_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["referrer-policy"] == "no-referrer"


def test_password_reset_code_is_not_returned_when_delivery_is_configured():
    from app.config import settings

    registered = client.post("/api/auth/register", json={
        "email": "reset-privado@example.com",
        "password": "segura123",
        "role": "client",
    })
    assert registered.status_code == 201
    with (
        patch.object(settings, "expose_password_reset_code", False),
        patch("app.main.deliver_password_reset_code") as deliver,
    ):
        response = client.post("/api/auth/password-reset/request", json={
            "email": "reset-privado@example.com",
        })
    assert response.status_code == 200
    assert "dev_code" not in response.json()
    deliver.assert_called_once()
