from datetime import date, datetime, time

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator

from .models import MediaType, UserRole


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    role: UserRole


class LoginRequest(BaseModel):
    identifier: str | None = Field(default=None, min_length=3, max_length=320)
    email: EmailStr | None = None
    password: str = Field(min_length=1, max_length=128)

    @model_validator(mode="after")
    def migrate_email_login(self):
        self.identifier = self.identifier or (str(self.email) if self.email else None)
        if not self.identifier:
            raise ValueError("Escribe tu correo o número celular")
        return self


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(min_length=100, max_length=10000)
    role: UserRole | None = None
    create_account: bool = False

    @model_validator(mode="after")
    def require_role_for_registration(self):
        if self.create_account and self.role not in {
            UserRole.client, UserRole.musician,
        }:
            raise ValueError("Elige si usarás Balam como cliente o agrupación")
        return self


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetRequestResponse(BaseModel):
    message: str
    dev_code: str | None = Field(default=None, exclude_if=lambda value: value is None)


class PasswordResetConfirm(BaseModel):
    email: EmailStr
    code: str = Field(pattern=r"^\d{6}$")
    new_password: str = Field(min_length=8, max_length=128)


class RulesAcceptanceResponse(BaseModel):
    rules_type: str
    rules_version: str
    accepted: bool
    accepted_at: datetime | None = None
    accepted_group_name: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: int
    email: str | None = None
    phone: str | None = None
    role: UserRole
    is_active: bool
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class ClientProfileUpsert(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    admin_phone: str | None = Field(default=None, min_length=10, max_length=20)
    city: str | None = Field(default=None, min_length=2, max_length=120)
    municipality: str | None = Field(default=None, min_length=2, max_length=120)
    state: str | None = Field(default=None, min_length=2, max_length=120)
    musical_tastes: list[str] = Field(default_factory=list)
    favorite_groups: list[str] = Field(default_factory=list)


class ClientProfileResponse(ClientProfileUpsert):
    id: int
    user_id: int
    avatar_url: str | None = None
    avatar_preset: str = "jaguar_guitar"
    avatar_color: str = "#8B5CF6"
    profile_complete: bool = False
    admin_phone_saved: bool = False


class AvatarChoiceUpdate(BaseModel):
    preset: str = Field(min_length=2, max_length=40)
    color: str = Field(pattern=r"^#[0-9A-Fa-f]{6}$")


class MusicianProfileUpsert(BaseModel):
    contact_name: str = Field(min_length=2, max_length=120)
    admin_phone: str | None = Field(default=None, min_length=10, max_length=20)
    city: str | None = Field(default=None, min_length=2, max_length=120)
    municipality: str | None = Field(default=None, min_length=2, max_length=120)
    state: str | None = Field(default=None, min_length=2, max_length=120)
    group_name: str = Field(min_length=2, max_length=180)
    group_type: str = Field(min_length=2, max_length=100)
    musical_style: str = Field(min_length=2, max_length=180)
    member_count: int = Field(ge=1, le=100)
    hourly_rate: float = Field(ge=0)
    includes_sound: bool = False
    subwoofer_count: int = Field(default=0, ge=0, le=100)
    mid_speaker_count: int = Field(default=0, ge=0, le=100)
    equipment_brands: list[str] = Field(default_factory=list)
    audience_capacity: int = Field(default=0, ge=0)
    description: str = Field(default="", max_length=2000)


class MediaResponse(BaseModel):
    id: int
    media_type: MediaType
    position: int
    url: str
    model_config = ConfigDict(from_attributes=True)


class MusicianProfileResponse(MusicianProfileUpsert):
    id: int
    user_id: int
    media: list[MediaResponse] = Field(default_factory=list)
    avatar_preset: str = "jaguar_guitar"
    avatar_color: str = "#8B5CF6"
    rating: float | None = None
    review_count: int = 0
    profile_complete: bool = False
    admin_phone_saved: bool = False


class PayoutDestinationUpsert(BaseModel):
    destination_type: str = Field(pattern=r"^(clabe|debit_card)$")
    account_number: str = Field(min_length=16, max_length=23)


class PayoutDestinationResponse(BaseModel):
    eligible: bool
    configured: bool
    destination_type: str | None = None
    last4: str | None = None
    updated_at: datetime | None = None
    stripe_connect_ready: bool = False


class StripeConnectAccountUpdate(BaseModel):
    account_id: str = Field(pattern=r"^acct_[A-Za-z0-9]+$", max_length=255)


class BusyDateUpdate(BaseModel):
    busy: bool


class BusyDateResponse(BaseModel):
    date: date
    busy: bool


class AvailabilityResponse(BaseModel):
    date: date
    available: bool
    message: str


class BookingCreate(BaseModel):
    musician_id: int = Field(gt=0)
    event_date: date
    venue: str = Field(min_length=3, max_length=300)
    start_time: time
    end_time: time

    @model_validator(mode="after")
    def validate_schedule(self):
        if self.end_time <= self.start_time:
            raise ValueError("El horario final debe ser posterior al horario de inicio")
        return self


class BookingResponse(BaseModel):
    id: int
    musician_id: int
    group_name: str
    client_id: int
    client_name: str
    client_email: str
    event_date: date
    venue: str
    start_time: time
    end_time: time
    hourly_rate_cents: int
    duration_minutes: int
    subtotal_cents: int
    service_fee_cents: int
    total_cents: int
    musician_earnings_cents: int
    platform_fee_cents: int
    stripe_fee_estimate_cents: int
    currency: str
    payment_status: str
    payout_status: str
    dispute_reason: str | None = None
    stripe_transfer_id: str | None = None
    payout_error: str | None = None
    created_at: datetime
    chat_active: bool
    chat_status: str
    can_review: bool
    review_status: str
    review_score: float | None = None
    review_recommendation: str | None = None
    event_finished: bool
    is_new_sale: bool = False


class BookingDisputeCreate(BaseModel):
    reason: str = Field(min_length=10, max_length=1500)


class AdminPayoutAction(BaseModel):
    action: str = Field(pattern=r"^(approve|mark_paid|reject_dispute)$")


class BookingReviewCreate(BaseModel):
    agreed_duration: float
    punctuality: float
    uniform: float
    atmosphere: float
    kindness: float
    song_requests: float
    would_hire_again: float
    recommendation: str = Field(min_length=3, max_length=1000)

    @model_validator(mode="after")
    def validate_stars(self):
        fields = (
            "agreed_duration", "punctuality", "uniform", "atmosphere",
            "kindness", "song_requests", "would_hire_again",
        )
        for name in fields:
            score = getattr(self, name)
            if score < 0.5 or score > 5 or score * 2 != int(score * 2):
                raise ValueError("Cada calificación debe ir de 0.5 a 5 en medias estrellas")
        return self


class BookingReviewResponse(BookingReviewCreate):
    id: int
    booking_id: int
    musician_id: int
    overall_score: float
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class ChatMessageCreate(BaseModel):
    text: str = Field(min_length=1, max_length=1500)


class ChatMessageResponse(BaseModel):
    id: int
    booking_id: int
    sender_user_id: int
    sender_role: UserRole
    sender_name: str
    text: str
    created_at: datetime
    mine: bool


class EventChatInviteResponse(BaseModel):
    token: str
    qr_value: str
    expires_at: datetime


class EventChatAccessResponse(BaseModel):
    id: int
    group_name: str
    event_date: date
    venue: str
    start_time: time
    end_time: time
    chat_active: bool
    chat_status: str
