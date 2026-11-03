from collections.abc import Mapping
from typing import Any

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.db import engine
from app.main import app
from app.models import GlobalRole, User
from app.routers.auth import REFRESH_COOKIE
from app.security import hash_password

PASSWORD = "correct horse battery"
CSRF = {"X-Engram-CSRF": "1"}


def new_client() -> TestClient:
    # https so the client stores and sends the Secure refresh cookie.
    return TestClient(app, base_url="https://testserver")


def create_user(
    username: str, password: str = PASSWORD, role: GlobalRole = GlobalRole.user
) -> User:
    with Session(engine) as session:
        user = User(username=username, password_hash=hash_password(password), role=role)
        session.add(user)
        session.commit()
        session.refresh(user)
        return user


def sign_in(client: TestClient, username: str, password: str = PASSWORD) -> str:
    response = client.post("/api/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200, response.text
    access_token: str = response.json()["access_token"]
    client.headers["Authorization"] = f"Bearer {access_token}"
    return access_token


def client_with_refresh_cookie(cookie: str) -> TestClient:
    client = new_client()
    # http.cookiejar files dotless hosts under "<host>.local".
    client.cookies.set(REFRESH_COOKIE, cookie, domain="testserver.local")
    return client


BASIC_CARD = {"type": "basic", "front": "Capital of Morocco?", "back": "Rabat", "tags": ["geo"]}
QUIZ_CARD = {
    "type": "quiz",
    "question": "Which are prime?",
    "select_all": True,
    "options": [
        {"text": "2", "correct": True},
        {"text": "4", "correct": False},
        {"text": "7", "correct": True},
    ],
    "explanation": "4 = 2 x 2.",
    "tags": ["math"],
}


def create_deck(client: TestClient, name: str = "Geography") -> str:
    response = client.post("/api/decks", json={"name": name})
    assert response.status_code == 201, response.text
    deck_id: str = response.json()["id"]
    return deck_id


def create_card(client: TestClient, deck_id: str, card: Mapping[str, Any]) -> str:
    response = client.post(f"/api/decks/{deck_id}/cards", json=card)
    assert response.status_code == 201, response.text
    card_id: str = response.json()["id"]
    return card_id


def share(owner: TestClient, deck_id: str, username: str, role: str) -> None:
    response = owner.post(
        f"/api/decks/{deck_id}/members", json={"username": username, "role": role}
    )
    assert response.status_code == 201, response.text
