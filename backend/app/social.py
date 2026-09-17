from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, StrictBool
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .auth import current_user, require_role
from .database import get_db
from .models import ClientProfile, Media, MediaAjua, MediaShare, MusicianProfile, User, UserRole
from .notifications import enqueue

router = APIRouter(prefix="/api")


class AjuaUpdate(BaseModel):
    active: StrictBool


def media_or_404(media_id, db):
    media = db.get(Media, media_id)
    if not media:
        raise HTTPException(404, "Publicación no encontrada")
    return media


def ajua_state(media_id, user, db):
    count = db.scalar(select(func.count()).select_from(MediaAjua).where(
        MediaAjua.media_id == media_id, MediaAjua.active.is_(True)))
    mine = db.scalar(select(MediaAjua.active).join(ClientProfile).where(
        MediaAjua.media_id == media_id, ClientProfile.user_id == user.id))
    shared = db.scalar(select(MediaShare.id).join(ClientProfile).where(
        MediaShare.media_id == media_id, ClientProfile.user_id == user.id))
    return {"media_id": media_id, "count": count, "active": bool(mine), "shared": shared is not None}


@router.get("/media/{media_id}/ajua")
def get_ajua(media_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    media_or_404(media_id, db)
    return ajua_state(media_id, user, db)


@router.put("/media/{media_id}/ajua")
def set_ajua(media_id: int, data: AjuaUpdate,
             user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    media = media_or_404(media_id, db)
    profile = db.scalar(select(ClientProfile).where(ClientProfile.user_id == user.id))
    if not profile:
        raise HTTPException(409, "Completa tu perfil de cliente")
    reaction = db.scalar(select(MediaAjua).where(
        MediaAjua.media_id == media_id, MediaAjua.client_id == profile.id))
    if reaction:
        reaction.active = data.active
    elif data.active:
        db.add(MediaAjua(media_id=media_id, client_id=profile.id))
        musician = db.get(MusicianProfile, media.musician_id)
        enqueue(db, user_id=musician.user_id,
                event_key=f"ajua:{media_id}:{profile.id}", kind="ajua",
                title="¡Ajua en tu publicación!",
                body="A un cliente le gustó una foto o video de tu agrupación.",
                data={"media_id": str(media_id)})
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        # A repeated concurrent request must never create a second reaction.
        reaction = db.scalar(select(MediaAjua).where(
            MediaAjua.media_id == media_id, MediaAjua.client_id == profile.id))
        if not reaction:
            raise HTTPException(409, "La publicación cambió; vuelve a cargarla")
        reaction.active = data.active
        db.commit()
    return ajua_state(media_id, user, db)


@router.get("/musicians/me/ajua-notifications")
def notifications(user: User = Depends(require_role(UserRole.musician)), db: Session = Depends(get_db)):
    query = select(MediaAjua, Media, ClientProfile.name).select_from(MediaAjua).join(Media, MediaAjua.media_id == Media.id).join(
        MusicianProfile, Media.musician_id == MusicianProfile.id).join(
        ClientProfile, MediaAjua.client_id == ClientProfile.id).where(
        MusicianProfile.user_id == user.id, MediaAjua.active.is_(True))
    rows = db.execute(query.order_by(MediaAjua.read, MediaAjua.created_at.desc()).limit(50)).all()
    return [{"id": reaction.id, "client_id": reaction.client_id, "client_name": name, "media_id": media.id,
             "media_type": media.media_type, "url": media.url, "read": reaction.read,
             "created_at": reaction.created_at} for reaction, media, name in rows]


@router.put("/musicians/me/ajua-notifications/{notification_id}/read")
def read_notification(notification_id: int, user: User = Depends(require_role(UserRole.musician)),
                      db: Session = Depends(get_db)):
    reaction = db.scalar(select(MediaAjua).join(Media).join(MusicianProfile).where(
        MediaAjua.id == notification_id, MusicianProfile.user_id == user.id))
    if not reaction:
        raise HTTPException(404, "Aviso no encontrado")
    reaction.read = True
    db.commit()
    return {"read": True}


@router.put("/media/{media_id}/share")
def share_media(media_id: int, data: AjuaUpdate,
                user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    media = media_or_404(media_id, db)
    profile = db.scalar(select(ClientProfile).where(ClientProfile.user_id == user.id))
    if not profile:
        raise HTTPException(409, "Completa tu perfil de cliente")
    share = db.scalar(select(MediaShare).where(
        MediaShare.media_id == media_id, MediaShare.client_id == profile.id))
    if data.active and not share:
        db.add(MediaShare(media_id=media_id, client_id=profile.id))
        musician = db.get(MusicianProfile, media.musician_id)
        enqueue(db, user_id=musician.user_id,
                event_key=f"share:{media_id}:{profile.id}", kind="share",
                title="Compartieron tu publicación",
                body="Un cliente compartió una foto o video tuyo en su perfil.",
                data={"media_id": str(media_id)})
    elif not data.active and share:
        db.delete(share)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if not db.scalar(select(MediaShare.id).where(
            MediaShare.media_id == media_id, MediaShare.client_id == profile.id)):
            raise HTTPException(409, "La publicación cambió; vuelve a cargarla")
    return ajua_state(media_id, user, db)


@router.get("/clients/{client_id}/shared-media")
def shared_media(client_id: int, offset: int = 0,
                 user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile = db.get(ClientProfile, client_id)
    if not profile:
        raise HTTPException(404, "Perfil no encontrado")
    rows = db.execute(select(MediaShare, Media, MusicianProfile.group_name).select_from(MediaShare).join(Media, MediaShare.media_id == Media.id).join(
        MusicianProfile, Media.musician_id == MusicianProfile.id).where(
        MediaShare.client_id == client_id).order_by(MediaShare.created_at.desc(), MediaShare.id.desc())
        .offset(max(0, offset)).limit(20)).all()
    # A social profile never exposes contact details or contracts.
    return {"client_name": profile.name, "owner": profile.user_id == user.id,
            "items": [{"id": media.id, "url": media.url, "media_type": media.media_type,
                       "musician_id": media.musician_id, "group_name": name,
                       "shared_at": share.created_at} for share, media, name in rows]}
