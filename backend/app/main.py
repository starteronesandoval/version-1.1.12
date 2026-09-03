import json
import shutil
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, File, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from .auth import create_token, current_user, hash_password, require_role, verify_password
from .config import settings
from .database import Base, engine, get_db
from .models import (AvatarChoice, ClientAvatar, ClientProfile, Media, MediaType,
                     MusicianProfile, User, UserRole)
from .schemas import (AvatarChoiceUpdate, ClientProfileResponse, ClientProfileUpsert, LoginRequest,
                      MusicianProfileResponse, MusicianProfileUpsert,
                      RegisterRequest, TokenResponse, UserResponse)

Base.metadata.create_all(bind=engine)
settings.upload_dir.mkdir(parents=True, exist_ok=True)

app = FastAPI(title=settings.app_name, version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=False, allow_methods=["*"], allow_headers=["*"])
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")


def csv(values: list[str]) -> str:
    return json.dumps([v.strip() for v in values if v.strip()], ensure_ascii=False)


def values(raw: str) -> list[str]:
    try:
        return json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []


def client_profiles():
    return select(ClientProfile).options(
        selectinload(ClientProfile.avatar),
        selectinload(ClientProfile.user).selectinload(User.avatar_choice),
    )


def musician_profiles():
    return select(MusicianProfile).options(
        selectinload(MusicianProfile.media),
        selectinload(MusicianProfile.user).selectinload(User.avatar_choice),
    )


def musician_out(profile: MusicianProfile) -> MusicianProfileResponse:
    choice = profile.user.avatar_choice
    return MusicianProfileResponse(
        id=profile.id, user_id=profile.user_id, contact_name=profile.contact_name,
        group_name=profile.group_name, group_type=profile.group_type,
        musical_style=profile.musical_style, member_count=profile.member_count,
        hourly_rate=profile.hourly_rate, includes_sound=profile.includes_sound,
        subwoofer_count=profile.subwoofer_count, mid_speaker_count=profile.mid_speaker_count,
        equipment_brands=values(profile.equipment_brands), audience_capacity=profile.audience_capacity,
        description=profile.description, media=profile.media,
        avatar_preset=choice.preset if choice else "jaguar_guitar",
        avatar_color=choice.color if choice else "#8B5CF6",
    )


def client_out(profile: ClientProfile) -> ClientProfileResponse:
    choice = profile.user.avatar_choice
    return ClientProfileResponse(
        id=profile.id, user_id=profile.user_id, name=profile.name,
        musical_tastes=values(profile.musical_tastes),
        favorite_groups=values(profile.favorite_groups),
        avatar_url=profile.avatar.url if profile.avatar else None,
        avatar_preset=choice.preset if choice else "jaguar_guitar",
        avatar_color=choice.color if choice else "#8B5CF6",
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/auth/register", response_model=TokenResponse, status_code=201)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    email = data.email.lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "El correo ya está registrado")
    user = User(email=email, password_hash=hash_password(data.password), role=data.role)
    db.add(user); db.commit(); db.refresh(user)
    return TokenResponse(access_token=create_token(user))


@app.post("/api/auth/login", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == data.email.lower()))
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(401, "Correo o contraseña incorrectos")
    return TokenResponse(access_token=create_token(user))


@app.get("/api/users/me", response_model=UserResponse)
def me(user: User = Depends(current_user)):
    return user


