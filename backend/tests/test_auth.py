import statistics
import time
import uuid
from datetime import timedelta

import jwt
from sqlmodel import Session, select

from app.config import settings
from app.models import GlobalRole, RefreshToken, utcnow
from app.rate_limit import login_failure_limiter, login_ip_limiter
from app.routers.auth import REFRESH_COOKIE
from tests.conftest import SignedIn
from tests.helpers import (
    CSRF,
    PASSWORD,
    client_with_refresh_cookie,
    create_user,
    new_client,
    sign_in,
)


def test_login_returns_working_access_token() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    me = client.get("/api/me")
    assert me.status_code == 200
    assert me.json()["username"] == "alice"


def test_login_is_case_insensitive_on_username() -> None:
    create_user("Alice")
    client = new_client()
    sign_in(client, "aLICE")
    assert client.get("/api/me").json()["username"] == "Alice"


def test_unknown_user_and_wrong_password_give_identical_errors() -> None:
    create_user("alice")
    client = new_client()
    unknown = client.post("/api/auth/login", json={"username": "nobody", "password": PASSWORD})
    wrong = client.post("/api/auth/login", json={"username": "alice", "password": "wrong-pass"})
    assert unknown.status_code == wrong.status_code == 401
    assert unknown.json() == wrong.json() == {"detail": "Incorrect username or password."}


def test_unknown_user_and_wrong_password_take_similar_time() -> None:
    create_user("alice")
    client = new_client()

    def seconds(username: str) -> float:
        started = time.perf_counter()
        response = client.post(
            "/api/auth/login", json={"username": username, "password": "wrong-pass"}
        )
        assert response.status_code == 401
        return time.perf_counter() - started

    unknown: list[float] = []
    wrong_password: list[float] = []
    # Interleaved so a stall on the machine hits both sides alike; limiters are reset because
    # a 429 would short-circuit before argon2 and skew the timing.
    for _ in range(7):
        unknown.append(seconds("nobody"))
        wrong_password.append(seconds("alice"))
        for limiter in (login_ip_limiter, login_failure_limiter):
            limiter.reset()
    # Without the dummy hash the unknown-user path skips argon2 and is ~20x faster.
    assert 0.5 < statistics.median(unknown) / statistics.median(wrong_password) < 2.0


