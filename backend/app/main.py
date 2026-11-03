from fastapi import APIRouter, FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text
from starlette.types import ASGIApp, Receive, Scope, Send

from app.db import SessionDep
from app.deps import PUBLIC
from app.models import CardKind
from app.routers import admin, auth, cards, decks, invites, me, members, reviews
from app.routers.decks import ANKI_IMPORT_PATH, MAX_ANKI_UPLOAD_BYTES
from app.web import SecurityHeaders, web_mount

# JSON deck imports are the largest ordinary bodies. A proxy in front may cap lower, never higher.
MAX_BODY_BYTES = 2 * 1024 * 1024
LARGER_BODIES = {
    # The browser uploads only the collection from an .apkg, gzipped; media stays behind.
    ANKI_IMPORT_PATH: (
        MAX_ANKI_UPLOAD_BYTES,
        "The Anki collection is larger than 64 MiB. Export smaller subdecks from Anki.",
    ),
}


class BodySizeLimit:
    # Checked from Content-Length before FastAPI reads the body into memory. Bodies without a
    # length (chunked) are refused, since browsers always send one for fetch() with a string.
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http" and scope["method"] in {"POST", "PUT", "PATCH"}:
            headers = dict(scope["headers"])
            length = headers.get(b"content-length")
            problem = None
            if length is None:
                if headers.get(b"transfer-encoding"):
                    problem = (status.HTTP_411_LENGTH_REQUIRED, "Send a Content-Length header.")
            else:
                limit, message = LARGER_BODIES.get(
                    scope["path"],
                    (
                        MAX_BODY_BYTES,
                        "The request body is larger than 2 MiB. Split the deck into smaller files.",
                    ),
                )
                if not length.isdigit() or int(length) > limit:
                    problem = (status.HTTP_413_CONTENT_TOO_LARGE, message)
            if problem:
                response = JSONResponse({"detail": problem[1]}, problem[0])
                await response(scope, receive, send)
                return
        await self.app(scope, receive, send)


CARD_TYPES = {kind.value for kind in CardKind}


def _field_path(location: tuple[int | str, ...]) -> str:
    path = ""
    for index, part in enumerate(location):
        if isinstance(part, int):
            path += f"[{part}]"
        # Pydantic puts the discriminator value of a tagged union in the location
        # (cards.3.quiz.options, or quiz.options for a single card); it isn't a field the
        # user wrote, so drop it.
        elif part in CARD_TYPES and (index == 0 or isinstance(location[index - 1], int)):
            continue
        else:
            path += f".{part}" if path else part
    return path


# No interactive docs in production: they would be the one unauthenticated page listing
# every route.
app = FastAPI(title="Engram", docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(BodySizeLimit)
app.add_middleware(SecurityHeaders)


@app.exception_handler(RequestValidationError)
async def explain_validation_error(request: Request, error: RequestValidationError) -> JSONResponse:
    # One readable sentence that names the bad field (cards[12].options: ...), plus the full
    # list. Inputs are not echoed back, so a rejected password never appears in a response.
    problems = [
        {
            "field": _field_path(tuple(e["loc"][1:] if e["loc"][0] == "body" else e["loc"])),
            "message": e["msg"].removeprefix("Value error, "),
        }
        for e in error.errors()
    ]
    first = problems[0]
    detail = f"{first['field']}: {first['message']}" if first["field"] else first["message"]
    if len(problems) > 1:
        detail += f" (and {len(problems) - 1} more problem{'s' if len(problems) > 2 else ''})"
    return JSONResponse(
        {"detail": detail, "errors": problems}, status.HTTP_422_UNPROCESSABLE_CONTENT
    )


api = APIRouter(prefix="/api")


@api.get("/health", openapi_extra=PUBLIC, tags=["health"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@api.get("/health/ready", openapi_extra=PUBLIC, tags=["health"])
def ready(session: SessionDep) -> dict[str, str]:
    session.connection().execute(text("SELECT 1"))
    return {"status": "ok"}


for module in (auth, invites, me, admin, decks, members, cards, reviews):
    api.include_router(module.router)

app.include_router(api)

# The web app goes last, behind every API route. Without a build (development, tests) it's
# left out and only the API runs.
if (web := web_mount()) is not None:
    app.router.routes.append(web)
