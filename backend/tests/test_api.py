import os
from pathlib import Path

os.environ["DATABASE_URL"] = "sqlite:///./test_balam.db"
os.environ["UPLOAD_DIR"] = "test_uploads"

from fastapi.testclient import TestClient
from app.database import Base, engine
from app.main import app

client = TestClient(app)


def setup_module():
    Base.metadata.drop_all(engine); Base.metadata.create_all(engine)


def teardown_module():
    Base.metadata.drop_all(engine)
    engine.dispose()
    Path("test_balam.db").unlink(missing_ok=True)


def test_full_registration_and_search_flow():
    musician = client.post("/api/auth/register", json={"email":"musico@example.com","password":"segura123","role":"musician"})
    assert musician.status_code == 201
    mh = {"Authorization": f"Bearer {musician.json()['access_token']}"}
    profile = client.put("/api/musicians/me", headers=mh, json={
        "contact_name":"Ana López","group_name":"Los del Valle","group_type":"Norteño",
        "musical_style":"Norteño tradicional","member_count":5,"hourly_rate":3500,
        "includes_sound":True,"subwoofer_count":2,"mid_speaker_count":4,
        "equipment_brands":["JBL","QSC"],"audience_capacity":500,"description":"Música para eventos"
    })
    assert profile.status_code == 200
    choice = client.put("/api/users/me/avatar-preset", headers=mh,
        json={"preset":"jaguar_accordion","color":"#20C9B5"})
    assert choice.status_code == 200
    restored = client.get("/api/musicians/me", headers=mh)
    assert restored.status_code == 200
    assert restored.json()["equipment_brands"] == ["JBL", "QSC"]
    assert restored.json()["avatar_preset"] == "jaguar_accordion"
    found = client.get("/api/musicians?q=Valle")
    assert found.status_code == 200 and found.json()[0]["group_name"] == "Los del Valle"
    assert found.json()[0]["avatar_color"] == "#20C9B5"
    customer = client.post("/api/auth/register", json={"email":"cliente@example.com","password":"segura123","role":"client"})
    ch = {"Authorization": f"Bearer {customer.json()['access_token']}"}
    result = client.put("/api/clients/me", headers=ch, json={"name":"Luis","musical_tastes":["Norteño"],"favorite_groups":["Intocable"]})
    assert result.status_code == 200 and result.json()["musical_tastes"] == ["Norteño"]
    restored_client = client.get("/api/clients/me", headers=ch)
    assert restored_client.status_code == 200
    assert restored_client.json()["favorite_groups"] == ["Intocable"]
    avatar = client.post("/api/clients/me/avatar", headers=ch,
        files={"file": ("avatar.jpg", b"fake-image", "image/jpeg")})
    assert avatar.status_code == 201
    assert client.get("/api/clients/me", headers=ch).json()["avatar_url"].startswith("/uploads/clients/")
