import json
import asyncio
import hashlib
import hmac
import logging
import mimetypes
import re
import secrets
import smtplib
import ssl
import base64
import jwt
import stripe
import time
from collections import defaultdict, deque
from threading import Lock
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from email.message import EmailMessage
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo

from cryptography.fernet import Fernet

from fastapi import Depends, FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import case, func, or_, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from .auth import (create_token, current_user, hash_password, require_role,
                   verify_google_token, verify_password)
from .billing import (
    payout_release_deadline,
    release_due_payouts,
    release_musician_funds,
    router as billing_router,
    sync_connect_account,
    stripe_client_ready,
)
from .config import settings
from .database import SessionLocal, get_db
from .social import router as social_router
from .models import (AvatarChoice, Booking, BookingReview, ChatMessage, ClientAvatar,
                     ClientProfile, Media, MediaType, MusicianBusyDate,
                     MusicianProfile, MusicianPayoutDestination, PasswordResetCode, RulesAcceptance,
                     User, UserRole)
from .schemas import (AdminPayoutAction, AvailabilityResponse, AvatarChoiceUpdate, BookingCreate,
                      BookingDisputeCreate,
                      BookingResponse, BusyDateResponse, BusyDateUpdate,
                      BookingReviewCreate, BookingReviewResponse,
                      ChatMessageCreate, ChatMessageResponse,
                      EventChatAccessResponse, EventChatInviteResponse,
                      ClientProfileResponse, ClientProfileUpsert, LoginRequest,
                      MusicianProfileResponse, MusicianProfileUpsert,
                      PayoutDestinationResponse, PayoutDestinationUpsert,
                      StripeConnectAccountUpdate,
                      GoogleAuthRequest, PasswordResetConfirm, PasswordResetRequest,
                      PasswordResetRequestResponse, RegisterRequest,
                      RulesAcceptanceResponse, TokenResponse, UserResponse)

settings.upload_dir.mkdir(parents=True, exist_ok=True)
mimetypes.add_type("application/vnd.android.package-archive", ".apk")

app = FastAPI(
    title=settings.app_name,
    version="0.2.0",
    docs_url=None if settings.app_env == "production" else "/docs",
    redoc_url=None if settings.app_env == "production" else "/redoc",
)


CLIENT_PRICE_MULTIPLIER = Decimal("1.071")
CLIENT_SURCHARGE_RATE = Decimal("0.071")
CLIENT_PLATFORM_FEE_RATE = Decimal("0.03")
MUSICIAN_NET_RATE = Decimal("0.97")
app.include_router(billing_router)
app.include_router(social_router)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")


