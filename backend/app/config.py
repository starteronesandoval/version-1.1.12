from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Balam API"
    app_env: Literal["development", "test", "staging", "production"] = "development"
    database_url: str = "sqlite:///./balam.db"
    secret_key: str = "development-only-secret-key-change-me"
    access_token_minutes: int = Field(default=60, ge=5, le=10080)
    upload_dir: Path = Path("uploads")
    release_download_dir: Path = Path("releases")
    event_timezone: str = "America/Mexico_City"
    payout_auto_release_hours: int = Field(default=2, ge=2, le=2)
    payout_release_scan_seconds: int = Field(default=60, ge=10, le=3600)
    fcm_project_id: str | None = None
    fcm_credentials_file: Path | None = None
    push_scan_seconds: int = Field(default=15, ge=5, le=300)
    stripe_secret_key: str | None = None
    stripe_webhook_secret: str | None = None
    billing_success_url: str = (
        "http://10.0.2.2:8000/api/billing/checkout/success"
        "?session_id={CHECKOUT_SESSION_ID}"
    )
    billing_cancel_url: str = "http://10.0.2.2:8000/api/billing/checkout/cancel"
    connect_refresh_url: str = "http://10.0.2.2:8000/api/billing/connect/refresh"
    connect_return_url: str = "http://10.0.2.2:8000/api/billing/connect/return"
    cors_origins: Annotated[list[str], NoDecode] = [
        "http://localhost:3000", "http://localhost:8080"
    ]
    allowed_hosts: Annotated[list[str], NoDecode] = [
        "localhost", "127.0.0.1", "10.0.2.2", "testserver"
    ]
    database_pool_size: int = Field(default=10, ge=1, le=100)
    database_max_overflow: int = Field(default=20, ge=0, le=200)
    database_pool_timeout: int = Field(default=30, ge=1, le=300)
    database_pool_recycle: int = Field(default=1800, ge=60, le=86400)
    database_connect_timeout: int = Field(default=10, ge=1, le=60)
    database_ssl_mode: Literal[
        "disable", "allow", "prefer", "require", "verify-ca", "verify-full"
    ] = "prefer"
    database_ssl_root_cert: Path | None = None
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from_email: str | None = None
    smtp_from_name: str = "Balam"
    smtp_starttls: bool = True
    google_client_ids: Annotated[list[str], NoDecode] = [
        "882316037020-3tgmqu1p4vn8g187aam0svvo8cmr1l0g.apps.googleusercontent.com"
    ]
    expose_password_reset_code: bool = False
    max_image_bytes: int = 8 * 1024 * 1024
    max_video_bytes: int = 100 * 1024 * 1024
    max_request_body_bytes: int = Field(default=2 * 1024 * 1024, ge=1024)
    max_stripe_webhook_bytes: int = Field(default=1024 * 1024, ge=1024)
    trust_cloudflare_headers: bool = False
    auth_rate_limit_per_minute: int = Field(default=10, ge=1, le=1000)
    password_reset_rate_limit_per_hour: int = Field(default=5, ge=1, le=100)

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    @field_validator("cors_origins", "allowed_hosts", "google_client_ids", mode="before")
    @classmethod
    def parse_csv(cls, value):
        if isinstance(value, str) and not value.lstrip().startswith("["):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @model_validator(mode="after")
    def validate_production(self):
        if self.app_env in {"staging", "production"}:
            if self.access_token_minutes > 1440:
                raise ValueError(
                    "ACCESS_TOKEN_MINUTES no puede superar 1440 fuera de desarrollo"
                )
            if not self.database_url.startswith(("postgresql://", "postgresql+psycopg://")):
                raise ValueError("DATABASE_URL debe usar PostgreSQL fuera de desarrollo")
            if self.database_ssl_mode in {"verify-ca", "verify-full"}:
                if not self.database_ssl_root_cert:
                    raise ValueError(
                        "DATABASE_SSL_ROOT_CERT es obligatorio con verificación SSL"
                    )
            if len(self.secret_key) < 32 or "development" in self.secret_key.lower():
                raise ValueError("SECRET_KEY debe ser aleatoria y tener al menos 32 caracteres")
            if not self.cors_origins or "*" in self.cors_origins:
                raise ValueError("CORS_ORIGINS debe enumerar los sitios web permitidos")
            if any(not origin.startswith("https://") for origin in self.cors_origins):
                raise ValueError("Todos los CORS_ORIGINS deben usar HTTPS")
            if not self.allowed_hosts or "*" in self.allowed_hosts:
                raise ValueError("ALLOWED_HOSTS debe enumerar los hosts públicos")
            if self.expose_password_reset_code:
                raise ValueError("EXPOSE_PASSWORD_RESET_CODE no puede activarse en producción")
            if not self.smtp_host or not self.smtp_from_email:
                raise ValueError(
                    "SMTP_HOST y SMTP_FROM_EMAIL son obligatorios en producción"
                )
            if not self.stripe_secret_key or not self.stripe_webhook_secret:
                raise ValueError(
                    "STRIPE_SECRET_KEY y STRIPE_WEBHOOK_SECRET son obligatorios "
                    "en producción"
                )
            if not self.billing_success_url.startswith("https://"):
                raise ValueError("BILLING_SUCCESS_URL debe usar HTTPS")
            if not self.billing_cancel_url.startswith("https://"):
                raise ValueError("BILLING_CANCEL_URL debe usar HTTPS")
            if not self.connect_refresh_url.startswith("https://"):
                raise ValueError("CONNECT_REFRESH_URL debe usar HTTPS")
            if not self.connect_return_url.startswith("https://"):
                raise ValueError("CONNECT_RETURN_URL debe usar HTTPS")
        return self


settings = Settings()
