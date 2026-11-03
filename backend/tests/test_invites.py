from datetime import timedelta

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.models import GlobalRole, Invite, User, utcnow
from app.security import hash_opaque_token
from tests.conftest import SignedIn
from tests.helpers import PASSWORD, new_client, sign_in

SIGNUP = {"username": "bob", "password": PASSWORD, "timezone": "Europe/Berlin"}


def _create_invite(admin: TestClient) -> str:
    response = admin.post("/api/admin/invites")
    assert response.status_code == 201
    token: str = response.json()["token"]
    return token


def test_invite_token_is_long_random_and_stored_hashed(signed_in: SignedIn, db: Session) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    token = _create_invite(admin)
    # 32 random bytes, base64url-encoded.
    assert len(token) >= 43
    stored = db.exec(select(Invite)).one()
    assert stored.token_hash == hash_opaque_token(token)
    assert token not in stored.model_dump_json()
    assert timedelta(days=6, hours=23) < stored.expires_at - utcnow() <= timedelta(days=7)


def test_redeem_creates_a_working_account(signed_in: SignedIn, db: Session) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    token = _create_invite(admin)

    guest = new_client()
    assert guest.get(f"/api/invites/{token}").status_code == 200
    response = guest.post(f"/api/invites/{token}/redeem", json=SIGNUP)
    assert response.status_code == 201
    assert response.json()["user"]["role"] == "user"

    bob = db.exec(select(User).where(User.username == "bob")).one()
    assert bob.timezone == "Europe/Berlin"
    assert bob.password_hash.startswith("$argon2id$")
    sign_in(new_client(), "bob")

    listed = admin.get("/api/admin/invites").json()
    assert [(invite["state"], invite["used_by"]) for invite in listed] == [("used", "bob")]


def test_invite_cannot_be_reused(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    token = _create_invite(admin)
    assert new_client().post(f"/api/invites/{token}/redeem", json=SIGNUP).status_code == 201

    second = new_client().post(
        f"/api/invites/{token}/redeem", json={**SIGNUP, "username": "mallory"}
    )
    assert second.status_code == 404
    assert new_client().get(f"/api/invites/{token}").status_code == 404


def test_expired_invite_is_rejected(signed_in: SignedIn, db: Session) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    token = _create_invite(admin)
    invite = db.exec(select(Invite)).one()
    invite.expires_at = utcnow() - timedelta(seconds=1)
    db.add(invite)
    db.commit()

    assert new_client().get(f"/api/invites/{token}").status_code == 404
    assert new_client().post(f"/api/invites/{token}/redeem", json=SIGNUP).status_code == 404
    assert admin.get("/api/admin/invites").json()[0]["state"] == "expired"


def test_revoked_invite_is_rejected(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    token = _create_invite(admin)
    invite_id = admin.get("/api/admin/invites").json()[0]["id"]
    assert admin.delete(f"/api/admin/invites/{invite_id}").status_code == 204

    assert new_client().post(f"/api/invites/{token}/redeem", json=SIGNUP).status_code == 404
    assert admin.get("/api/admin/invites").json()[0]["state"] == "revoked"


def test_non_admins_cannot_manage_invites(signed_in: SignedIn) -> None:
    admin, _ = signed_in("root", GlobalRole.admin)
    _create_invite(admin)
    invite_id = admin.get("/api/admin/invites").json()[0]["id"]
    user, _ = signed_in("alice")
    assert user.post("/api/admin/invites").status_code == 403
    assert user.get("/api/admin/invites").status_code == 403
    assert user.delete(f"/api/admin/invites/{invite_id}").status_code == 403