@app.put("/api/users/me/avatar-preset")
def set_avatar_preset(data: AvatarChoiceUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    allowed = {
        "jaguar_guitar", "jaguar_accordion", "jaguar_dj", "coyote_singer", "coyote_guitar", "coyote_drums",
        "owl_violin", "owl_keyboard", "owl_sax", "fox_bass", "fox_mariachi", "fox_singer", "bear_tuba",
        "bear_drums", "bear_accordion", "eagle_trumpet", "eagle_guitar", "eagle_dj", "rabbit_violin",
        "lion_trumpet", "lion_conductor", "lion_tuba", "axolotl_guitar", "axolotl_dj", "raccoon_bass",
        "deer_harp", "bull_trombone", "cat_violin", "elephant_cello", "turtle_flute",
        "music", "microphone", "guitar", "accordion", "drums", "headphones", "star", "jaguar",
    }
    if data.preset not in allowed:
        raise HTTPException(422, "Avatar no disponible")
    choice = db.scalar(select(AvatarChoice).where(AvatarChoice.user_id == user.id))
    if choice:
        choice.preset = data.preset; choice.color = data.color.upper()
    else:
        choice = AvatarChoice(user_id=user.id, preset=data.preset, color=data.color.upper()); db.add(choice)
    db.commit(); db.refresh(choice)
    return {"preset": choice.preset, "color": choice.color}


@app.put("/api/clients/me", response_model=ClientProfileResponse)
def upsert_client(data: ClientProfileUpsert, user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    payload = data.model_dump(exclude={"musical_tastes", "favorite_groups"})
    payload.update(musical_tastes=csv(data.musical_tastes), favorite_groups=csv(data.favorite_groups))
    if profile:
        for key, value in payload.items(): setattr(profile, key, value)
    else:
        profile = ClientProfile(user_id=user.id, **payload); db.add(profile)
    db.commit()
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    return client_out(profile)


@app.get("/api/clients/me", response_model=ClientProfileResponse)
def get_client(user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    if not profile: raise HTTPException(404, "Completa tu perfil")
    return client_out(profile)


@app.post("/api/clients/me/avatar", status_code=201)
def upload_client_avatar(file: UploadFile = File(...),
                         user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    if not profile: raise HTTPException(409, "Crea primero tu perfil de cliente")
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(415, "La foto de perfil debe ser una imagen")
    extension = Path(file.filename or "").suffix.lower() or ".jpg"
    folder = settings.upload_dir / "clients" / str(profile.id); folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"avatar-{uuid4().hex}{extension}"
    with target.open("wb") as output: shutil.copyfileobj(file.file, output)
    public_url = f"/uploads/clients/{profile.id}/{target.name}"
    if profile.avatar:
        old = settings.upload_dir / "clients" / str(profile.id) / Path(profile.avatar.url).name
        if old.exists(): old.unlink()
        profile.avatar.url = public_url
    else:
        db.add(ClientAvatar(client_id=profile.id, url=public_url))
    db.commit()
    return {"url": public_url}


@app.put("/api/musicians/me", response_model=MusicianProfileResponse)
def upsert_musician(data: MusicianProfileUpsert, user: User = Depends(require_role(UserRole.musician)), db: Session = Depends(get_db)):
    profile = db.scalar(select(MusicianProfile).where(MusicianProfile.user_id == user.id))
    payload = data.model_dump(exclude={"equipment_brands"}); payload["equipment_brands"] = csv(data.equipment_brands)
    if profile:
        for key, value in payload.items(): setattr(profile, key, value)
    else:
        profile = MusicianProfile(user_id=user.id, **payload); db.add(profile)
    db.commit()
    profile = db.scalar(musician_profiles().where(MusicianProfile.user_id == user.id))
    return musician_out(profile)


@app.get("/api/musicians/me", response_model=MusicianProfileResponse)
def get_musician(user: User = Depends(require_role(UserRole.musician)), db: Session = Depends(get_db)):
    profile = db.scalar(musician_profiles().where(MusicianProfile.user_id == user.id))
    if not profile: raise HTTPException(404, "Completa tu perfil")
    return musician_out(profile)


@app.get("/api/musicians", response_model=list[MusicianProfileResponse])
def search_musicians(q: str = "", group_type: str | None = None, musical_style: str | None = None,
                     max_hourly_rate: float | None = Query(None, ge=0), includes_sound: bool | None = None,
                     skip: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
    stmt = musician_profiles()
    if q:
        term = f"%{q}%"; stmt = stmt.where(or_(MusicianProfile.group_name.ilike(term), MusicianProfile.group_type.ilike(term), MusicianProfile.musical_style.ilike(term)))
    if group_type: stmt = stmt.where(MusicianProfile.group_type.ilike(f"%{group_type}%"))
    if musical_style: stmt = stmt.where(MusicianProfile.musical_style.ilike(f"%{musical_style}%"))
    if max_hourly_rate is not None: stmt = stmt.where(MusicianProfile.hourly_rate <= max_hourly_rate)
    if includes_sound is not None: stmt = stmt.where(MusicianProfile.includes_sound == includes_sound)
    return [musician_out(p) for p in db.scalars(stmt.offset(skip).limit(limit)).all()]


@app.get("/api/musicians/{musician_id}", response_model=MusicianProfileResponse)
def musician_detail(musician_id: int, db: Session = Depends(get_db)):
    profile = db.scalar(musician_profiles().where(MusicianProfile.id == musician_id))
    if not profile: raise HTTPException(404, "Agrupación no encontrada")
    return musician_out(profile)


@app.post("/api/musicians/me/media", status_code=201)
def upload_media(media_type: MediaType, position: int = Query(ge=1), file: UploadFile = File(...),
                 user: User = Depends(require_role(UserRole.musician)), db: Session = Depends(get_db)):
    profile = db.scalar(select(MusicianProfile).where(MusicianProfile.user_id == user.id))
    if not profile: raise HTTPException(409, "Crea primero el perfil de la agrupación")
    maximum = {MediaType.profile_photo: 1, MediaType.photo: 5, MediaType.video: 2}[media_type]
    if position > maximum: raise HTTPException(422, f"Sólo se permiten {maximum} archivo(s) de este tipo")
    allowed = {MediaType.video: ("video/",), MediaType.photo: ("image/",), MediaType.profile_photo: ("image/",)}[media_type]
    if not file.content_type or not file.content_type.startswith(allowed): raise HTTPException(415, "Tipo de archivo no permitido")
    extension = Path(file.filename or "").suffix.lower() or (".mp4" if media_type == MediaType.video else ".jpg")
    folder = settings.upload_dir / str(profile.id); folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{media_type.value}-{position}-{uuid4().hex}{extension}"
    with target.open("wb") as output: shutil.copyfileobj(file.file, output)
    existing = db.scalar(select(Media).where(Media.musician_id == profile.id, Media.media_type == media_type, Media.position == position))
    public_url = f"/uploads/{profile.id}/{target.name}"
    if existing:
        old = settings.upload_dir / str(profile.id) / Path(existing.url).name
        if old.exists(): old.unlink()
        existing.url = public_url
    else:
        existing = Media(musician_id=profile.id, media_type=media_type, position=position, url=public_url); db.add(existing)
    db.commit(); db.refresh(existing)
    return {"id": existing.id, "media_type": existing.media_type, "position": existing.position, "url": existing.url}
