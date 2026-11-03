import io
import sys

import pytest
from alembic.autogenerate import compare_metadata
from alembic.runtime.migration import MigrationContext
from pydantic import ValidationError
from sqlmodel import SQLModel

from app import cli
from app.config import Settings
from app.db import engine
from tests.helpers import CSRF, PASSWORD, new_client, sign_in


@pytest.mark.parametrize(
    ("missing", "override", "expected_field"),
    [
        ("JWT_SECRET", {}, "jwt_secret"),
        ("DATABASE_URL", {}, "database_url"),
        (None, {"JWT_SECRET": "too-short-secret"}, "jwt_secret"),
    ],
)
def test_config_rejects_missing_or_weak_secrets_without_echoing_them(
    monkeypatch: pytest.MonkeyPatch,
    missing: str | None,
    override: dict[str, str],
    expected_field: str,
) -> None:
    if missing:
        monkeypatch.delenv(missing)
    for key, value in override.items():
        monkeypatch.setenv(key, value)
    # Settings() is what app.config runs at import, so this is the startup check itself.
    with pytest.raises(ValidationError) as error:
        Settings()
    message = str(error.value)
    assert expected_field in message
    for secret in ("too-short-secret", str(engine.url.password)):
        assert secret not in message


def _cli(monkeypatch: pytest.MonkeyPatch, *args: str, stdin: str = "") -> None:
    monkeypatch.setattr(sys, "argv", ["app.cli", *args])
    monkeypatch.setattr(sys, "stdin", io.StringIO(stdin))
    cli.main()


def test_create_admin_creates_a_working_admin(monkeypatch: pytest.MonkeyPatch) -> None:
    _cli(monkeypatch, "create-admin", "root", "--password-stdin", stdin=PASSWORD)
    client = new_client()
    sign_in(client, "root")
    assert client.get("/api/admin/users").status_code == 200

    with pytest.raises(SystemExit, match="already exists"):
        _cli(monkeypatch, "create-admin", "ROOT", "--password-stdin", stdin=PASSWORD)
    with pytest.raises(SystemExit, match="10 to 256 characters"):
        _cli(monkeypatch, "create-admin", "other", "--password-stdin", stdin="short")


def test_set_password_signs_out_existing_sessions(monkeypatch: pytest.MonkeyPatch) -> None:
    _cli(monkeypatch, "create-admin", "root", "--password-stdin", stdin=PASSWORD)
    client = new_client()
    sign_in(client, "root")

    _cli(monkeypatch, "set-password", "root", "--password-stdin", stdin="a new passphrase!")
    assert client.get("/api/me").status_code == 401
    assert client.post("/api/auth/refresh", headers=CSRF).status_code == 401
    sign_in(new_client(), "root", "a new passphrase!")


def test_wait_for_migrations_returns_when_schema_is_current(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _cli(monkeypatch, "wait-for-migrations", "--timeout", "5")


def test_migrations_match_the_models() -> None:
    with engine.connect() as connection:
        differences = compare_metadata(MigrationContext.configure(connection), SQLModel.metadata)
    assert differences == []
