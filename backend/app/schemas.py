from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

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


class BusyDateUpdate(BaseModel):
    busy: bool


class BusyDateResponse(BaseModel):
    date: date
    busy: bool


class AvailabilityResponse(BaseModel):
    date: date
    available: bool
    message: str
