import enum
from datetime import date, datetime, time, timezone

from sqlalchemy import Boolean, Date, DateTime, Enum, Float, ForeignKey, Integer, Numeric, String, Text, Time, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class UserRole(str, enum.Enum):
    musician = "musician"
    client = "client"
    admin = "admin"


class MediaType(str, enum.Enum):
    profile_photo = "profile_photo"
    photo = "photo"
    video = "video"


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True, index=True, nullable=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    google_subject: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, nullable=True
    )
    role: Mapped[UserRole] = mapped_column(Enum(UserRole))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    token_version: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))
    musician_profile: Mapped["MusicianProfile | None"] = relationship(back_populates="user", cascade="all, delete-orphan")
    client_profile: Mapped["ClientProfile | None"] = relationship(back_populates="user", cascade="all, delete-orphan")
    avatar_choice: Mapped["AvatarChoice | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )


class BillingCustomer(Base):
    __tablename__ = "billing_customers"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"), unique=True, index=True
    )
    stripe_customer_id: Mapped[str] = mapped_column(
        String(255), unique=True, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
        onupdate=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
    )


class StripeWebhookEvent(Base):
    __tablename__ = "stripe_webhook_events"
    id: Mapped[int] = mapped_column(primary_key=True)
    stripe_event_id: Mapped[str] = mapped_column(
        String(255), unique=True, index=True
    )
    event_type: Mapped[str] = mapped_column(String(120))
    processed_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None)
    )


class PasswordResetCode(Base):
    __tablename__ = "password_reset_codes"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    used: Mapped[bool] = mapped_column(Boolean, default=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None)
    )


class RulesAcceptance(Base):
    __tablename__ = "rules_acceptances"
    __table_args__ = (
        UniqueConstraint("user_id", "rules_type", "rules_version"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    rules_type: Mapped[str] = mapped_column(String(80), index=True)
    rules_version: Mapped[str] = mapped_column(String(80), index=True)
    group_name_snapshot: Mapped[str | None] = mapped_column(
        String(180), nullable=True
    )
    accepted: Mapped[bool] = mapped_column(Boolean, default=True)
    accepted_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None)
    )


class AvatarChoice(Base):
    __tablename__ = "avatar_choices"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    preset: Mapped[str] = mapped_column(String(40), default="jaguar_guitar")
    color: Mapped[str] = mapped_column(String(9), default="#8B5CF6")
    mode: Mapped[str] = mapped_column(String(12), default="photo")
    user: Mapped[User] = relationship(back_populates="avatar_choice")


class MusicianProfile(Base):
    __tablename__ = "musician_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    contact_name: Mapped[str] = mapped_column(String(120))
    admin_phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    city: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    municipality: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    state: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    group_name: Mapped[str] = mapped_column(String(180), index=True)
    group_type: Mapped[str] = mapped_column(String(100), index=True)
    musical_style: Mapped[str] = mapped_column(String(180), index=True)
    card_theme: Mapped[str] = mapped_column(String(30), default="classic")
    member_count: Mapped[int] = mapped_column(Integer)
    hourly_rate: Mapped[float] = mapped_column(Numeric(12, 2))
    minimum_booking_hours: Mapped[int] = mapped_column(Integer, default=2)
    includes_sound: Mapped[bool] = mapped_column(Boolean, default=False)
    subwoofer_count: Mapped[int] = mapped_column(Integer, default=0)
    mid_speaker_count: Mapped[int] = mapped_column(Integer, default=0)
    equipment_brands: Mapped[str] = mapped_column(Text, default="")
    audience_capacity: Mapped[int] = mapped_column(Integer, default=0)
    description: Mapped[str] = mapped_column(Text, default="")
    user: Mapped[User] = relationship(back_populates="musician_profile")
    media: Mapped[list["Media"]] = relationship(back_populates="musician", cascade="all, delete-orphan")
    busy_dates: Mapped[list["MusicianBusyDate"]] = relationship(
        back_populates="musician", cascade="all, delete-orphan"
    )
    bookings: Mapped[list["Booking"]] = relationship(
        back_populates="musician", cascade="all, delete-orphan"
    )
    reviews: Mapped[list["BookingReview"]] = relationship(
        back_populates="musician", cascade="all, delete-orphan"
    )
    payout_destination: Mapped["MusicianPayoutDestination | None"] = relationship(
        back_populates="musician", cascade="all, delete-orphan", uselist=False
    )


class MusicianPayoutDestination(Base):
    __tablename__ = "musician_payout_destinations"
    id: Mapped[int] = mapped_column(primary_key=True)
    musician_id: Mapped[int] = mapped_column(
        ForeignKey("musician_profiles.id"), unique=True, index=True
    )
    destination_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    encrypted_number: Mapped[str | None] = mapped_column(Text, nullable=True)
    last4: Mapped[str | None] = mapped_column(String(4), nullable=True)
    stripe_connected_account_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, nullable=True
    )
    stripe_details_submitted: Mapped[bool] = mapped_column(Boolean, default=False)
    stripe_payouts_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    stripe_requirements_due: Mapped[str] = mapped_column(Text, default="")
    last_stripe_payout_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    last_stripe_payout_status: Mapped[str | None] = mapped_column(String(30), nullable=True)
    last_stripe_payout_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
        onupdate=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
    )
    musician: Mapped[MusicianProfile] = relationship(
        back_populates="payout_destination"
    )