@app.middleware("http")
async def security_headers(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if request.url.path == "/api/billing/webhooks/stripe":
        maximum_body = settings.max_stripe_webhook_bytes
    elif request.url.path in {
        "/api/clients/me/avatar", "/api/musicians/me/media",
    }:
        maximum_body = settings.max_video_bytes + 1024 * 1024
    else:
        maximum_body = settings.max_request_body_bytes
    if content_length:
        try:
            if int(content_length) > maximum_body:
                return JSONResponse(
                    status_code=413,
                    content={"detail": "La solicitud supera el tamaño permitido"},
                )
        except ValueError:
            return JSONResponse(
                status_code=400, content={"detail": "Content-Length inválido"}
            )
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Cache-Control"] = "no-store" if request.url.path.startswith("/api/") else "no-cache"
    if settings.app_env in {"staging", "production"}:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response

GROUP_RULES_TYPE = "musician_group_rules"
GROUP_RULES_VERSION = "GARIBALDY_GROUP_RULES_V1"
logger = logging.getLogger(__name__)
_rate_limit_events: dict[str, deque[float]] = defaultdict(deque)
_rate_limit_lock = Lock()


async def automatic_payout_release_loop() -> None:
    while True:
        try:
            with SessionLocal() as db:
                release_due_payouts(db)
        except Exception:
            logger.exception("Falló la revisión automática de pagos por liberar")
        await asyncio.sleep(settings.payout_release_scan_seconds)


@app.on_event("startup")
async def start_automatic_payout_release() -> None:
    app.state.payout_release_task = asyncio.create_task(
        automatic_payout_release_loop()
    )


@app.on_event("shutdown")
async def stop_automatic_payout_release() -> None:
    task = getattr(app.state, "payout_release_task", None)
    if task:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


def request_client_ip(request: Request) -> str:
    if settings.trust_cloudflare_headers:
        cloudflare_ip = request.headers.get("cf-connecting-ip", "").strip()
        if cloudflare_ip:
            return cloudflare_ip
    return request.client.host if request.client else "unknown"


def enforce_rate_limit(
    request: Request, scope: str, *, limit: int, window_seconds: int,
    identity: str = "",
) -> None:
    keys = [f"{scope}:ip:{request_client_ip(request)}"]
    normalized_identity = identity.strip().lower()
    if normalized_identity:
        keys.append(f"{scope}:identity:{normalized_identity}")
    if settings.app_env == "test":
        keys = keys[1:] or keys
    now = time.monotonic()
    cutoff = now - window_seconds
    with _rate_limit_lock:
        buckets = []
        for key in keys:
            events = _rate_limit_events[key]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= limit:
                raise HTTPException(429, "Demasiados intentos. Inténtalo más tarde.")
            buckets.append(events)
        for events in buckets:
            events.append(now)


def validate_upload_signature(target: Path, content_type: str) -> None:
    with target.open("rb") as uploaded:
        header = uploaded.read(16)
    valid = {
        "image/jpeg": header.startswith(b"\xff\xd8\xff"),
        "image/png": header.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/webp": header.startswith(b"RIFF") and header[8:12] == b"WEBP",
        "video/mp4": len(header) >= 12 and header[4:8] == b"ftyp",
        "video/webm": header.startswith(b"\x1aE\xdf\xa3"),
    }.get(content_type, False)
    if not valid:
        target.unlink(missing_ok=True)
        raise HTTPException(415, "El contenido del archivo no coincide con su tipo")


def payout_cipher() -> Fernet:
    key = hashlib.sha256(settings.secret_key.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(key))


def valid_clabe(value: str) -> bool:
    if len(value) != 18 or not value.isdigit():
        return False
    weights = (3, 7, 1)
    total = sum(int(digit) * weights[index % 3]
                for index, digit in enumerate(value[:17]))
    return (10 - total % 10) % 10 == int(value[-1])


def valid_card_number(value: str) -> bool:
    if len(value) != 16 or not value.isdigit():
        return False
    total = 0
    for index, digit in enumerate(reversed(value)):
        number = int(digit)
        if index % 2 == 1:
            number *= 2
            if number > 9:
                number -= 9
        total += number
    return total % 10 == 0


def csv(values: list[str]) -> str:
    return json.dumps([v.strip() for v in values if v.strip()], ensure_ascii=False)


def values(raw: str) -> list[str]:
    try:
        return json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []


def booking_price_snapshot(hourly_rate: float, start_time, end_time) -> dict:
    start_minutes = start_time.hour * 60 + start_time.minute
    end_minutes = end_time.hour * 60 + end_time.minute
    duration_minutes = end_minutes - start_minutes
    hourly_rate_cents = int(
        (Decimal(str(hourly_rate)) * 100).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
    )
    subtotal_cents = int(
        (Decimal(hourly_rate_cents) * Decimal(duration_minutes) / Decimal(60))
        .quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    )
    service_fee_cents = int(
        (Decimal(subtotal_cents) * CLIENT_SURCHARGE_RATE).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
    )
    musician_earnings_cents = int(
        (Decimal(subtotal_cents) * MUSICIAN_NET_RATE).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
    )
    client_platform_fee_cents = int(
        (Decimal(subtotal_cents) * CLIENT_PLATFORM_FEE_RATE).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
    )
    musician_platform_fee_cents = subtotal_cents - musician_earnings_cents
    platform_fee_cents = client_platform_fee_cents + musician_platform_fee_cents
    stripe_fee_estimate_cents = service_fee_cents - client_platform_fee_cents
    return {
        "hourly_rate_cents": hourly_rate_cents,
        "duration_minutes": duration_minutes,
        "subtotal_cents": subtotal_cents,
        "service_fee_cents": service_fee_cents,
        "total_cents": subtotal_cents + service_fee_cents,
        "musician_earnings_cents": musician_earnings_cents,
        "platform_fee_cents": platform_fee_cents,
        "stripe_fee_estimate_cents": stripe_fee_estimate_cents,
        "currency": "mxn",
        "payment_status": "pending",
        "payout_status": "awaiting_payment",
    }


def normalize_phone(value: str) -> str:
    phone = re.sub(r"\D", "", value)
    if len(phone) < 10 or len(phone) > 15:
        raise HTTPException(422, "El número celular debe tener entre 10 y 15 dígitos")
    return phone


def find_user(identifier: str, db: Session) -> User | None:
    value = identifier.strip().lower()
    if "@" in value:
        return db.scalar(select(User).where(User.email == value))
    try:
        phone = normalize_phone(value)
    except HTTPException:
        return None
    return db.scalar(select(User).where(User.phone == phone))


def reset_code_hash(user_id: int, code: str) -> str:
    return hashlib.sha256(
        f"{settings.secret_key}:{user_id}:{code}".encode()
    ).hexdigest()


def deliver_password_reset_code(user: User, code: str) -> None:
    if settings.expose_password_reset_code:
        return
    if not user.email or not settings.smtp_host or not settings.smtp_from_email:
        raise HTTPException(503, "La recuperación de contraseña no está disponible")
    message = EmailMessage()
    message["Subject"] = "Código para recuperar tu cuenta Balam"
    message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    message["To"] = user.email
    message.set_content(
        "Recibimos una solicitud para cambiar tu contraseña de Balam.\n\n"
        f"Tu código es: {code}\n\n"
        "El código vence en 15 minutos. Si no solicitaste este cambio, "
        "ignora este mensaje."
    )
    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
            if settings.smtp_starttls:
                smtp.starttls(context=ssl.create_default_context())
            if settings.smtp_username:
                smtp.login(settings.smtp_username, settings.smtp_password or "")
            smtp.send_message(message)
    except (OSError, smtplib.SMTPException) as exc:
        raise HTTPException(503, "No pudimos enviar el código de recuperación") from exc


CONTENT_TYPE_EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "video/mp4": ".mp4",
    "video/webm": ".webm",
}


def save_upload(file: UploadFile, target: Path, maximum_bytes: int) -> None:
    written = 0
    try:
        with target.open("wb") as output:
            while chunk := file.file.read(1024 * 1024):
                written += len(chunk)
                if written > maximum_bytes:
                    raise HTTPException(413, "El archivo supera el tamaño permitido")
                output.write(chunk)
    except Exception:
        target.unlink(missing_ok=True)
        raise


def current_group_rules_acceptance(user_id: int, db: Session):
    return db.scalar(select(RulesAcceptance).where(
        RulesAcceptance.user_id == user_id,
        RulesAcceptance.rules_type == GROUP_RULES_TYPE,
        RulesAcceptance.rules_version == GROUP_RULES_VERSION,
        RulesAcceptance.accepted.is_(True),
    ))


def client_profiles():
    return select(ClientProfile).options(
        selectinload(ClientProfile.avatar),
        selectinload(ClientProfile.user).selectinload(User.avatar_choice),
    )


def musician_profiles():
    return select(MusicianProfile).options(
        selectinload(MusicianProfile.media),
        selectinload(MusicianProfile.user).selectinload(User.avatar_choice),
        selectinload(MusicianProfile.reviews),
        selectinload(MusicianProfile.payout_destination),
    )


def payout_eligible(profile: MusicianProfile, db: Session) -> bool:
    # Configuring deposits before the first event avoids holding an approved payment.
    return True


def payout_out(
    profile: MusicianProfile, db: Session
) -> PayoutDestinationResponse:
    destination = profile.payout_destination
    requirements = []
    if destination and destination.stripe_requirements_due:
        try:
            requirements = json.loads(destination.stripe_requirements_due)
        except (TypeError, json.JSONDecodeError):
            requirements = []
    if not destination or not destination.stripe_connected_account_id:
        onboarding_status = "not_started"
    elif destination.stripe_payouts_enabled:
        onboarding_status = "ready"
    elif destination.stripe_details_submitted:
        onboarding_status = "pending_verification"
    else:
        onboarding_status = "incomplete"
    return PayoutDestinationResponse(
        eligible=payout_eligible(profile, db),
        configured=bool(destination and destination.stripe_connected_account_id),
        destination_type=(destination.destination_type if destination else None),
        last4=(destination.last4 if destination else None),
        updated_at=(destination.updated_at if destination else None),
        stripe_connect_ready=bool(destination and destination.stripe_payouts_enabled),
        onboarding_status=onboarding_status,
        requirements_due=requirements,
        last_payout_status=(destination.last_stripe_payout_status if destination else None),
        last_payout_error=(destination.last_stripe_payout_error if destination else None),
    )


