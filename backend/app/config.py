from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Balam API"
    database_url: str = "sqlite:///./balam.db"
    secret_key: str = "desarrollo-cambiar-en-produccion"
    access_token_minutes: int = 60 * 24 * 7
    upload_dir: Path = Path("uploads")

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()

