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
