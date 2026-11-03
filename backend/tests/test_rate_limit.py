from app.models import GlobalRole
from tests.conftest import SignedIn
from tests.helpers import CSRF, PASSWORD, create_user, new_client, sign_in


def test_login_is_limited_per_ip() -> None:
    client = new_client()
    for attempt in range(10):
        response = client.post(
            "/api/auth/login", json={"username": f"user{attempt}", "password": "wrong-pass"}
        )
        assert response.status_code == 401
    blocked = client.post("/api/auth/login", json={"username": "user99", "password": "x"})
    assert blocked.status_code == 429
    assert int(blocked.headers["Retry-After"]) >= 1


def test_login_failures_are_limited_per_username_even_with_the_right_password() -> None:
    create_user("alice")
    client = new_client()
    for _ in range(5):
        response = client.post(
            "/api/auth/login", json={"username": "alice", "password": "wrong-pass"}
        )
        assert response.status_code == 401
    right_password = client.post(
        "/api/auth/login", json={"username": "ALICE", "password": PASSWORD}
    )
    assert right_password.status_code == 429


def test_refresh_is_limited_per_ip() -> None:
    create_user("alice")
    client = new_client()
    sign_in(client, "alice")
    for _ in range(30):
        assert client.post("/api/auth/refresh", headers=CSRF).status_code == 200
    assert client.post("/api/auth/refresh", headers=CSRF).status_code == 429


def test_invite_lookup_and_redemption_share_a_per_ip_limit(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    token = admin.post("/api/admin/invites").json()["token"]
    guest = new_client()
    for _ in range(10):
        assert guest.get("/api/invites/guess").status_code == 404
    response = guest.post(
        f"/api/invites/{token}/redeem",
        json={"username": "bob", "password": PASSWORD, "timezone": "UTC"},
    )
    assert response.status_code == 429
