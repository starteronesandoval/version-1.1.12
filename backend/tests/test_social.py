import os
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_social.db")
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("UPLOAD_DIR", "test_uploads")
os.environ.setdefault("SECRET_KEY", "test-only-secret-key-with-at-least-32-characters")

from fastapi.testclient import TestClient
from sqlalchemy import select
from app.auth import create_token
from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import User, UserRole, ClientProfile, MusicianProfile, Media, MediaType, MediaAjua, MediaShare

client = TestClient(app)


def setup_function():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def teardown_module():
    Base.metadata.drop_all(engine)


def fixture():
    with SessionLocal() as db:
        users = [User(email=f"social{i}@example.com", password_hash="unused", role=role)
                 for i, role in enumerate([UserRole.client, UserRole.client, UserRole.musician, UserRole.musician])]
        db.add_all(users); db.flush()
        customers = [ClientProfile(user_id=u.id, name=f"Cliente {i}", admin_phone="8111111111")
                     for i, u in enumerate(users[:2])]
        groups = [MusicianProfile(user_id=u.id, contact_name="Ana", group_name=f"Grupo {i}",
                  group_type="Banda", musical_style="Regional", member_count=5, hourly_rate=1000,
                  equipment_brands="[]", description="Grupo de prueba") for i, u in enumerate(users[2:])]
        db.add_all(customers + groups); db.flush()
        media = [Media(musician_id=groups[0].id, media_type=kind, position=1, url=f"/uploads/{kind.value}.jpg")
                 for kind in [MediaType.photo, MediaType.video]]
        db.add_all(media); db.commit()
        return ([{"Authorization": f"Bearer {create_token(u)}"} for u in users],
                [m.id for m in media], customers[0].id)


def test_ajua_is_unique_reversible_and_group_inbox_is_private():
    headers, media, _ = fixture()
    for media_id in media:
        url = f"/api/media/{media_id}/ajua"
        assert client.get(url).status_code == 401
        assert client.put(url, headers=headers[2], json={"active": True}).status_code == 403
        for _ in range(2):
            response = client.put(url, headers=headers[0], json={"active": True})
            assert response.status_code == 200
            assert response.json()["count"] == 1
        assert client.get(url, headers=headers[1]).json()["active"] is False
        assert client.put(url, headers=headers[1], json={"active": True}).json()["count"] == 2
        assert client.put(url, headers=headers[0], json={"active": False}).json()["count"] == 1
    inbox = "/api/musicians/me/ajua-notifications"
    notices = client.get(inbox, headers=headers[2]).json()
    assert len(notices) == 2
    assert client.get(inbox, headers=headers[3]).json() == []
    assert client.get(inbox, headers=headers[0]).status_code == 403
    mark = f"{inbox}/{notices[0]['id']}/read"
    assert client.put(mark, headers=headers[3], json={}).status_code == 404
    assert client.put(mark, headers=headers[2], json={}).status_code == 200
    assert any(n['read'] for n in client.get(inbox, headers=headers[2]).json())


def test_shares_preserve_attribution_and_never_expose_private_profile_fields():
    headers, media, profile_id = fixture()
    for media_id in media:
        url = f"/api/media/{media_id}/share"
        assert client.put(url, headers=headers[2], json={"active": True}).status_code == 403
        for _ in range(2):
            assert client.put(url, headers=headers[0], json={"active": True}).json()["shared"] is True
    feed = f"/api/clients/{profile_id}/shared-media"
    assert client.get(feed).status_code == 401
    data = client.get(feed, headers=headers[1]).json()
    assert set(data) == {"client_name", "owner", "items"}
    assert data["owner"] is False
    assert len(data["items"]) == 2
    assert all(item["group_name"] == "Grupo 0" for item in data["items"])
    assert client.get(feed + '?offset=2', headers=headers[0]).json()["items"] == []
    # Another customer's removal never removes the owner's share.
    url = f"/api/media/{media[0]}/share"
    client.put(url, headers=headers[1], json={"active": False})
    assert len(client.get(feed, headers=headers[0]).json()["items"]) == 2
    client.put(url, headers=headers[0], json={"active": False})
    assert len(client.get(feed, headers=headers[0]).json()["items"]) == 1


def test_replacing_media_does_not_inherit_reactions_or_shares():
    headers, media, profile_id = fixture()
    media_id = media[0]
    client.put(f"/api/media/{media_id}/ajua", headers=headers[0], json={"active": True})
    client.put(f"/api/media/{media_id}/share", headers=headers[0], json={"active": True})
    response = client.post('/api/musicians/me/media?media_type=photo&position=1',
                           headers=headers[2], files={'file': ('new.png', b'\x89PNG\r\n\x1a\n' + b'0' * 20, 'image/png')})
    assert response.status_code == 201
    with SessionLocal() as db:
        assert db.scalar(select(MediaAjua.id)) is None
        assert db.scalar(select(MediaShare.id)) is None
    assert client.get(f"/api/clients/{profile_id}/shared-media", headers=headers[0]).json()["items"] == []
    assert client.put('/api/media/99999/ajua', headers=headers[0], json={"active": True}).status_code == 404
