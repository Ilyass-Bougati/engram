from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Environment only: no .env file is read, so a missing secret fails loudly at startup.
    # Hiding inputs keeps a rejected secret (or a DATABASE_URL with its password) out of logs.
    model_config = SettingsConfigDict(env_file=None, extra="ignore", hide_input_in_errors=True)

    database_url: str
    jwt_secret: SecretStr = Field(min_length=32)
    refresh_token_days: int = Field(default=30, ge=1, le=365)

    @field_validator("database_url")
    @classmethod
    def use_psycopg_driver(cls, url: str) -> str:
        # Accept the libpq-style URL that Postgres tooling prints and pin the driver we ship.
        for prefix in ("postgresql://", "postgres://"):
            if url.startswith(prefix):
                return "postgresql+psycopg://" + url.removeprefix(prefix)
        return url


settings = Settings()
