"""Private notification inbox and durable Firebase Cloud Messaging delivery."""
import json
import logging
from datetime import datetime, timedelta, timezone

import google.auth.transport.requests
from google.oauth2 import service_account
import requests
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from sqlalchemy.orm import selectinload

from .auth import current_user, require_role
from .config import settings
from .database import SessionLocal, get_db
from .models import PushDelivery, PushDevice, User, UserNotification, UserRole

router = APIRouter(prefix="/api/notifications", tags=["notifications"])
logger = logging.getLogger(__name__)


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class DeviceRegistration(BaseModel):
    installation_id: str = Field(min_length=16, max_length=100)
    token: str = Field(min_length=30, max_length=512)


class AdminAnnouncement(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    message_id: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    title: str = Field(min_length=3, max_length=120)
    body: str = Field(min_length=5, max_length=250)
    recipient_user_id: int | None = Field(default=None, gt=0)


def enqueue(db: Session, *, user_id: int, event_key: str, kind: str,
            title: str, body: str, data: dict[str, str] | None = None) -> None:
    """Join the caller's transaction; duplicate events do not create another alert."""
    with db.begin_nested() as nested:
        notice = UserNotification(user_id=user_id, event_key=event_key,
                                  kind=kind, title=title, body=body,
                                  data_json=json.dumps(data or {}))
        db.add(notice)
        try:
            db.flush()
        except IntegrityError:
            nested.rollback()
            return
        devices = db.scalars(select(PushDevice).where(
            PushDevice.user_id == user_id, PushDevice.enabled.is_(True))).all()
        for device in devices:
            db.add(PushDelivery(notification_id=notice.id, device_id=device.id,
                                next_attempt_at=utcnow()))


@router.get("/admin/recipients")
def admin_recipients(
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    recipients = db.scalars(select(User).options(
        selectinload(User.musician_profile), selectinload(User.client_profile),
    ).where(User.is_active.is_(True)).order_by(User.id)).all()
    enabled = set(db.scalars(select(PushDevice.user_id).where(
        PushDevice.enabled.is_(True),
    )).all())
    return [{
        "id": recipient.id,
        "role": recipient.role.value,
        "name": (
            recipient.musician_profile.group_name if recipient.musician_profile else
            recipient.client_profile.name if recipient.client_profile else
            "Administrador" if recipient.role == UserRole.admin else
            "Músico sin perfil" if recipient.role == UserRole.musician else
            "Cliente sin perfil"
        ),
        "email": recipient.email,
        "push_enabled": recipient.id in enabled,
    } for recipient in recipients]


@router.post("/admin/send", status_code=201)
def admin_send_announcement(
    data: AdminAnnouncement,
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    query = select(User.id).where(User.is_active.is_(True))
    if data.recipient_user_id is not None:
        query = query.where(User.id == data.recipient_user_id)
    recipients = db.scalars(query).all()
    if not recipients:
        raise HTTPException(404, "No hay un destinatario activo con ese ID")
    key = f"admin_announcement:{data.message_id}"
    existing = db.scalar(select(UserNotification).where(UserNotification.event_key == key))
    if existing and (existing.title != data.title or existing.body != data.body):
        raise HTTPException(409, "El identificador de este envío ya se utilizó")
    for recipient_id in recipients:
        enqueue(db, user_id=recipient_id, event_key=key, kind="announcement",
                title=data.title, body=data.body,
                data={"sender_user_id": str(user.id)})
    db.commit()
    return {
        "recipient_count": len(recipients),
        "queued_devices": db.scalar(select(func.count(PushDelivery.id))
            .join(UserNotification, PushDelivery.notification_id == UserNotification.id)
            .where(UserNotification.event_key == key)) or 0,
        "push_configured": push_configured(),
    }


@router.put("/devices")
def register_device(data: DeviceRegistration, user: User = Depends(current_user),
                    db: Session = Depends(get_db)):
    now = utcnow()
    existing = db.scalar(select(PushDevice).where(
        PushDevice.installation_id == data.installation_id))
    token_owner = db.scalar(select(PushDevice).where(PushDevice.token == data.token))
    if token_owner and token_owner is not existing:
        # FCM rotates tokens; move ownership to this authenticated installation.
        db.delete(token_owner)
        db.flush()
    if existing:
        if existing.user_id != user.id:
            db.query(PushDelivery).filter(PushDelivery.device_id == existing.id).delete()
        existing.user_id = user.id
        existing.token = data.token
        existing.enabled = True
        existing.updated_at = now
    else:
        db.add(PushDevice(user_id=user.id, installation_id=data.installation_id,
                          token=data.token, enabled=True, updated_at=now))
    db.commit()
    return {"registered": True, "push_configured": push_configured()}


@router.put("/devices/{installation_id}/disable")
def disable_device(installation_id: str, user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    device = db.scalar(select(PushDevice).where(
        PushDevice.installation_id == installation_id, PushDevice.user_id == user.id))
    if device:
        device.enabled = False
        db.commit()
    return {"disabled": True}


@router.get("")
def inbox(user: User = Depends(current_user), db: Session = Depends(get_db)):
    notices = db.scalars(select(UserNotification).where(
        UserNotification.user_id == user.id).order_by(
            UserNotification.created_at.desc(), UserNotification.id.desc()).limit(100)).all()
    return [{"id": n.id, "kind": n.kind, "title": n.title, "body": n.body,
             "data": json.loads(n.data_json), "created_at": n.created_at,
             "read": n.read_at is not None} for n in notices]


@router.put("/{notification_id}/read")
def mark_read(notification_id: int, user: User = Depends(current_user),
              db: Session = Depends(get_db)):
    notice = db.scalar(select(UserNotification).where(
        UserNotification.id == notification_id, UserNotification.user_id == user.id))
    if not notice:
        raise HTTPException(404, "Aviso no encontrado")
    notice.read_at = notice.read_at or utcnow()
    db.commit()
    return {"read": True}


def push_configured() -> bool:
    return bool(settings.fcm_project_id and settings.fcm_credentials_file
                and settings.fcm_credentials_file.is_file())


def send_fcm(token: str, notice: UserNotification) -> str:
    credentials = service_account.Credentials.from_service_account_file(
        str(settings.fcm_credentials_file),
        scopes=["https://www.googleapis.com/auth/firebase.messaging"])
    credentials.refresh(google.auth.transport.requests.Request())
    payload = {"message": {
        "token": token,
        "notification": {"title": notice.title, "body": notice.body},
        "data": {"notification_id": str(notice.id), "kind": notice.kind,
                 **json.loads(notice.data_json)},
        "android": {"priority": "HIGH", "notification": {
            "channel_id": "garibaldi_alerts", "sound": "default",
            "notification_priority": "PRIORITY_HIGH", "visibility": "PRIVATE",
            "tag": str(notice.id)}},
    }}
    response = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{settings.fcm_project_id}/messages:send",
        json=payload, headers={"Authorization": f"Bearer {credentials.token}"}, timeout=10)
    if response.status_code == 200:
        return "sent"
    if response.status_code in {400, 404} and any(
        code in response.text for code in ("UNREGISTERED", "INVALID_ARGUMENT")):
        return "invalid_token"
    response.raise_for_status()
    return "retry"


def dispatch_pending(limit: int = 30) -> int:
    if not push_configured():
        return 0
    completed = 0
    with SessionLocal() as db:
        ids = db.scalars(select(PushDelivery.id).where(
            PushDelivery.delivered_at.is_(None), PushDelivery.next_attempt_at <= utcnow(),
            PushDelivery.attempts < 12).order_by(PushDelivery.id).limit(limit)).all()
    for delivery_id in ids:
        with SessionLocal() as db:
            delivery = db.scalar(select(PushDelivery).where(
                PushDelivery.id == delivery_id).with_for_update(skip_locked=True))
            if not delivery or delivery.delivered_at or delivery.next_attempt_at > utcnow():
                continue
            device = db.get(PushDevice, delivery.device_id)
            notice = db.get(UserNotification, delivery.notification_id)
            if not device or not device.enabled or not notice or device.user_id != notice.user_id:
                delivery.delivered_at = utcnow()
                db.commit()
                continue
            try:
                result = send_fcm(device.token, notice)
                if result == "invalid_token":
                    device.enabled = False
                delivery.delivered_at = utcnow()
                completed += result == "sent"
            except Exception:
                logger.exception("Falló la entrega push del aviso %s", notice.id)
                delivery.attempts += 1
                delay = min(3600, 15 * (2 ** min(delivery.attempts, 8)))
                delivery.next_attempt_at = utcnow() + timedelta(seconds=delay)
            db.commit()
    return completed