def musician_out(
    profile: MusicianProfile, *, customer_price: bool = False
) -> MusicianProfileResponse:
    choice = profile.user.avatar_choice
    hourly_rate = Decimal(str(profile.hourly_rate))
    if customer_price:
        hourly_rate = (hourly_rate * CLIENT_PRICE_MULTIPLIER).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
    return MusicianProfileResponse(
        id=profile.id, user_id=profile.user_id, contact_name=profile.contact_name,
        city=profile.city, municipality=profile.municipality, state=profile.state,
        group_name=profile.group_name, group_type=profile.group_type,
        musical_style=profile.musical_style, card_theme=profile.card_theme,
        member_count=profile.member_count,
        hourly_rate=float(hourly_rate),
        minimum_booking_hours=profile.minimum_booking_hours,
        includes_sound=profile.includes_sound,
        subwoofer_count=profile.subwoofer_count, mid_speaker_count=profile.mid_speaker_count,
        equipment_brands=values(profile.equipment_brands), audience_capacity=profile.audience_capacity,
        description=profile.description, media=profile.media,
        avatar_preset=choice.preset if choice else "jaguar_guitar",
        avatar_color=choice.color if choice else "#8B5CF6",
        avatar_mode=choice.mode if choice else "photo",
        rating=(round(sum(r.overall_score for r in profile.reviews) / len(profile.reviews), 2)
                if profile.reviews else None),
        review_count=len(profile.reviews),
        profile_complete=bool(profile.admin_phone and profile.city
                              and profile.municipality and profile.state),
        admin_phone_saved=bool(profile.admin_phone),
    )


def client_out(profile: ClientProfile) -> ClientProfileResponse:
    choice = profile.user.avatar_choice
    return ClientProfileResponse(
        id=profile.id, user_id=profile.user_id, name=profile.name,
        city=profile.city, municipality=profile.municipality, state=profile.state,
        musical_tastes=values(profile.musical_tastes),
        favorite_groups=values(profile.favorite_groups),
        avatar_url=profile.avatar.url if profile.avatar else None,
        avatar_preset=choice.preset if choice else "jaguar_guitar",
        avatar_color=choice.color if choice else "#8B5CF6",
        avatar_mode=choice.mode if choice else "photo",
        profile_complete=bool(profile.admin_phone and profile.city
                              and profile.municipality and profile.state),
        admin_phone_saved=bool(profile.admin_phone),
    )


def booking_query():
    return select(Booking).options(
        selectinload(Booking.client).selectinload(ClientProfile.user),
        selectinload(Booking.musician),
        selectinload(Booking.review),
    )


def booking_out(
    booking: Booking, *, include_private_recommendation: bool = False
) -> BookingResponse:
    chat_active, chat_status = booking_chat_state(booking)
    can_review, review_status = booking_review_state(booking)
    return BookingResponse(
        id=booking.id,
        musician_id=booking.musician_id,
        group_name=booking.musician.group_name,
        client_id=booking.client_id,
        client_name=booking.client.name,
        client_email=(booking.client.user.phone or booking.client.user.email),
        event_date=booking.event_date,
        venue=booking.venue,
        start_time=booking.start_time,
        end_time=booking.end_time,
        hourly_rate_cents=booking.hourly_rate_cents,
        duration_minutes=booking.duration_minutes,
        subtotal_cents=booking.subtotal_cents,
        service_fee_cents=booking.service_fee_cents,
        total_cents=booking.total_cents,
        musician_earnings_cents=booking.musician_earnings_cents,
        platform_fee_cents=booking.platform_fee_cents,
        stripe_fee_estimate_cents=booking.stripe_fee_estimate_cents,
        currency=booking.currency,
        payment_status=booking.payment_status,
        payout_status=booking.payout_status,
        dispute_reason=(booking.dispute_reason if include_private_recommendation else None),
        stripe_transfer_id=booking.stripe_transfer_id,
        payout_error=(booking.payout_error if include_private_recommendation else None),
        created_at=booking.created_at,
        chat_active=chat_active,
        chat_status=chat_status,
        can_review=can_review,
        review_status=review_status,
        review_score=booking.review.overall_score if booking.review else None,
        review_recommendation=(
            booking.review.recommendation
            if booking.review and include_private_recommendation
            else None
        ),
        event_finished=booking_event_finished(booking),
        payout_release_deadline=payout_release_deadline(booking),
        can_release_payment=(
            booking.payment_status == "paid"
            and booking_event_finished(booking)
            and booking.payout_status == "musician_funds_held"
        ),
        can_dispute_payment=(
            booking.payment_status == "paid"
            and booking_event_finished(booking)
            and booking_payout_window_open(booking)
            and booking.payout_status == "musician_funds_held"
        ),
        is_new_sale=(
            datetime.now(timezone.utc).replace(tzinfo=None) - booking.created_at
            < timedelta(hours=24)
        ),
    )


def booking_event_finished(booking: Booking) -> bool:
    timezone = ZoneInfo(settings.event_timezone)
    ends_at = datetime.combine(booking.event_date, booking.end_time, tzinfo=timezone)
    return datetime.now(timezone) >= ends_at


def booking_payout_window_open(booking: Booking) -> bool:
    event_timezone = ZoneInfo(settings.event_timezone)
    return datetime.now(event_timezone) < payout_release_deadline(booking)


def booking_review_state(booking: Booking) -> tuple[bool, str]:
    if booking.review:
        return False, "Ya calificaste este evento."
    if not booking_event_finished(booking):
        return False, "Podrás calificar justo después de que termine el evento."
    return True, "Tu opinión ayudará a la agrupación a seguir mejorando."


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
        or user.role == UserRole.admin
    )
    if not participant:
        raise HTTPException(403, "Este chat pertenece a otra contratación")
    return booking


