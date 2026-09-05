from datetime import date, datetime, time

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator

from .models import MediaType, UserRole


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    role: UserRole


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: int
    email: EmailStr
    role: UserRole
    is_active: bool
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class ClientProfileUpsert(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    musical_tastes: list[str] = Field(default_factory=list)
    favorite_groups: list[str] = Field(default_factory=list)


class ClientProfileResponse(ClientProfileUpsert):
    id: int
    user_id: int
    avatar_url: str | None = None
    avatar_preset: str = "jaguar_guitar"
    avatar_color: str = "#8B5CF6"


class AvatarChoiceUpdate(BaseModel):
    preset: str = Field(min_length=2, max_length=40)
    color: str = Field(pattern=r"^#[0-9A-Fa-f]{6}$")


class MusicianProfileUpsert(BaseModel):
    contact_name: str = Field(min_length=2, max_length=120)
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
    client_email: EmailStr
    event_date: date
    venue: str
    start_time: time
    end_time: time
    created_at: datetime
    chat_active: bool
    chat_status: str
    can_review: bool
    review_status: str
    review_score: float | None = None
    event_finished: bool


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
