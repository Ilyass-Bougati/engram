"""The web app, served by the API process on the same origin as /api.

The refresh cookie and the CSRF header only work when the page and the API share an origin,
so the image carries the frontend build and this module serves it. In development the build
isn't there and only the API runs; Vite serves the page and proxies /api instead.
"""

from pathlib import Path

from starlette.datastructures import MutableHeaders
from starlette.exceptions import HTTPException
from starlette.responses import Response
from starlette.routing import Match, Mount
from starlette.staticfiles import StaticFiles
from starlette.types import ASGIApp, Message, Receive, Scope, Send

# Where the image puts `vite build`'s output.
WEB_DIR = Path(__file__).resolve().parent.parent / "web"

# Vite puts a content hash in every file name under assets/, so a cached copy is never stale.
IMMUTABLE = "public, max-age=31536000, immutable"

# Scripts only from this origin, never inline. Styles allow inline attributes because KaTeX
# and code highlighting position and color with style="…". Card images may come from any
# https: address (cards link them); everything else is this origin only.
CONTENT_SECURITY_POLICY = "; ".join(
    [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' https: data:",
        "font-src 'self' data:",
        "connect-src 'self'",
        "object-src 'none'",
        "base-uri 'none'",
        "form-action 'self'",
        "frame-ancestors 'none'",
    ]
)

SECURITY_HEADERS = {
    "Content-Security-Policy": CONTENT_SECURITY_POLICY,
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    # Only takes effect over HTTPS, so plain http on 127.0.0.1 is unaffected.
    "Strict-Transport-Security": "max-age=31536000",
}


class SecurityHeaders:
    # On every response, API included: harmless on JSON, and nothing can slip through
    # without them.
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                for name, value in SECURITY_HEADERS.items():
                    headers.setdefault(name, value)
            await send(message)

        await self.app(scope, receive, send_with_headers)


class WebApp(StaticFiles):
    # A file from the build, or index.html for any other path, so a link like /decks/<id>
    # opens the app and its router shows the right page. A missing asset stays a 404.
    async def get_response(self, path: str, scope: Scope) -> Response:
        try:
            response = await super().get_response(path, scope)
        except HTTPException as error:
            if error.status_code != 404 or path.startswith("assets/"):
                raise
            response = await super().get_response("index.html", scope)
            path = "index.html"
        # Everything outside assets/ (index.html above all) is checked on every visit, so a
        # release shows up on the next load.
        response.headers["Cache-Control"] = IMMUTABLE if path.startswith("assets/") else "no-cache"
        return response


class WebMount(Mount):
    # Never claims /api paths: an unknown API path or a wrong method keeps its JSON 404 or 405
    # instead of turning into the app's page.
    def matches(self, scope: Scope) -> tuple[Match, Scope]:
        path: str = scope.get("path", "")
        if path == "/api" or path.startswith("/api/"):
            return Match.NONE, {}
        return super().matches(scope)


def web_mount(directory: Path = WEB_DIR) -> WebMount | None:
    if not (directory / "index.html").is_file():
        return None
    return WebMount("/", app=WebApp(directory=directory), name="web")
