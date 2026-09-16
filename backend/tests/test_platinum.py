import os
from datetime import date, timedelta

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_platinum.db")
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("UPLOAD_DIR", "test_uploads")
os.environ.setdefault("SECRET_KEY", "test-only-secret-key-with-at-least-32-characters")

from fastapi.testclient import TestClient
from sqlalchemy import select
from app.auth import create_token
from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import User, UserRole, MusicianProfile, MusicianPayoutDestination, PlatinumAudit, PlatinumRequest

client = TestClient(app)


def setup_function():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def teardown_module():
    Base.metadata.drop_all(engine)


def fixture():
    with SessionLocal() as db:
        users = [User(email=email, password_hash="unused", role=role) for email, role in [
            ("administrador@balam.local", UserRole.admin),
            ("another-admin@example.com", UserRole.admin),
            ("group@example.com", UserRole.musician),
            ("customer@example.com", UserRole.client),
        ]]
        db.add_all(users); db.flush()
        group = MusicianProfile(user_id=users[2].id, contact_name="Ana", group_name="Grupo de prueba",
            group_type="Banda", musical_style="Regional", member_count=5, hourly_rate=1000,
            equipment_brands="[]", description="Una agrupación real")
        db.add(group); db.commit()
        return [{"Authorization": f"Bearer {create_token(user)}"} for user in users], group.id


def payload():
    return {"recommendation": "La administración recomienda a esta agrupación por su trabajo y cumplimiento. " * 8,
            "verification_method": "administrative", "verified_on": date.today().isoformat(),
            "existence_confirmed": True, "excellent_service_confirmed": True, "commitments_confirmed": True}


def test_only_designated_administrator_can_certify_and_revoke():
    headers, group_id = fixture()
    url = f"/api/admin/musicians/{group_id}/platinum"
    assert client.put(url, json=payload()).status_code == 401
    for forbidden in headers[1:]:
        assert client.put(url, headers=forbidden, json=payload()).status_code == 403
        assert client.post(url + '/revoke', headers=forbidden, json={'reason': 'Motivo de prueba completo'}).status_code == 403
        assert client.get(url + '/history', headers=forbidden).status_code == 403
    response = client.put(url, headers=headers[0], json=payload())
    assert response.status_code == 200
    certificate = response.json()
    assert certificate['group_name'] == 'Grupo de prueba'
    assert certificate['verification_method'] == 'administrative'
    assert certificate['certificate_code'].startswith('PLATINO-')
    public = client.get(f'/api/musicians/{group_id}').json()
    assert public['platinum_certificate'] == certificate
    assert 'issued_by_user_id' not in certificate
    assert client.get('/api/admin/groups', headers=headers[0]).json()[0]['can_manage_platinum'] is True
    assert client.get('/api/admin/groups', headers=headers[1]).json()[0]['can_manage_platinum'] is False
    assert client.post(url + '/revoke', headers=headers[0], json={'reason': 'Requiere una revisión adicional'}).status_code == 200
    assert client.get(f'/api/musicians/{group_id}/platinum').status_code == 404
    assert client.get(f'/api/musicians/{group_id}').json().get('platinum_certificate') is None
    history = client.get(url + '/history', headers=headers[0]).json()
    assert [record['action'] for record in history] == ['revoked', 'issued']
    assert history[1]['details']['recommendation'] == payload()['recommendation'].strip()


def test_admin_panel_accepts_connect_accounts_without_stored_bank_number():
    headers, group_id = fixture()
    with SessionLocal() as db:
        db.add(MusicianPayoutDestination(musician_id=group_id,
            stripe_connected_account_id='acct_connect_only', encrypted_number=None))
        db.commit()
    for path in ['/api/admin/clients', '/api/admin/groups', '/api/admin/bookings']:
        response = client.get(path, headers=headers[0])
        assert response.status_code == 200
        assert isinstance(response.json(), list)
    group = client.get('/api/admin/groups', headers=headers[0]).json()[0]
    assert group['deposit_account'] is None
    assert group['stripe_connected_account_id'] == 'acct_connect_only'
    assert group['can_manage_platinum'] is True
    # Legacy accounts that actually store an encrypted number remain readable.
    from app.main import payout_cipher
    with SessionLocal() as db:
        destination = db.scalar(select(MusicianPayoutDestination))
        destination.encrypted_number = payout_cipher().encrypt(b'012345678901234567').decode('ascii')
        db.commit()
    assert client.get('/api/admin/groups', headers=headers[0]).json()[0]['deposit_account'] == '012345678901234567'


def test_requires_substantial_recommendation_confirmation_and_real_date():
    headers, group_id = fixture()
    url = f"/api/admin/musicians/{group_id}/platinum"
    invalid = [
        {'recommendation': ' ' * 350}, {'recommendation': 'x' * 12001},
        {'existence_confirmed': False}, {'excellent_service_confirmed': False},
        {'commitments_confirmed': False}, {'existence_confirmed': 'true'},
        {'verified_on': (date.today() + timedelta(days=2)).isoformat()},
        {'verification_method': 'automatic'},
    ]
    for change in invalid:
        assert client.put(url, headers=headers[0], json={**payload(), **change}).status_code == 422
    assert client.get(f'/api/musicians/{group_id}/platinum').status_code == 404
    with SessionLocal() as db:
        assert db.scalar(select(PlatinumAudit.id)) is None