class MusicianBusyDate(Base):
    __tablename__ = "musician_busy_dates"
    __table_args__ = (UniqueConstraint("musician_id", "busy_date"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    musician_id: Mapped[int] = mapped_column(
        ForeignKey("musician_profiles.id"), index=True
    )
    busy_date: Mapped[date] = mapped_column(Date, index=True)
    musician: Mapped[MusicianProfile] = relationship(back_populates="busy_dates")


class ClientProfile(Base):
    __tablename__ = "client_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    admin_phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    city: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    municipality: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    state: Mapped[str | None] = mapped_column(String(120), nullable=True, index=True)
    musical_tastes: Mapped[str] = mapped_column(Text, default="")
    favorite_groups: Mapped[str] = mapped_column(Text, default="")
    user: Mapped[User] = relationship(back_populates="client_profile")
    avatar: Mapped["ClientAvatar | None"] = relationship(
        back_populates="client", cascade="all, delete-orphan", uselist=False
    )
    bookings: Mapped[list["Booking"]] = relationship(
        back_populates="client", cascade="all, delete-orphan"
    )


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = (UniqueConstraint("musician_id", "event_date"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    musician_id: Mapped[int] = mapped_column(
        ForeignKey("musician_profiles.id"), index=True
    )
    client_id: Mapped[int] = mapped_column(
        ForeignKey("client_profiles.id"), index=True
    )
    event_date: Mapped[date] = mapped_column(Date, index=True)
    venue: Mapped[str] = mapped_column(String(300))
    start_time: Mapped[time] = mapped_column(Time)
    end_time: Mapped[time] = mapped_column(Time)
    hourly_rate_cents: Mapped[int] = mapped_column(Integer, default=0)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=0)
    subtotal_cents: Mapped[int] = mapped_column(Integer, default=0)
    service_fee_cents: Mapped[int] = mapped_column(Integer, default=0)
    total_cents: Mapped[int] = mapped_column(Integer, default=0)
    musician_earnings_cents: Mapped[int] = mapped_column(Integer, default=0)
    platform_fee_cents: Mapped[int] = mapped_column(Integer, default=0)
    stripe_fee_estimate_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(3), default="mxn")
    payment_status: Mapped[str] = mapped_column(
        String(30), default="pending", index=True
    )
    stripe_checkout_session_id: Mapped[str | None] = mapped_column(
        String(255), nullable=True, unique=True
    )
    stripe_payment_intent_id: Mapped[str | None] = mapped_column(
        String(255), nullable=True, unique=True
    )
    stripe_transfer_id: Mapped[str | None] = mapped_column(
        String(255), nullable=True, unique=True
    )
    payout_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    payout_status: Mapped[str] = mapped_column(
        String(40), default="awaiting_payment", index=True
    )
    dispute_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    dispute_opened_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    approved_for_payout_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    paid_out_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None)
    )
    musician: Mapped[MusicianProfile] = relationship(back_populates="bookings")
    client: Mapped[ClientProfile] = relationship(back_populates="bookings")
    messages: Mapped[list["ChatMessage"]] = relationship(
        back_populates="booking", cascade="all, delete-orphan"
    )
    review: Mapped["BookingReview | None"] = relationship(
        back_populates="booking", cascade="all, delete-orphan", uselist=False
    )


class BookingReview(Base):
    __tablename__ = "booking_reviews"
    id: Mapped[int] = mapped_column(primary_key=True)
    booking_id: Mapped[int] = mapped_column(ForeignKey("bookings.id"), unique=True, index=True)
    musician_id: Mapped[int] = mapped_column(ForeignKey("musician_profiles.id"), index=True)
    agreed_duration: Mapped[float] = mapped_column(Float)
    punctuality: Mapped[float] = mapped_column(Float)
    uniform: Mapped[float] = mapped_column(Float)
    atmosphere: Mapped[float] = mapped_column(Float)
    kindness: Mapped[float] = mapped_column(Float)
    song_requests: Mapped[float] = mapped_column(Float)
    would_hire_again: Mapped[float] = mapped_column(Float)
    overall_score: Mapped[float] = mapped_column(Float)
    recommendation: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None)
    )
    booking: Mapped[Booking] = relationship(back_populates="review")
    musician: Mapped[MusicianProfile] = relationship(back_populates="reviews")


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    id: Mapped[int] = mapped_column(primary_key=True)
    booking_id: Mapped[int] = mapped_column(ForeignKey("bookings.id"), index=True)
    sender_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None)
    )
    booking: Mapped[Booking] = relationship(back_populates="messages")
    sender: Mapped[User] = relationship()


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
