import json
from datetime import date, datetime, timezone
from typing import Literal
from uuid import uuid4
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StrictBool, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .auth import require_role
from .config import settings
from .database import get_db
from .models import MusicianProfile, PlatinumAudit, PlatinumCertificate, User, UserRole
from .schemas import PlatinumResponse

PLATINUM_ADMIN_EMAIL = "administrador@balam.local"
router = APIRouter(prefix="/api")


def can_manage_platinum(user: User) -> bool:
    return user.is_active and user.role == UserRole.admin and user.email.strip().casefold() == PLATINUM_ADMIN_EMAIL


def platinum_admin(user: User = Depends(require_role(UserRole.admin))) -> User:
    if not can_manage_platinum(user):
        raise HTTPException(403, "Solo la cuenta administradora autorizada puede certificar agrupaciones")
    return user


class PlatinumIssue(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    recommendation: str = Field(min_length=300, max_length=12000)
    verification_method: Literal["administrative", "in_person"]
    verified_on: date
    existence_confirmed: StrictBool
    excellent_service_confirmed: StrictBool
    commitments_confirmed: StrictBool

    @field_validator("verified_on")
    @classmethod
    def not_future(cls, value):
        if value > datetime.now(ZoneInfo(settings.event_timezone)).date():
            raise ValueError("La fecha de verificación no puede estar en el futuro")
        return value


class PlatinumRevoke(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    reason: str = Field(min_length=10, max_length=2000)


def public_certificate(profile: MusicianProfile) -> PlatinumResponse | None:
    certificate = profile.platinum_certificate
    if (not certificate or certificate.revoked_at or not profile.user.is_active
            or certificate.group_name_snapshot.strip().casefold() != profile.group_name.strip().casefold()):
        return None
    return PlatinumResponse(
        certificate_code=certificate.certificate_code,
        group_name=certificate.group_name_snapshot,
        recommendation=certificate.recommendation,
        verification_method=certificate.verification_method,
        verified_on=certificate.verified_on,
        issued_at=certificate.issued_at.replace(tzinfo=timezone.utc),
    )


@router.get("/musicians/{musician_id}/platinum", response_model=PlatinumResponse)
def get_certificate(musician_id: int, db: Session = Depends(get_db)):
    profile = db.get(MusicianProfile, musician_id)
    certificate = public_certificate(profile) if profile else None
    if not certificate:
        raise HTTPException(404, "La agrupación no tiene una certificación Platino vigente")
    return certificate


@router.put("/admin/musicians/{musician_id}/platinum", response_model=PlatinumResponse)
def issue_certificate(musician_id: int, data: PlatinumIssue,
                      user: User = Depends(platinum_admin), db: Session = Depends(get_db)):
    # Also enforce authorization for maintenance calls, not only HTTP dependencies.
    platinum_admin(user)
    if not all((data.existence_confirmed, data.excellent_service_confirmed, data.commitments_confirmed)):
        raise HTTPException(422, "Confirma la existencia, la excelencia del servicio y el cumplimiento de la agrupación")
    profile = db.scalar(select(MusicianProfile).where(MusicianProfile.id == musician_id).with_for_update())
    if not profile:
        raise HTTPException(404, "Agrupación no encontrada")
    if not profile.user.is_active:
        raise HTTPException(409, "La cuenta de la agrupación está desactivada")
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    certificate = profile.platinum_certificate
    action = "updated" if certificate and not certificate.revoked_at else "issued"
    if certificate is None:
        certificate = PlatinumCertificate(musician_id=profile.id)
        profile.platinum_certificate = certificate
    certificate.certificate_code = f"PLATINO-{uuid4().hex.upper()}"
    certificate.group_name_snapshot = profile.group_name.strip()
    certificate.recommendation = data.recommendation
    certificate.verification_method = data.verification_method
    certificate.verified_on = data.verified_on
    certificate.issued_at = now
    certificate.issued_by_user_id = user.id
    certificate.revoked_at = None
    certificate.revocation_reason = None
    db.add(PlatinumAudit(musician_id=profile.id, admin_user_id=user.id,
        action=action, certificate_code=certificate.certificate_code,
        details=json.dumps({**data.model_dump(mode="json"), "group_name": certificate.group_name_snapshot}, ensure_ascii=False),
        created_at=now))
    db.commit()
    return public_certificate(profile)


@router.post("/admin/musicians/{musician_id}/platinum/revoke")
def revoke_certificate(musician_id: int, data: PlatinumRevoke,
                       user: User = Depends(platinum_admin), db: Session = Depends(get_db)):
    profile = db.scalar(select(MusicianProfile).where(MusicianProfile.id == musician_id).with_for_update())
    certificate = profile.platinum_certificate if profile else None
    if not certificate:
        raise HTTPException(404, "Certificado no encontrado")
    if not certificate.revoked_at:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        certificate.revoked_at = now
        certificate.revocation_reason = data.reason
        db.add(PlatinumAudit(musician_id=musician_id, admin_user_id=user.id,
            action="revoked", certificate_code=certificate.certificate_code,
            details=json.dumps({"reason": data.reason}, ensure_ascii=False), created_at=now))
        db.commit()
    return {"revoked": True}


@router.get("/admin/musicians/{musician_id}/platinum/history")
def certification_history(musician_id: int, user: User = Depends(platinum_admin), db: Session = Depends(get_db)):
    records = db.scalars(select(PlatinumAudit).where(PlatinumAudit.musician_id == musician_id)
        .order_by(PlatinumAudit.id.desc()).limit(100)).all()
    return [{"action": record.action, "certificate_code": record.certificate_code,
             "created_at": record.created_at, "details": json.loads(record.details)} for record in records]