def test_deactivated_user_gets_the_same_login_error(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    user = create_user("alice")
    admin.patch(f"/api/admin/users/{user.id}", json={"is_active": False})
    response = new_client().post(
        "/api/auth/login", json={"username": "alice", "password": PASSWORD}
    )
    assert response.status_code == 401
    assert response.json() == {"detail": "Incorrect username or password."}


def test_refresh_cookie_flags() -> None:
    create_user("alice")
    response = new_client().post(
        "/api/auth/login", json={"username": "alice", "password": PASSWORD}
    )
    set_cookie = response.headers["set-cookie"]
    assert set_cookie.startswith(f"{REFRESH_COOKIE}=")
    for flag in ("HttpOnly", "Secure", "SameSite=lax", "Path=/api/auth"):
        assert flag in set_cookie


def test_refresh_token_is_stored_hashed(db: Session) -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    cookie = client.cookies[REFRESH_COOKIE]
    stored = db.exec(select(RefreshToken)).one()
    assert cookie not in (stored.token_hash, str(stored.id))
    assert len(stored.token_hash) == 64


def test_refresh_rotates_the_token() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    first_cookie = client.cookies[REFRESH_COOKIE]

    response = client.post("/api/auth/refresh", headers=CSRF)
    assert response.status_code == 200
    assert client.cookies[REFRESH_COOKIE] != first_cookie
    me = client.get(
        "/api/me", headers={"Authorization": f"Bearer {response.json()['access_token']}"}
    )
    assert me.json()["username"] == "alice"


def test_reusing_a_rotated_token_revokes_the_whole_family() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    stolen_cookie = client.cookies[REFRESH_COOKIE]
    assert client.post("/api/auth/refresh", headers=CSRF).status_code == 200
    current_cookie = client.cookies[REFRESH_COOKIE]

    attacker = client_with_refresh_cookie(stolen_cookie)
    assert attacker.post("/api/auth/refresh", headers=CSRF).status_code == 401

    victim = client_with_refresh_cookie(current_cookie)
    assert victim.post("/api/auth/refresh", headers=CSRF).status_code == 401


def test_reuse_does_not_touch_other_sessions_of_the_same_user() -> None:
    create_user("alice")
    laptop, phone = new_client(), new_client()
    sign_in(laptop, "alice")
    sign_in(phone, "alice")
    stolen_cookie = laptop.cookies[REFRESH_COOKIE]
    laptop.post("/api/auth/refresh", headers=CSRF)

    attacker = client_with_refresh_cookie(stolen_cookie)
    attacker.post("/api/auth/refresh", headers=CSRF)
    assert phone.post("/api/auth/refresh", headers=CSRF).status_code == 200


def test_refresh_and_logout_require_the_csrf_header() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    for path in ("/api/auth/refresh", "/api/auth/logout"):
        response = client.post(path)
        assert response.status_code == 403
        assert "X-Engram-CSRF" in response.json()["detail"]
    # The rejected logout must not have ended the session.
    assert client.post("/api/auth/refresh", headers=CSRF).status_code == 200


def test_refresh_without_cookie_is_rejected() -> None:
    assert new_client().post("/api/auth/refresh", headers=CSRF).status_code == 401


def test_expired_refresh_token_is_rejected(db: Session) -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    stored = db.exec(select(RefreshToken)).one()
    stored.expires_at = utcnow() - timedelta(seconds=1)
    db.add(stored)
    db.commit()
    assert client.post("/api/auth/refresh", headers=CSRF).status_code == 401


def test_logout_revokes_the_refresh_token() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    cookie = client.cookies[REFRESH_COOKIE]
    assert client.post("/api/auth/logout", headers=CSRF).status_code == 204

    replay = client_with_refresh_cookie(cookie)
    assert replay.post("/api/auth/refresh", headers=CSRF).status_code == 401


def test_password_change_revokes_other_sessions_and_old_access_tokens() -> None:
    create_user("alice")
    laptop, phone = new_client(), new_client()
    sign_in(laptop, "alice")
    phone_access = sign_in(phone, "alice")

    response = laptop.post(
        "/api/me/password",
        json={"current_password": PASSWORD, "new_password": "a brand new passphrase"},
    )
    assert response.status_code == 200
    laptop.headers["Authorization"] = f"Bearer {response.json()['access_token']}"

    assert laptop.get("/api/me").status_code == 200
    assert laptop.post("/api/auth/refresh", headers=CSRF).status_code == 200
    assert (
        phone.get("/api/me", headers={"Authorization": f"Bearer {phone_access}"}).status_code == 401
    )
    assert phone.post("/api/auth/refresh", headers=CSRF).status_code == 401
    sign_in(new_client(), "alice", "a brand new passphrase")


def test_password_change_requires_the_current_password() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    response = client.post(
        "/api/me/password",
        json={"current_password": "not my password", "new_password": "a brand new passphrase"},
    )
    assert response.status_code == 400
    sign_in(new_client(), "alice")


def test_short_new_password_is_rejected() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    response = client.post(
        "/api/me/password", json={"current_password": PASSWORD, "new_password": "short"}
    )
    assert response.status_code == 422


def _forged_token(user_id: uuid.UUID, *, secret: str, expires_in: timedelta) -> str:
    now = utcnow()
    return jwt.encode(
        {"sub": str(user_id), "ver": 0, "iat": now, "exp": now + expires_in},
        secret,
        algorithm="HS256",
    )


def test_expired_access_token_is_rejected() -> None:
    user = create_user("alice")
    secret = settings.jwt_secret.get_secret_value()
    token = _forged_token(user.id, secret=secret, expires_in=timedelta(seconds=-1))
    response = new_client().get("/api/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401


def test_access_token_signed_with_another_key_is_rejected() -> None:
    user = create_user("alice")
    token = _forged_token(user.id, secret="x" * 48, expires_in=timedelta(minutes=5))
    response = new_client().get("/api/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401


def test_missing_access_token_is_rejected() -> None:
    assert new_client().get("/api/me").status_code == 401


def test_update_timezone() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    assert client.patch("/api/me", json={"timezone": "Africa/Casablanca"}).status_code == 200
    assert client.get("/api/me").json()["timezone"] == "Africa/Casablanca"
    assert client.patch("/api/me", json={"timezone": "Mars/Olympus"}).status_code == 422
