import os
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_notifications.db")
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("UPLOAD_DIR", "test_uploads")
os.environ.setdefault("SECRET_KEY", "test-only-secret-key-with-at-least-32-characters")

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.auth import create_token
from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import PushDelivery, User, UserNotification, UserRole, ClientProfile, MusicianProfile
from app.notifications import enqueue

client = TestClient(app)


def setup_function():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def test_inbox_is_private_and_duplicate_event_is_not_resent():
    with SessionLocal() as db:
        users = [User(email=f"push{i}@example.com", password_hash="unused",
                      role=UserRole.musician) for i in range(2)]
        db.add_all(users)
        db.commit()
        headers = [{"Authorization": f"Bearer {create_token(u)}"} for u in users]
        user_id = users[0].id
    device = {"installation_id": "a" * 32, "token": "x" * 100}
    assert client.put("/api/notifications/devices", headers=headers[0], json=device).status_code == 200
    with SessionLocal() as db:
        enqueue(db, user_id=user_id, event_key="booking:42", kind="booking",
                title="Nueva contratación", body="Tienes un contrato", data={"booking_id": "42"})
        enqueue(db, user_id=user_id, event_key="booking:42", kind="booking",
                title="Nueva contratación", body="Tienes un contrato")
        db.commit()
        assert len(db.scalars(select(UserNotification)).all()) == 1
        assert len(db.scalars(select(PushDelivery)).all()) == 1
    notice = client.get("/api/notifications", headers=headers[0]).json()[0]
    assert notice["data"] == {"booking_id": "42"}
    assert client.get("/api/notifications", headers=headers[1]).json() == []
    assert client.put(f"/api/notifications/{notice['id']}/read", headers=headers[1], json={}).status_code == 404
    assert client.put(f"/api/notifications/{notice['id']}/read", headers=headers[0], json={}).status_code == 200
    assert client.get("/api/notifications", headers=headers[0]).json()[0]["read"] is True


def test_admin_can_notify_one_user_or_every_active_user_with_push():
    with SessionLocal() as db:
        admin = User(email="admin-messages@example.com", password_hash="unused", role=UserRole.admin)
        musician = User(email="band-messages@example.com", password_hash="unused", role=UserRole.musician)
        customer = User(email="client-messages@example.com", password_hash="unused", role=UserRole.client)
        inactive = User(email="inactive-messages@example.com", password_hash="unused", role=UserRole.client, is_active=False)
        db.add_all([admin, musician, customer, inactive])
        db.flush()
        db.add(MusicianProfile(user_id=musician.id, contact_name="Ana", group_name="Infranqueable",
                group_type="Banda", musical_style="Regional", member_count=5,
                hourly_rate=1000, equipment_brands="[]", description="Test"))
        db.add(ClientProfile(user_id=customer.id, name="Cliente", admin_phone="8111111111",
                             city="Monterrey", municipality="Monterrey", state="Nuevo León"))
        db.commit()
        admin_id, musician_id, customer_id, inactive_id = admin.id, musician.id, customer.id, inactive.id
        admin_headers = {"Authorization": f"Bearer {create_token(admin)}"}
        musician_headers = {"Authorization": f"Bearer {create_token(musician)}"}
    recipients = client.get("/api/notifications/admin/recipients", headers=admin_headers)
    assert recipients.status_code == 200
    assert {entry["id"] for entry in recipients.json()} == {admin_id, musician_id, customer_id}
    assert next(entry for entry in recipients.json() if entry["id"] == musician_id)["name"] == "Infranqueable"
    assert client.get("/api/notifications/admin/recipients", headers=musician_headers).status_code == 403
    client.put("/api/notifications/devices", headers=musician_headers,
               json={"installation_id": "z" * 32, "token": "t" * 100})

    message = {"message_id": "specific-message-0001", "title": "Hola, Infranqueable",
               "body": "Revisa tus eventos de esta semana.", "recipient_user_id": musician_id}
    assert client.post("/api/notifications/admin/send", headers=musician_headers, json=message).status_code == 403
    sent = client.post("/api/notifications/admin/send", headers=admin_headers, json=message)
    assert sent.status_code == 201
    assert sent.json()["recipient_count"] == 1
    assert sent.json()["queued_devices"] == 1
    assert client.post("/api/notifications/admin/send", headers=admin_headers, json=message).json()["queued_devices"] == 1
    assert client.post("/api/notifications/admin/send", headers=admin_headers,
        json={**message, "body": "Un mensaje distinto"}).status_code == 409
    assert client.post("/api/notifications/admin/send", headers=admin_headers,
        json={**message, "message_id": "inactive-message-0001", "recipient_user_id": inactive_id}).status_code == 404

    broadcast = {"message_id": "broadcast-message-0001", "title": "Aviso general",
                 "body": "Bienvenidos a Garibaldi."}
    result = client.post("/api/notifications/admin/send", headers=admin_headers, json=broadcast)
    assert result.status_code == 201
    assert result.json()["recipient_count"] == 3
    with SessionLocal() as db:
        notices = db.scalars(select(UserNotification).where(
            UserNotification.event_key == "admin_announcement:broadcast-message-0001")).all()
        assert {notice.user_id for notice in notices} == {admin_id, musician_id, customer_id}
        assert not db.scalars(select(UserNotification).where(UserNotification.user_id == inactive_id)).all()
