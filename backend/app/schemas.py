import uuid
import zoneinfo
from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, StringConstraints

from app.models import GlobalRole

_TIMEZONES = frozenset(zoneinfo.available_timezones())


def _known_timezone(name: str) -> str:
    if name not in _TIMEZONES:
        raise ValueError(f"unknown timezone {name!r}; use an IANA name such as Europe/Paris")
    return name


Username = Annotated[
    str, StringConstraints(min_length=3, max_length=32, pattern=r"^[A-Za-z0-9_.-]+$")
]
# The upper bound keeps a single request from turning argon2 into a CPU sink.
Password = Annotated[str, StringConstraints(min_length=10, max_length=256)]
Timezone = Annotated[str, AfterValidator(_known_timezone)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    username: str
    role: GlobalRole
    timezone: str
    created_at: datetime


class SessionResponse(BaseModel):
    access_token: str
    user: UserPublic