def chat_message_out(
    message: ChatMessage, booking: Booking, viewer: User
) -> ChatMessageResponse:
    sent_by_client = message.sender_user_id == booking.client.user_id
    sent_by_musician = message.sender_user_id == booking.musician.user_id
    sender_role = (
        UserRole.client if sent_by_client else
        UserRole.musician if sent_by_musician else message.sender.role
    )
    sender_name = (
        booking.client.name if sent_by_client else
        booking.musician.group_name if sent_by_musician else
        "Administración Garibaldy" if message.sender.role == UserRole.admin else
        message.sender.client_profile.name
        if message.sender.client_profile else
        message.sender.musician_profile.group_name
        if message.sender.musician_profile else
        message.sender.email.split("@", 1)[0]
    )
    return ChatMessageResponse(
        id=message.id,
        booking_id=message.booking_id,
        sender_user_id=message.sender_user_id,
        sender_role=sender_role,
        sender_name=sender_name,
        text=message.text,
        created_at=message.created_at,
        mine=message.sender_user_id == viewer.id,
    )


def event_chat_ends_at(booking: Booking) -> datetime:
    return datetime.combine(
        booking.event_date,
        booking.end_time,
        tzinfo=ZoneInfo(settings.event_timezone),
    )


def booking_from_event_chat_token(token: str, db: Session) -> Booking:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        if payload.get("scope") != "event_chat":
            raise ValueError
        booking_id = int(payload["booking_id"])
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
        raise HTTPException(401, "La invitación del evento no es válida o ya expiró")
    booking = db.scalar(booking_query().where(Booking.id == booking_id))
    if not booking:
        raise HTTPException(404, "El evento ya no está disponible")
    require_active_chat(booking)
    return booking


@app.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.get("/downloads/garibaldi.apk", include_in_schema=False)
def download_local_android_build():
    apk = settings.upload_dir / "Garibaldi-red-local.apk"
    if not apk.is_file():
        raise HTTPException(404, "La APK local todavía no está disponible")
    return FileResponse(
        apk,
        media_type="application/vnd.android.package-archive",
        filename="Garibaldi-red-local.apk",
    )


@app.post("/api/auth/register", response_model=TokenResponse, status_code=201)
def register(data: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    enforce_rate_limit(
        request, "register", limit=settings.auth_rate_limit_per_minute,
        window_seconds=60, identity=str(data.email),
    )
    if data.role == UserRole.admin:
        raise HTTPException(403, "El rol administrador no admite registro público")
    email = str(data.email).strip().lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "El correo ya está registrado")
    user = User(
        email=email,
        password_hash=hash_password(data.password), role=data.role,
    )
    db.add(user); db.commit(); db.refresh(user)
    return TokenResponse(access_token=create_token(user))