def test_edits_preserve_history_and_changed_identity_hides_certificate():
    headers, group_id = fixture()
    url = f"/api/admin/musicians/{group_id}/platinum"
    first = client.put(url, headers=headers[0], json=payload()).json()
    changed = {**payload(), 'verification_method': 'in_person', 'recommendation': payload()['recommendation'] + ' Visita realizada.'}
    second = client.put(url, headers=headers[0], json=changed).json()
    assert first['certificate_code'] != second['certificate_code']
    assert second['verification_method'] == 'in_person'
    history = client.get(url + '/history', headers=headers[0]).json()
    assert [record['action'] for record in history] == ['updated', 'issued']
    assert history[1]['details']['recommendation'] == first['recommendation']
    with SessionLocal() as db:
        db.get(MusicianProfile, group_id).group_name = 'Otra agrupación'
        db.commit()
    assert client.get(f'/api/musicians/{group_id}/platinum').status_code == 404
    assert client.get(f'/api/musicians/{group_id}').json().get('platinum_certificate') is None


def test_musician_requests_once_then_admin_approves_without_deployment():
    headers, group_id = fixture()
    url = '/api/musicians/me/platinum-request'
    assert client.get(url, headers=headers[2]).json()['status'] == 'not_requested'
    response = client.post(url, headers=headers[2], json={'message': 'Estamos disponibles para una visita.'})
    assert response.status_code == 200
    original = response.json()
    assert original['status'] == 'pending'
    assert client.post(url, headers=headers[2], json={'message': 'Duplicado'}).json() == original
    with SessionLocal() as db:
        assert len(db.scalars(select(PlatinumRequest)).all()) == 1
    assert client.get(f'/api/musicians/{group_id}/platinum').status_code == 404
    public = client.get(f'/api/musicians/{group_id}').json()
    assert 'platinum_request' not in public
    group = client.get('/api/admin/groups', headers=headers[0]).json()[0]
    assert group['platinum_request']['status'] == 'pending'
    assert group['platinum_request']['message'] == 'Estamos disponibles para una visita.'
    result = client.put(f'/api/admin/musicians/{group_id}/platinum', headers=headers[0], json=payload())
    assert result.status_code == 200
    approved = client.get(url, headers=headers[2]).json()
    assert approved['status'] == 'certified'
    assert approved['certificate']['certificate_code'] == result.json()['certificate_code']
    assert client.post(url, headers=headers[2], json={}).status_code == 409
    assert client.get('/api/admin/groups', headers=headers[0]).json()[0]['platinum_request']['status'] == 'certified'


def test_request_rejection_revocation_and_resubmission():
    headers, group_id = fixture()
    url = '/api/musicians/me/platinum-request'
    review = f'/api/admin/musicians/{group_id}/platinum-request/reject'
    client.post(url, headers=headers[2], json={})
    assert client.post(review, headers=headers[1], json={'reason': 'Necesitamos una visita presencial.'}).status_code == 403
    assert client.post(review, headers=headers[0], json={'reason': 'No'}).status_code == 422
    response = client.post(review, headers=headers[0], json={'reason': 'Necesitamos una visita presencial.'})
    assert response.json()['status'] == 'rejected'
    assert client.get(url, headers=headers[2]).json()['response'] == 'Necesitamos una visita presencial.'
    assert client.post(review, headers=headers[0], json={'reason': 'Duplicado de rechazo'}).status_code == 409
    assert client.post(url, headers=headers[2], json={'message': 'Ya podemos recibir la visita.'}).json()['status'] == 'pending'
    cert = f'/api/admin/musicians/{group_id}/platinum'
    client.put(cert, headers=headers[0], json=payload())
    assert client.post(review, headers=headers[0], json={'reason': 'No debe retirar un certificado aprobado'}).status_code == 409
    client.post(cert + '/revoke', headers=headers[0], json={'reason': 'Se requiere una nueva verificación.'})
    assert client.get(url, headers=headers[2]).json()['status'] == 'revoked'
    assert client.post(url, headers=headers[2], json={}).json()['status'] == 'pending'
    assert client.get(f'/api/musicians/{group_id}/platinum').status_code == 404


def test_request_permissions_and_unrelated_group_isolation():
    headers, group_id = fixture()
    url = '/api/musicians/me/platinum-request'
    assert client.post(url, json={}).status_code == 401
    for forbidden in [headers[0], headers[1], headers[3]]:
        assert client.post(url, headers=forbidden, json={}).status_code == 403
    assert client.post(url, headers=headers[2], json={'musician_id': 999, 'status': 'approved'}).status_code == 422
    assert client.post(url, headers=headers[2], json={'message': 'a' * 2001}).status_code == 422
    with SessionLocal() as db:
        other_user = User(email='other-group@example.com', role=UserRole.musician, password_hash='unused')
        db.add(other_user); db.commit()
        other_headers = {'Authorization': f'Bearer {create_token(other_user)}'}
    assert client.post(url, headers=other_headers, json={}).status_code == 409
    assert client.get(url, headers=headers[2]).json()['status'] == 'not_requested'
