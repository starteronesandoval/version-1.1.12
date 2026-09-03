import enum
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Enum, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class UserRole(str, enum.Enum):
    musician = "musician"
    client = "client"


class MediaType(str, enum.Enum):
    profile_photo = "profile_photo"
    photo = "photo"
    video = "video"


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[UserRole] = mapped_column(Enum(UserRole))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))
    musician_profile: Mapped["MusicianProfile | None"] = relationship(back_populates="user", cascade="all, delete-orphan")
    client_profile: Mapped["ClientProfile | None"] = relationship(back_populates="user", cascade="all, delete-orphan")


class MusicianProfile(Base):
    __tablename__ = "musician_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    contact_name: Mapped[str] = mapped_column(String(120))
    group_name: Mapped[str] = mapped_column(String(180), index=True)
    group_type: Mapped[str] = mapped_column(String(100), index=True)
    musical_style: Mapped[str] = mapped_column(String(180), index=True)
    member_count: Mapped[int] = mapped_column(Integer)
    hourly_rate: Mapped[float] = mapped_column(Float)
    includes_sound: Mapped[bool] = mapped_column(Boolean, default=False)
    subwoofer_count: Mapped[int] = mapped_column(Integer, default=0)
    mid_speaker_count: Mapped[int] = mapped_column(Integer, default=0)
    equipment_brands: Mapped[str] = mapped_column(Text, default="")
    audience_capacity: Mapped[int] = mapped_column(Integer, default=0)
    description: Mapped[str] = mapped_column(Text, default="")
    user: Mapped[User] = relationship(back_populates="musician_profile")
    media: Mapped[list["Media"]] = relationship(back_populates="musician", cascade="all, delete-orphan")


class ClientProfile(Base):
    __tablename__ = "client_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    musical_tastes: Mapped[str] = mapped_column(Text, default="")
    favorite_groups: Mapped[str] = mapped_column(Text, default="")
    user: Mapped[User] = relationship(back_populates="client_profile")
    avatar: Mapped["ClientAvatar | None"] = relationship(
        back_populates="client", cascade="all, delete-orphan", uselist=False
    )


class ClientAvatar(Base):
    __tablename__ = "client_avatars"
    id: Mapped[int] = mapped_column(primary_key=True)
    client_id: Mapped[int] = mapped_column(ForeignKey("client_profiles.id"), unique=True, index=True)
    url: Mapped[str] = mapped_column(String(500))
    client: Mapped[ClientProfile] = relationship(back_populates="avatar")


class Media(Base):
    __tablename__ = "media"
    __table_args__ = (UniqueConstraint("musician_id", "media_type", "position"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    musician_id: Mapped[int] = mapped_column(ForeignKey("musician_profiles.id"), index=True)
    media_type: Mapped[MediaType] = mapped_column(Enum(MediaType))
    position: Mapped[int] = mapped_column(Integer)
    url: Mapped[str] = mapped_column(String(500))
    musician: Mapped[MusicianProfile] = relationship(back_populates="media")
