import os
import subprocess
import sys

import pytest
from alembic.autogenerate import compare_metadata
from alembic.runtime.migration import MigrationContext
from sqlmodel import SQLModel

from app.db import engine
from tests.conftest import BACKEND_DIR
from tests.helpers import CSRF, PASSWORD, new_client, sign_in


def _run(args: list[str], env: dict[str, str], stdin: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, *args],
        cwd=BACKEND_DIR,
        env=env,
        input=stdin,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


@pytest.mark.parametrize(
    ("missing", "override", "expected_field"),
    [
        ("JWT_SECRET", {}, "jwt_secret"),
        ("DATABASE_URL", {}, "database_url"),
        (None, {"JWT_SECRET": "too-short-secret"}, "jwt_secret"),
    ],
)
def test_backend_refuses_to_start_without_valid_secrets(
    missing: str | None, override: dict[str, str], expected_field: str
) -> None:
    env = {key: value for key, value in os.environ.items() if key != missing} | override
    result = _run(["-c", "import app.main"], env)
    assert result.returncode != 0
    assert expected_field in result.stderr
    for secret in (env.get("JWT_SECRET"), env.get("DATABASE_URL")):
        if secret:
            assert secret not in result.stderr


def test_create_admin_cli_creates_a_working_admin() -> None:
    result = _run(
        ["-m", "app.cli", "create-admin", "root", "--password-stdin"], dict(os.environ), PASSWORD
    )
    assert result.returncode == 0, result.stderr
    client = new_client()
    sign_in(client, "root")
    assert client.get("/api/me").json()["role"] == "admin"
    assert client.get("/api/admin/users").status_code == 200


def test_create_admin_cli_rejects_duplicates_and_weak_passwords() -> None:
    env = dict(os.environ)
    assert _run(["-m", "app.cli", "create-admin", "root", "--password-stdin"], env, PASSWORD)
    weak = _run(["-m", "app.cli", "create-admin", "other", "--password-stdin"], env, "short")
    assert weak.returncode != 0
    duplicate = _run(["-m", "app.cli", "create-admin", "ROOT", "--password-stdin"], env, PASSWORD)
    assert duplicate.returncode != 0
    assert "already exists" in duplicate.stderr


def test_set_password_cli_changes_password_and_signs_out_sessions() -> None:
    env = dict(os.environ)
    _run(["-m", "app.cli", "create-admin", "root", "--password-stdin"], env, PASSWORD)
    client = new_client()
    sign_in(client, "root")

    result = _run(
        ["-m", "app.cli", "set-password", "root", "--password-stdin"], env, "a new passphrase!"
    )
    assert result.returncode == 0, result.stderr
    assert client.get("/api/me").status_code == 401
    assert client.post("/api/auth/refresh", headers=CSRF).status_code == 401
    sign_in(new_client(), "root", "a new passphrase!")


def test_wait_for_migrations_returns_when_schema_is_current() -> None:
    result = _run(["-m", "app.cli", "wait-for-migrations", "--timeout", "5"], dict(os.environ))
    assert result.returncode == 0, result.stderr


def test_migrations_match_the_models() -> None:
    with engine.connect() as connection:
        differences = compare_metadata(MigrationContext.configure(connection), SQLModel.metadata)
    assert differences == []
