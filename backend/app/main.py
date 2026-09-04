import json
import shutil
from datetime import date, datetime
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, File, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from .auth import create_token, current_user, hash_password, require_role, verify_password
from .config import settings
from .database import Base, engine, get_db
from .models import (AvatarChoice, Booking, ChatMessage, ClientAvatar,
                     ClientProfile, Media, MediaType, MusicianBusyDate,
                     MusicianProfile, User, UserRole)
from .schemas import (AvailabilityResponse, AvatarChoiceUpdate, BookingCreate,
                      BookingResponse, BusyDateResponse, BusyDateUpdate,
                      ChatMessageCreate, ChatMessageResponse,
                      ClientProfileResponse, ClientProfileUpsert, LoginRequest,
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


def booking_query():
    return select(Booking).options(
        selectinload(Booking.client).selectinload(ClientProfile.user),
        selectinload(Booking.musician),
    )


def booking_out(booking: Booking) -> BookingResponse:
    chat_active, chat_status = booking_chat_state(booking)
    return BookingResponse(
        id=booking.id,
        musician_id=booking.musician_id,
        group_name=booking.musician.group_name,
        client_id=booking.client_id,
        client_name=booking.client.name,
        client_email=booking.client.user.email,
        event_date=booking.event_date,
        venue=booking.venue,
        start_time=booking.start_time,
        end_time=booking.end_time,
        created_at=booking.created_at,
        chat_active=chat_active,
        chat_status=chat_status,
    )


def booking_chat_state(booking: Booking) -> tuple[bool, str]:
    timezone = ZoneInfo(settings.event_timezone)
    now = datetime.now(timezone)
    starts_at = datetime.combine(
        booking.event_date, booking.start_time, tzinfo=timezone
    )
    ends_at = datetime.combine(
        booking.event_date, booking.end_time, tzinfo=timezone
    )
    if now < starts_at:
        return False, (
            "El chat se activará durante el evento, de "
            f"{booking.start_time.strftime('%H:%M')} a "
            f"{booking.end_time.strftime('%H:%M')}."
        )
    if now >= ends_at:
        return False, "El chat terminó al finalizar el horario del evento."
    return True, "Chat activo durante el horario del evento."


def require_active_chat(booking: Booking):
    active, status = booking_chat_state(booking)
    if not active:
        raise HTTPException(403, status)


def accessible_booking(booking_id: int, user: User, db: Session) -> Booking:
    booking = db.scalar(booking_query().where(Booking.id == booking_id))
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    participant = (
        booking.client.user_id == user.id
        or booking.musician.user_id == user.id
    )
    if not participant:
        raise HTTPException(403, "Este chat pertenece a otra contratación")
    return booking


def chat_message_out(
    message: ChatMessage, booking: Booking, viewer: User
) -> ChatMessageResponse:
    sent_by_client = message.sender_user_id == booking.client.user_id
    return ChatMessageResponse(
        id=message.id,
        booking_id=message.booking_id,
        sender_user_id=message.sender_user_id,
        sender_role=UserRole.client if sent_by_client else UserRole.musician,
        sender_name=(
            booking.client.name if sent_by_client else booking.musician.group_name
        ),
        text=message.text,
        created_at=message.created_at,
        mine=message.sender_user_id == viewer.id,
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/auth/register", response_model=TokenResponse, status_code=201)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    email = str(data.email).strip().lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "El correo ya está registrado")
    user = User(email=email, password_hash=hash_password(data.password), role=data.role)
    db.add(user); db.commit(); db.refresh(user)
    return TokenResponse(access_token=create_token(user))


@app.post("/api/auth/login", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    email = str(data.email).strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    if not user or not user.is_active or not verify_password(data.password, user.password_hash):
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


@app.get("/api/musicians/me/busy-dates", response_model=list[BusyDateResponse])
def get_my_busy_dates(
    user: User = Depends(require_role(UserRole.musician)),
    db: Session = Depends(get_db),
):
    profile = db.scalar(
        select(MusicianProfile).where(MusicianProfile.user_id == user.id)
    )
    if not profile:
        raise HTTPException(409, "Crea primero el perfil de la agrupación")
    dates = db.scalars(
        select(MusicianBusyDate)
        .where(MusicianBusyDate.musician_id == profile.id)
        .order_by(MusicianBusyDate.busy_date)
    ).all()
    return [BusyDateResponse(date=item.busy_date, busy=True) for item in dates]


@app.put(
    "/api/musicians/me/busy-dates/{selected_date}",
    response_model=BusyDateResponse,
)
def set_my_busy_date(
    selected_date: date,
    data: BusyDateUpdate,
    user: User = Depends(require_role(UserRole.musician)),
    db: Session = Depends(get_db),
):
    if selected_date < date.today():
        raise HTTPException(422, "No puedes modificar fechas anteriores")
    profile = db.scalar(
        select(MusicianProfile).where(MusicianProfile.user_id == user.id)
    )
    if not profile:
        raise HTTPException(409, "Crea primero el perfil de la agrupación")
    existing = db.scalar(
        select(MusicianBusyDate).where(
            MusicianBusyDate.musician_id == profile.id,
            MusicianBusyDate.busy_date == selected_date,
        )
    )
    if not data.busy:
        booking = db.scalar(
            select(Booking).where(
                Booking.musician_id == profile.id,
                Booking.event_date == selected_date,
            )
        )
        if booking:
            raise HTTPException(409, "No puedes liberar una fecha contratada")
    if data.busy and not existing:
        db.add(
            MusicianBusyDate(
                musician_id=profile.id,
                busy_date=selected_date,
            )
        )
    elif not data.busy and existing:
        db.delete(existing)
    db.commit()
    return BusyDateResponse(date=selected_date, busy=data.busy)


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


@app.get(
    "/api/musicians/{musician_id}/availability",
    response_model=AvailabilityResponse,
)
def musician_availability(
    musician_id: int,
    selected_date: date = Query(alias="date"),
    user: User = Depends(require_role(UserRole.client)),
    db: Session = Depends(get_db),
):
    profile = db.get(MusicianProfile, musician_id)
    if not profile:
        raise HTTPException(404, "Agrupación no encontrada")
    busy = db.scalar(
        select(MusicianBusyDate).where(
            MusicianBusyDate.musician_id == musician_id,
            MusicianBusyDate.busy_date == selected_date,
        )
    )
    available = busy is None
    message = (
        "La agrupación está disponible en esta fecha."
        if available
        else "Lo sentimos, el grupo ya tiene compromiso ese día."
    )
    return AvailabilityResponse(
        date=selected_date,
        available=available,
        message=message,
    )


@app.post("/api/bookings", response_model=BookingResponse, status_code=201)
def create_booking(
    data: BookingCreate,
    user: User = Depends(require_role(UserRole.client)),
    db: Session = Depends(get_db),
):
    if data.event_date < date.today():
        raise HTTPException(422, "La fecha del evento debe ser futura")
    client = db.scalar(
        select(ClientProfile).where(ClientProfile.user_id == user.id)
    )
    if not client:
        raise HTTPException(409, "Crea primero tu perfil de cliente")
    musician = db.get(MusicianProfile, data.musician_id)
    if not musician:
        raise HTTPException(404, "Agrupación no encontrada")
    busy = db.scalar(
        select(MusicianBusyDate).where(
            MusicianBusyDate.musician_id == musician.id,
            MusicianBusyDate.busy_date == data.event_date,
        )
    )
    if busy:
        raise HTTPException(
            409, "Lo sentimos, el grupo ya tiene compromiso ese día."
        )
    booking = Booking(
        musician_id=musician.id,
        client_id=client.id,
        event_date=data.event_date,
        venue=data.venue.strip(),
        start_time=data.start_time,
        end_time=data.end_time,
    )
    db.add(booking)
    db.add(
        MusicianBusyDate(
            musician_id=musician.id,
            busy_date=data.event_date,
        )
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            409, "Lo sentimos, el grupo ya tiene compromiso ese día."
        )
    saved = db.scalar(booking_query().where(Booking.id == booking.id))
    return booking_out(saved)


@app.get(
    "/api/musicians/me/bookings",
    response_model=list[BookingResponse],
)
def get_my_bookings(
    user: User = Depends(require_role(UserRole.musician)),
    db: Session = Depends(get_db),
):
    profile = db.scalar(
        select(MusicianProfile).where(MusicianProfile.user_id == user.id)
    )
    if not profile:
        raise HTTPException(409, "Crea primero el perfil de la agrupación")
    bookings = db.scalars(
        booking_query()
        .where(Booking.musician_id == profile.id)
        .order_by(Booking.event_date, Booking.start_time)
    ).all()
    return [booking_out(item) for item in bookings]


@app.get(
    "/api/clients/me/bookings",
    response_model=list[BookingResponse],
)
def get_client_bookings(
    user: User = Depends(require_role(UserRole.client)),
    db: Session = Depends(get_db),
):
    profile = db.scalar(
        select(ClientProfile).where(ClientProfile.user_id == user.id)
    )
    if not profile:
        raise HTTPException(409, "Crea primero tu perfil de cliente")
    bookings = db.scalars(
        booking_query()
        .where(Booking.client_id == profile.id)
        .order_by(Booking.event_date, Booking.start_time)
    ).all()
    return [booking_out(item) for item in bookings]


@app.get(
    "/api/bookings/{booking_id}/messages",
    response_model=list[ChatMessageResponse],
)
def get_booking_messages(
    booking_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = accessible_booking(booking_id, user, db)
    require_active_chat(booking)
    messages = db.scalars(
        select(ChatMessage)
        .where(ChatMessage.booking_id == booking.id)
        .order_by(ChatMessage.created_at, ChatMessage.id)
    ).all()
    return [chat_message_out(item, booking, user) for item in messages]


@app.post(
    "/api/bookings/{booking_id}/messages",
    response_model=ChatMessageResponse,
    status_code=201,
)
def send_booking_message(
    booking_id: int,
    data: ChatMessageCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = accessible_booking(booking_id, user, db)
    require_active_chat(booking)
    message = ChatMessage(
        booking_id=booking.id,
        sender_user_id=user.id,
        text=data.text.strip(),
    )
    if not message.text:
        raise HTTPException(422, "Escribe un mensaje")
    db.add(message)
    db.commit()
    db.refresh(message)
    return chat_message_out(message, booking, user)


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