@app.post("/api/auth/login", response_model=TokenResponse)
def login(data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    enforce_rate_limit(
        request, "login", limit=settings.auth_rate_limit_per_minute,
        window_seconds=60, identity=data.identifier or "",
    )
    user = find_user(data.identifier or "", db)
    if not user or not user.is_active or not verify_password(data.password, user.password_hash):
        raise HTTPException(401, "Correo, celular o contraseña incorrectos")
    return TokenResponse(access_token=create_token(user))


@app.post("/api/auth/google", response_model=TokenResponse)
def google_auth(data: GoogleAuthRequest, request: Request, db: Session = Depends(get_db)):
    enforce_rate_limit(
        request, "google-auth", limit=settings.auth_rate_limit_per_minute,
        window_seconds=60,
    )
    claims = verify_google_token(data.id_token)
    subject = str(claims["sub"])
    email = str(claims["email"]).strip().lower()

    user = db.scalar(select(User).where(User.google_subject == subject))
    if user:
        if not user.is_active:
            raise HTTPException(403, "Esta cuenta está desactivada")
        if data.create_account and data.role and data.role != user.role:
            if user.client_profile or user.musician_profile:
                raise HTTPException(
                    409,
                    "Esta cuenta ya tiene un perfil Balam y no puede cambiar de modalidad",
                )
            user.role = data.role
            db.commit()
            db.refresh(user)
        return TokenResponse(access_token=create_token(user))

    email_user = db.scalar(select(User).where(User.email == email))
    if email_user:
        raise HTTPException(
            409,
            "Este correo ya tiene una cuenta Balam. Entra con tu contraseña para vincular Google.",
        )
    if not data.create_account:
        raise HTTPException(
            404,
            "Aún no existe una cuenta Balam con este Google. Elige Crear una cuenta.",
        )

    user = User(
        email=email,
        password_hash=hash_password(secrets.token_urlsafe(32)),
        google_subject=subject,
        role=data.role,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "La cuenta de Google ya está registrada")
    db.refresh(user)
    return TokenResponse(access_token=create_token(user))


@app.post(
    "/api/auth/password-reset/request",
    response_model=PasswordResetRequestResponse,
)
def request_password_reset(
    data: PasswordResetRequest, request: Request, db: Session = Depends(get_db)
):
    enforce_rate_limit(
        request, "password-reset-request",
        limit=settings.password_reset_rate_limit_per_hour,
        window_seconds=3600, identity=str(data.email),
    )
    email = str(data.email).strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    message = "Si la cuenta existe, generamos un código válido durante 15 minutos."
    if not user:
        return PasswordResetRequestResponse(message=message)
    active_codes = db.scalars(select(PasswordResetCode).where(
        PasswordResetCode.user_id == user.id,
        PasswordResetCode.used.is_(False),
    )).all()
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if any(item.created_at > now - timedelta(seconds=60) for item in active_codes):
        return PasswordResetRequestResponse(message=message)
    for previous in active_codes:
        previous.used = True
    code = f"{secrets.randbelow(1_000_000):06d}"
    reset = PasswordResetCode(
        user_id=user.id,
        code_hash=reset_code_hash(user.id, code),
        expires_at=now + timedelta(minutes=15),
    )
    db.add(reset)
    db.commit()
    try:
        deliver_password_reset_code(user, code)
    except HTTPException:
        reset.used = True
        db.commit()
        logger.warning("Password reset delivery failed; code invalidated")
        return PasswordResetRequestResponse(message=message)
    return PasswordResetRequestResponse(
        message=message,
        dev_code=code if settings.expose_password_reset_code else None,
    )


@app.post("/api/auth/password-reset/confirm")
def confirm_password_reset(
    data: PasswordResetConfirm, request: Request, db: Session = Depends(get_db)
):
    enforce_rate_limit(
        request, "password-reset-confirm",
        limit=settings.auth_rate_limit_per_minute,
        window_seconds=60, identity=str(data.email),
    )
    email = str(data.email).strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    if not user:
        raise HTTPException(400, "Código inválido o vencido")
    reset = db.scalar(select(PasswordResetCode).where(
        PasswordResetCode.user_id == user.id,
        PasswordResetCode.used.is_(False),
    ).order_by(PasswordResetCode.created_at.desc()))
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    valid = (
        reset is not None
        and reset.expires_at > now
        and reset.attempts < 5
        and hmac.compare_digest(reset.code_hash, reset_code_hash(user.id, data.code))
    )
    if not valid:
        if reset:
            reset.attempts += 1
            if reset.attempts >= 5:
                reset.used = True
            db.commit()
        raise HTTPException(400, "Código inválido o vencido")
    user.password_hash = hash_password(data.new_password)
    user.token_version += 1
    reset.used = True
    db.commit()
    return {"message": "Tu contraseña fue actualizada correctamente."}


@app.get("/api/users/me", response_model=UserResponse)
def me(user: User = Depends(current_user)):
    return {
        "id": user.id,
        "email": None if user.phone else user.email,
        "phone": user.phone,
        "role": user.role,
        "is_active": user.is_active,
        "created_at": user.created_at,
    }


@app.get("/api/admin/clients")
def admin_clients(
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    profiles = db.scalars(client_profiles().order_by(ClientProfile.id.desc())).all()
    return [{
        "id": profile.id,
        "user_id": profile.user_id,
        "name": profile.name,
        "account_email": None if profile.user.phone else profile.user.email,
        "account_phone": profile.user.phone,
        "admin_phone": profile.admin_phone,
        "city": profile.city,
        "municipality": profile.municipality,
        "state": profile.state,
        "musical_tastes": values(profile.musical_tastes),
        "favorite_groups": values(profile.favorite_groups),
        "is_active": profile.user.is_active,
        "created_at": profile.user.created_at,
    } for profile in profiles]


@app.get("/api/admin/groups")
def admin_groups(
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    profiles = db.scalars(musician_profiles().order_by(MusicianProfile.id.desc())).all()
    return [{
        **musician_out(profile).model_dump(),
        "account_email": None if profile.user.phone else profile.user.email,
        "account_phone": profile.user.phone,
        "admin_phone": profile.admin_phone,
        "deposit_account_type": (
            profile.payout_destination.destination_type
            if profile.payout_destination else None
        ),
        "deposit_account": (
            payout_cipher().decrypt(
                profile.payout_destination.encrypted_number.encode("ascii")
            ).decode("ascii") if profile.payout_destination else None
        ),
        "stripe_connected_account_id": (
            profile.payout_destination.stripe_connected_account_id
            if profile.payout_destination else None
        ),
        "is_active": profile.user.is_active,
        "rules_acceptances": [{
            "rules_type": acceptance.rules_type,
            "rules_version": acceptance.rules_version,
            "accepted": acceptance.accepted,
            "accepted_at": acceptance.accepted_at,
            "group_name_snapshot": acceptance.group_name_snapshot,
        } for acceptance in db.scalars(select(RulesAcceptance).where(
            RulesAcceptance.user_id == profile.user_id
        ).order_by(RulesAcceptance.accepted_at.desc())).all()],
    } for profile in profiles]


@app.get("/api/admin/bookings", response_model=list[BookingResponse])
def admin_bookings(
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    bookings = db.scalars(
        booking_query().order_by(Booking.created_at.desc(), Booking.id.desc())
    ).all()
    return [
        booking_out(item, include_private_recommendation=True)
        for item in bookings
    ]


@app.put("/api/users/me/avatar-preset")
def set_avatar_preset(data: AvatarChoiceUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    allowed = {
        "musician_tuba_burgundy", "musician_trumpet_black", "musician_accordion_black",
        "musician_singer_black", "musician_guitar_eden", "musician_guitar_chalino",
        "musician_accordion_red",
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
        choice.preset = data.preset
        choice.color = data.color.upper()
        choice.mode = "preset"
    else:
        choice = AvatarChoice(
            user_id=user.id,
            preset=data.preset,
            color=data.color.upper(),
            mode="preset",
        )
        db.add(choice)
    db.commit(); db.refresh(choice)
    return {"preset": choice.preset, "color": choice.color, "mode": choice.mode}


@app.put("/api/clients/me", response_model=ClientProfileResponse, response_model_exclude_none=True)
def upsert_client(data: ClientProfileUpsert, user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    if not profile and not data.admin_phone:
        raise HTTPException(422, "El número celular es obligatorio para completar tu perfil")
    if not all((data.city, data.municipality, data.state)):
        raise HTTPException(422, "Completa ciudad, municipio y estado")
    admin_phone = normalize_phone(data.admin_phone) if data.admin_phone else None
    payload = data.model_dump(exclude={"musical_tastes", "favorite_groups", "admin_phone"})
    payload.update(musical_tastes=csv(data.musical_tastes), favorite_groups=csv(data.favorite_groups))
    if admin_phone:
        payload["admin_phone"] = admin_phone
    if profile:
        for key, value in payload.items(): setattr(profile, key, value)
    else:
        profile = ClientProfile(user_id=user.id, **payload); db.add(profile)
    db.commit()
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    return client_out(profile)


@app.get("/api/clients/me", response_model=ClientProfileResponse, response_model_exclude_none=True)
def get_client(user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    if not profile: raise HTTPException(404, "Completa tu perfil")
    return client_out(profile)


@app.post("/api/clients/me/avatar", status_code=201)
def upload_client_avatar(file: UploadFile = File(...),
                         user: User = Depends(require_role(UserRole.client)), db: Session = Depends(get_db)):
    profile = db.scalar(client_profiles().where(ClientProfile.user_id == user.id))
    if not profile: raise HTTPException(409, "Crea primero tu perfil de cliente")
    if file.content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise HTTPException(415, "La foto de perfil debe ser una imagen")
    extension = CONTENT_TYPE_EXTENSIONS[file.content_type]
    folder = settings.upload_dir / "clients" / str(profile.id); folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"avatar-{uuid4().hex}{extension}"
    save_upload(file, target, settings.max_image_bytes)
    validate_upload_signature(target, file.content_type)
    public_url = f"/uploads/clients/{profile.id}/{target.name}"
    if profile.avatar:
        old = settings.upload_dir / "clients" / str(profile.id) / Path(profile.avatar.url).name
        if old.exists(): old.unlink()
        profile.avatar.url = public_url
    else:
        db.add(ClientAvatar(client_id=profile.id, url=public_url))
    choice = db.scalar(select(AvatarChoice).where(AvatarChoice.user_id == user.id))
    if choice:
        choice.mode = "photo"
    else:
        db.add(AvatarChoice(user_id=user.id, mode="photo"))
    db.commit()
    return {"url": public_url}


@app.put("/api/musicians/me", response_model=MusicianProfileResponse, response_model_exclude_none=True)
def upsert_musician(data: MusicianProfileUpsert, user: User = Depends(require_role(UserRole.musician)), db: Session = Depends(get_db)):
    if not current_group_rules_acceptance(user.id, db):
        raise HTTPException(
            403, "Debes aceptar las Reglas para Agrupaciones antes de continuar"
        )
    profile = db.scalar(select(MusicianProfile).where(MusicianProfile.user_id == user.id))
    if not profile and not data.admin_phone:
        raise HTTPException(422, "El número celular es obligatorio para completar tu perfil")
    if not all((data.city, data.municipality, data.state)):
        raise HTTPException(422, "Completa ciudad, municipio y estado")
    admin_phone = normalize_phone(data.admin_phone) if data.admin_phone else None
    payload = data.model_dump(exclude={"equipment_brands", "admin_phone"}); payload["equipment_brands"] = csv(data.equipment_brands)
    if admin_phone:
        payload["admin_phone"] = admin_phone
    if profile:
        for key, value in payload.items(): setattr(profile, key, value)
    else:
        profile = MusicianProfile(user_id=user.id, **payload); db.add(profile)
    acceptance = current_group_rules_acceptance(user.id, db)
    if acceptance:
        acceptance.group_name_snapshot = data.group_name.strip()
    db.commit()
    profile = db.scalar(musician_profiles().where(MusicianProfile.user_id == user.id))
    return musician_out(profile)


@app.get("/api/musicians/me", response_model=MusicianProfileResponse, response_model_exclude_none=True)
def get_musician(user: User = Depends(require_role(UserRole.musician)), db: Session = Depends(get_db)):
    profile = db.scalar(musician_profiles().where(MusicianProfile.user_id == user.id))
    if not profile: raise HTTPException(404, "Completa tu perfil")
    return musician_out(profile)


@app.get(
    "/api/musicians/me/payout-destination",
    response_model=PayoutDestinationResponse,
    response_model_exclude_none=True,
)
def get_payout_destination(
    user: User = Depends(require_role(UserRole.musician)),
    db: Session = Depends(get_db),
):
    profile = db.scalar(musician_profiles().where(
        MusicianProfile.user_id == user.id
    ))
    if not profile:
        raise HTTPException(409, "Crea primero el perfil de la agrupación")
    return payout_out(profile, db)


@app.put(
    "/api/musicians/me/payout-destination",
    response_model=PayoutDestinationResponse,
)
def set_payout_destination(
    data: PayoutDestinationUpsert,
    user: User = Depends(require_role(UserRole.musician)),
):
    raise HTTPException(
        410,
        "Por seguridad, registra tus datos bancarios directamente en Stripe",
    )


@app.put("/api/admin/musicians/{musician_id}/stripe-connect")
def link_stripe_connect_account(
    musician_id: int,
    data: StripeConnectAccountUpdate,
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    profile = db.get(MusicianProfile, musician_id)
    if not profile:
        raise HTTPException(404, "Agrupación no encontrada")
    destination = db.scalar(select(MusicianPayoutDestination).where(
        MusicianPayoutDestination.musician_id == musician_id
    ))
    if not destination:
        raise HTTPException(409, "La agrupación aún no registra cuenta de depósito")
    stripe_client_ready()
    try:
        account = stripe.Account.retrieve(data.account_id)
    except stripe.error.StripeError as exc:
        raise HTTPException(422, "Stripe no pudo verificar la cuenta Connect") from exc
    account_data = (
        account.to_dict_recursive()
        if hasattr(account, "to_dict_recursive")
        else dict(account)
    )
    metadata = account_data.get("metadata") or {}
    if (
        account_data.get("country") != "MX"
        or account_data.get("details_submitted") is not True
        or account_data.get("payouts_enabled") is not True
        or metadata.get("balam_musician_id") != str(musician_id)
    ):
        raise HTTPException(
            422,
            "La cuenta Connect no está habilitada o no pertenece a esta agrupación",
        )
    destination.stripe_connected_account_id = data.account_id
    sync_connect_account(account, db)
    db.commit()
    return {
        "musician_id": musician_id,
        "stripe_connect_ready": True,
        "retried_transfers": 0,
        "requires_payout_approval": True,
    }


@app.get(
    "/api/musicians/me/rules",
    response_model=RulesAcceptanceResponse,
)
def get_group_rules_status(
    user: User = Depends(require_role(UserRole.musician)),
    db: Session = Depends(get_db),
):
    acceptance = current_group_rules_acceptance(user.id, db)
    profile = db.scalar(select(MusicianProfile).where(
        MusicianProfile.user_id == user.id
    ))
    return RulesAcceptanceResponse(
        rules_type=GROUP_RULES_TYPE,
        rules_version=GROUP_RULES_VERSION,
        accepted=acceptance is not None,
        accepted_at=acceptance.accepted_at if acceptance else None,
        accepted_group_name=(
            acceptance.group_name_snapshot if acceptance
            else profile.group_name if profile else None
        ),
    )


@app.post(
    "/api/musicians/me/rules/accept",
    response_model=RulesAcceptanceResponse,
)
def accept_group_rules(
    user: User = Depends(require_role(UserRole.musician)),
    db: Session = Depends(get_db),
):
    acceptance = current_group_rules_acceptance(user.id, db)
    profile = db.scalar(select(MusicianProfile).where(
        MusicianProfile.user_id == user.id
    ))
    if not acceptance:
        acceptance = RulesAcceptance(
            user_id=user.id,
            rules_type=GROUP_RULES_TYPE,
            rules_version=GROUP_RULES_VERSION,
            group_name_snapshot=profile.group_name if profile else None,
            accepted=True,
        )
        db.add(acceptance)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            acceptance = current_group_rules_acceptance(user.id, db)
        else:
            db.refresh(acceptance)
    elif profile and not acceptance.group_name_snapshot:
        acceptance.group_name_snapshot = profile.group_name
        db.commit()
        db.refresh(acceptance)
    return RulesAcceptanceResponse(
        rules_type=GROUP_RULES_TYPE,
        rules_version=GROUP_RULES_VERSION,
        accepted=True,
        accepted_at=acceptance.accepted_at,
        accepted_group_name=acceptance.group_name_snapshot,
    )


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


@app.get("/api/musicians", response_model=list[MusicianProfileResponse], response_model_exclude_none=True)
def search_musicians(q: str = "", group_type: str | None = None, musical_style: str | None = None,
                     max_hourly_rate: float | None = Query(None, ge=0), includes_sound: bool | None = None,
                     city: str | None = None, municipality: str | None = None,
                     state: str | None = None,
                     skip: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
    stmt = musician_profiles()
    if q:
        term = f"%{q}%"; stmt = stmt.where(or_(MusicianProfile.group_name.ilike(term), MusicianProfile.group_type.ilike(term), MusicianProfile.musical_style.ilike(term)))
    if group_type: stmt = stmt.where(MusicianProfile.group_type.ilike(f"%{group_type}%"))
    if musical_style: stmt = stmt.where(MusicianProfile.musical_style.ilike(f"%{musical_style}%"))
    if max_hourly_rate is not None:
        base_limit = Decimal(str(max_hourly_rate)) / CLIENT_PRICE_MULTIPLIER
        stmt = stmt.where(MusicianProfile.hourly_rate <= base_limit)
    if includes_sound is not None: stmt = stmt.where(MusicianProfile.includes_sound == includes_sound)
    if city or municipality or state:
        stmt = stmt.order_by(case(
            (func.lower(MusicianProfile.municipality) == (municipality or "").lower(), 0),
            (func.lower(MusicianProfile.city) == (city or "").lower(), 1),
            (func.lower(MusicianProfile.state) == (state or "").lower(), 2),
            else_=3,
        ))
    return [musician_out(p, customer_price=True)
            for p in db.scalars(stmt.offset(skip).limit(limit)).all()]


@app.get("/api/musicians/{musician_id}", response_model=MusicianProfileResponse, response_model_exclude_none=True)
def musician_detail(musician_id: int, db: Session = Depends(get_db)):
    profile = db.scalar(musician_profiles().where(MusicianProfile.id == musician_id))
    if not profile: raise HTTPException(404, "Agrupación no encontrada")
    return musician_out(profile, customer_price=True)


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
    if not client or not all((
        client.admin_phone, client.city, client.municipality, client.state,
    )):
        raise HTTPException(409, "Completa primero tu perfil de cliente")
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
    start_minutes = data.start_time.hour * 60 + data.start_time.minute
    end_minutes = data.end_time.hour * 60 + data.end_time.minute
    requested_minutes = end_minutes - start_minutes
    minimum_minutes = musician.minimum_booking_hours * 60
    if requested_minutes < minimum_minutes:
        raise HTTPException(
            422,
            f"Esta agrupación acepta contratos a partir de "
            f"{musician.minimum_booking_hours} horas",
        )
    booking = Booking(
        musician_id=musician.id,
        client_id=client.id,
        event_date=data.event_date,
        venue=data.venue.strip(),
        start_time=data.start_time,
        end_time=data.end_time,
        **booking_price_snapshot(
            musician.hourly_rate, data.start_time, data.end_time
        ),
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
        .order_by(Booking.created_at.desc(), Booking.id.desc())
    ).all()
    return [
        booking_out(item, include_private_recommendation=True)
        for item in bookings
    ]


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


@app.post(
    "/api/bookings/{booking_id}/review",
    response_model=BookingReviewResponse,
    status_code=201,
)
def create_booking_review(
    booking_id: int,
    data: BookingReviewCreate,
    user: User = Depends(require_role(UserRole.client)),
    db: Session = Depends(get_db),
):
    booking = db.scalar(booking_query().where(Booking.id == booking_id))
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if booking.client.user_id != user.id:
        raise HTTPException(403, "Sólo el cliente que contrató puede calificar")
    can_review, status = booking_review_state(booking)
    if not can_review:
        raise HTTPException(409 if booking.review else 403, status)
    if booking.payment_status != "paid":
        raise HTTPException(409, "El pago debe estar confirmado antes de calificar")
    if booking.payout_status == "disputed":
        raise HTTPException(409, "La liberación está detenida por una disputa")
    recommendation = data.recommendation.strip()
    if len(recommendation) < 3:
        raise HTTPException(422, "Deja un consejo o recomendación amable")
    service_average = sum((
        data.agreed_duration, data.punctuality, data.uniform,
        data.atmosphere, data.kindness, data.song_requests,
    )) / 6
    overall = round(service_average * 0.70 + data.would_hire_again * 0.30, 2)
    review = BookingReview(
        booking_id=booking.id,
        musician_id=booking.musician_id,
        overall_score=overall,
        recommendation=recommendation,
        **data.model_dump(exclude={"recommendation"}),
    )
    db.add(review)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Ya calificaste este evento")
    db.refresh(review)
    return review


@app.post("/api/bookings/{booking_id}/release")
def release_booking_payment(
    booking_id: int,
    user: User = Depends(require_role(UserRole.client)),
    db: Session = Depends(get_db),
):
    booking = db.scalar(booking_query().where(Booking.id == booking_id))
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if booking.client.user_id != user.id:
        raise HTTPException(403, "Esta contratación pertenece a otro cliente")
    if booking.payment_status != "paid":
        raise HTTPException(409, "El pago aún no está confirmado")
    if not booking_event_finished(booking):
        raise HTTPException(403, "Podrás liberar el pago al terminar el evento")
    approved_at = datetime.now(timezone.utc).replace(tzinfo=None)
    result = db.execute(
        update(Booking)
        .where(
            Booking.id == booking.id,
            Booking.payment_status == "paid",
            Booking.payout_status == "musician_funds_held",
        )
        .values(
            payout_status="approved_for_payout",
            approved_for_payout_at=approved_at,
        )
    )
    if result.rowcount != 1:
        db.rollback()
        raise HTTPException(
            409, "El pago ya fue liberado o tiene una disputa abierta"
        )
    db.commit()
    release_musician_funds(booking.id, db)
    saved = db.get(Booking, booking.id)
    return {"booking_id": saved.id, "payout_status": saved.payout_status}


@app.post("/api/bookings/{booking_id}/dispute")
def open_booking_dispute(
    booking_id: int,
    data: BookingDisputeCreate,
    user: User = Depends(require_role(UserRole.client)),
    db: Session = Depends(get_db),
):
    booking = db.scalar(booking_query().where(Booking.id == booking_id))
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if booking.client.user_id != user.id:
        raise HTTPException(403, "Esta contratación pertenece a otro cliente")
    if booking.payment_status != "paid":
        raise HTTPException(409, "El pago aún no está confirmado")
    if not booking_event_finished(booking):
        raise HTTPException(403, "Podrás reportar un problema al terminar el evento")
    if not booking_payout_window_open(booking):
        raise HTTPException(
            409,
            "El plazo de 2 horas terminó y el pago ya fue autorizado para la agrupación",
        )
    opened_at = datetime.now(timezone.utc).replace(tzinfo=None)
    result = db.execute(
        update(Booking)
        .where(
            Booking.id == booking.id,
            Booking.payout_status == "musician_funds_held",
        )
        .values(
            payout_status="disputed",
            dispute_reason=data.reason.strip(),
            dispute_opened_at=opened_at,
        )
    )
    if result.rowcount != 1:
        db.rollback()
        raise HTTPException(409, "El pago ya fue autorizado o tiene una disputa abierta")
    db.commit()
    return {"booking_id": booking.id, "payout_status": "disputed"}


@app.put("/api/admin/bookings/{booking_id}/payout")
def admin_payout_action(
    booking_id: int,
    data: AdminPayoutAction,
    user: User = Depends(require_role(UserRole.admin)),
    db: Session = Depends(get_db),
):
    booking = db.get(Booking, booking_id)
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if data.action in {"approve", "reject_dispute"}:
        if booking.payment_status != "paid":
            raise HTTPException(409, "El pago aún no está confirmado")
        if booking_payout_window_open(booking):
            raise HTTPException(
                403,
                "El pago permanecerá retenido durante las 2 horas posteriores al evento",
            )
        booking.payout_status = "approved_for_payout"
        booking.approved_for_payout_at = datetime.now(timezone.utc).replace(tzinfo=None)
        if data.action == "reject_dispute":
            booking.dispute_reason = None
    elif data.action == "mark_paid":
        raise HTTPException(
            409,
            "Stripe confirma automáticamente el depósito bancario; no puede marcarse manualmente",
        )
    db.commit()
    if data.action in {"approve", "reject_dispute"}:
        release_musician_funds(booking.id, db)
        booking = db.get(Booking, booking.id)
    return {"booking_id": booking.id, "payout_status": booking.payout_status}


@app.get(
    "/api/bookings/{booking_id}/review",
    response_model=BookingReviewResponse,
)
def get_booking_review(
    booking_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = accessible_booking(booking_id, user, db)
    if user.role != UserRole.admin and (
        user.role != UserRole.musician or booking.musician.user_id != user.id
    ):
        raise HTTPException(403, "La recomendación es privada para la agrupación")
    if not booking.review:
        raise HTTPException(404, "Este evento aún no tiene calificación")
    return booking.review


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
    if user.role != UserRole.admin:
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
    if user.role != UserRole.admin:
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


@app.post(
    "/api/bookings/{booking_id}/chat-invite",
    response_model=EventChatInviteResponse,
)
def create_event_chat_invite(
    booking_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = accessible_booking(booking_id, user, db)
    can_invite = user.id in {
        booking.client.user_id,
        booking.musician.user_id,
    }
    if not can_invite:
        raise HTTPException(
            403,
            "Solo el anfitrión o la agrupación contratada pueden mostrar el QR",
        )
    require_active_chat(booking)
    expires_at = event_chat_ends_at(booking)
    token = jwt.encode(
        {"scope": "event_chat", "booking_id": booking.id, "exp": expires_at},
        settings.secret_key,
        algorithm="HS256",
    )
    return EventChatInviteResponse(
        token=token,
        qr_value=f"GARIBALDI_EVENT:{token}",
        expires_at=expires_at,
    )


@app.get("/api/event-chat/{token}", response_model=EventChatAccessResponse)
def get_event_chat_access(
    token: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = booking_from_event_chat_token(token, db)
    active, status = booking_chat_state(booking)
    return EventChatAccessResponse(
        id=booking.id,
        group_name=booking.musician.group_name,
        event_date=booking.event_date,
        venue=booking.venue,
        start_time=booking.start_time,
        end_time=booking.end_time,
        chat_active=active,
        chat_status=status,
    )


@app.get(
    "/api/event-chat/{token}/messages",
    response_model=list[ChatMessageResponse],
)
def get_event_chat_messages(
    token: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = booking_from_event_chat_token(token, db)
    messages = db.scalars(
        select(ChatMessage)
        .where(ChatMessage.booking_id == booking.id)
        .order_by(ChatMessage.created_at, ChatMessage.id)
    ).all()
    return [chat_message_out(item, booking, user) for item in messages]


@app.post(
    "/api/event-chat/{token}/messages",
    response_model=ChatMessageResponse,
    status_code=201,
)
def send_event_chat_message(
    token: str,
    data: ChatMessageCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = booking_from_event_chat_token(token, db)
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
    allowed = ({"video/mp4", "video/webm"} if media_type == MediaType.video
               else {"image/jpeg", "image/png", "image/webp"})
    if file.content_type not in allowed: raise HTTPException(415, "Tipo de archivo no permitido")
    extension = CONTENT_TYPE_EXTENSIONS[file.content_type]
    folder = settings.upload_dir / str(profile.id); folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{media_type.value}-{position}-{uuid4().hex}{extension}"
    maximum_bytes = settings.max_video_bytes if media_type == MediaType.video else settings.max_image_bytes
    save_upload(file, target, maximum_bytes)
    validate_upload_signature(target, file.content_type)
    existing = db.scalar(select(Media).where(Media.musician_id == profile.id, Media.media_type == media_type, Media.position == position))
    public_url = f"/uploads/{profile.id}/{target.name}"
    if existing:
        existing.reactions.clear()
        existing.shares.clear()
        old = settings.upload_dir / str(profile.id) / Path(existing.url).name
        if old.exists(): old.unlink()
        existing.url = public_url
    else:
        existing = Media(musician_id=profile.id, media_type=media_type, position=position, url=public_url); db.add(existing)
    if media_type == MediaType.profile_photo:
        choice = db.scalar(select(AvatarChoice).where(AvatarChoice.user_id == user.id))
        if choice:
            choice.mode = "photo"
        else:
            db.add(AvatarChoice(user_id=user.id, mode="photo"))
    db.commit(); db.refresh(existing)
    return {"id": existing.id, "media_type": existing.media_type, "position": existing.position, "url": existing.url}
