from pathlib import Path
from typing import Annotated, Literal

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Balam API"
    app_env: Literal["development", "test", "staging", "production"] = "development"
    database_url: str = "sqlite:///./balam.db"
    secret_key: str = "development-only-secret-key-change-me"
    access_token_minutes: int = 60 * 24 * 7
    upload_dir: Path = Path("uploads")
    event_timezone: str = "America/Mexico_City"
    cors_origins: Annotated[list[str], NoDecode] = [
        "http://localhost:3000", "http://localhost:8080"
    ]
    allowed_hosts: Annotated[list[str], NoDecode] = [
        "localhost", "127.0.0.1", "testserver"
    ]
    database_pool_size: int = 10
    database_max_overflow: int = 20
    database_pool_timeout: int = 30
    password_reset_webhook_url: str | None = None
    password_reset_webhook_token: str | None = None
    expose_password_reset_code: bool = False
    max_image_bytes: int = 8 * 1024 * 1024
    max_video_bytes: int = 100 * 1024 * 1024

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    @field_validator("cors_origins", "allowed_hosts", mode="before")
    @classmethod
    def parse_csv(cls, value):
        if isinstance(value, str) and not value.lstrip().startswith("["):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @model_validator(mode="after")
    def validate_production(self):
        if self.app_env in {"staging", "production"}:
            if not self.database_url.startswith(("postgresql://", "postgresql+psycopg://")):
                raise ValueError("DATABASE_URL debe usar PostgreSQL fuera de desarrollo")
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
            if not self.password_reset_webhook_url:
                raise ValueError("PASSWORD_RESET_WEBHOOK_URL es obligatorio en producción")
            if not self.password_reset_webhook_url.startswith("https://"):
                raise ValueError("PASSWORD_RESET_WEBHOOK_URL debe usar HTTPS")
        return self


settings = Settings()
