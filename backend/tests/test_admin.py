from app.models import GlobalRole
from tests.conftest import SignedIn
from tests.helpers import CSRF, new_client, sign_in


def test_admin_lists_users(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    signed_in("alice")
    users = admin.get("/api/admin/users").json()
    assert [(user["username"], user["role"]) for user in users] == [
        ("alice", "user"),
        ("root", "admin"),
    ]
    assert "password_hash" not in users[0]


def test_deactivating_a_user_ends_their_sessions_immediately(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    alice, alice_user = signed_in("alice")

    response = admin.patch(f"/api/admin/users/{alice_user.id}", json={"is_active": False})
    assert response.status_code == 200
    assert alice.get("/api/me").status_code == 401
    assert alice.post("/api/auth/refresh", headers=CSRF).status_code == 401

    admin.patch(f"/api/admin/users/{alice_user.id}", json={"is_active": True})
    sign_in(new_client(), "alice")


def test_promoting_a_user_grants_admin_access(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    alice, alice_user = signed_in("alice")
    assert alice.get("/api/admin/users").status_code == 403
    admin.patch(f"/api/admin/users/{alice_user.id}", json={"role": "admin"})
    assert alice.get("/api/admin/users").status_code == 200


def test_admin_cannot_deactivate_or_demote_themselves(signed_in: SignedIn) -> None:
    admin, admin_user = signed_in("root", GlobalRole.admin)
    for change in ({"is_active": False}, {"role": "user"}):
        assert admin.patch(f"/api/admin/users/{admin_user.id}", json=change).status_code == 409
    assert admin.get("/api/admin/users").status_code == 200


def test_regular_users_cannot_manage_users(signed_in: SignedIn) -> None:
    alice, alice_user = signed_in("alice")
    assert alice.get("/api/admin/users").status_code == 403
    response = alice.patch(f"/api/admin/users/{alice_user.id}", json={"role": "admin"})
    assert response.status_code == 403
