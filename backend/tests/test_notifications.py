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
from app.models import PushDelivery, User, UserNotification, UserRole
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
