import hashlib
import secrets
import threading
import uuid
from datetime import datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.config import settings
from app.models import utcnow

ACCESS_TOKEN_TTL = timedelta(minutes=15)
JWT_ALGORITHM = "HS256"

# OWASP's minimum argon2id profile (19 MiB, t=2). The semaphore caps concurrent hashes so a
# burst of logins can't push the backend past its 384 MiB memory limit.
_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
_hash_slots = threading.BoundedSemaphore(4)


def hash_password(password: str) -> str:
    with _hash_slots:
        return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    with _hash_slots:
        try:
            return _hasher.verify(password_hash, password)
        except VerifyMismatchError:
            return False


# Verified against when the username doesn't exist, so both failure paths cost one argon2 run.
DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(16))


def new_opaque_token() -> tuple[str, str]:
    token = secrets.token_urlsafe(32)
    return token, hash_opaque_token(token)


def hash_opaque_token(token: str) -> str:
    # These tokens carry 256 bits of entropy, so a fast hash is enough; argon2 is for passwords.
    return hashlib.sha256(token.encode()).hexdigest()


def create_access_token(user_id: uuid.UUID, token_version: int) -> str:
    now = utcnow()
    claims = {
        "sub": str(user_id),
        "ver": token_version,
        "iat": now,
        "exp": now + ACCESS_TOKEN_TTL,
    }
    return jwt.encode(claims, settings.jwt_secret.get_secret_value(), algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> tuple[uuid.UUID, int] | None:
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret.get_secret_value(),
            algorithms=[JWT_ALGORITHM],
            options={"require": ["sub", "ver", "exp"]},
        )
        return uuid.UUID(claims["sub"]), int(claims["ver"])
    except (jwt.InvalidTokenError, ValueError, TypeError):
        return None


def refresh_token_expiry() -> datetime:
    return utcnow() + timedelta(days=settings.refresh_token_days)
