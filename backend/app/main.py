from fastapi import APIRouter, FastAPI
from sqlalchemy import text

from app.db import SessionDep
from app.deps import PUBLIC
from app.routers import admin, auth, invites, me

# No interactive docs in production: they would be the one unauthenticated page listing every route.
app = FastAPI(title="Engram", docs_url=None, redoc_url=None, openapi_url=None)

api = APIRouter(prefix="/api")


@api.get("/health", openapi_extra=PUBLIC, tags=["health"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@api.get("/health/ready", openapi_extra=PUBLIC, tags=["health"])
def ready(session: SessionDep) -> dict[str, str]:
    session.connection().execute(text("SELECT 1"))
    return {"status": "ok"}


for module in (auth, invites, me, admin):
    api.include_router(module.router)

app.include_router(api)
