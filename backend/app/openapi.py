"""The API reference, docs/openapi.json, generated from the routes.

The running app serves no schema (see main.py), so the committed file is the reference, and
tests/test_openapi.py fails when it falls behind the routes. Regenerate it from backend/:

    DATABASE_URL=postgresql://unused/unused JWT_SECRET=$(openssl rand -hex 32) \\
        uv run python -m app.openapi

Settings are checked on import, so both variables must be set; nothing connects to them.
"""

import json
import tomllib
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from fastapi.dependencies.models import Dependant
from fastapi.openapi.utils import get_openapi
from fastapi.routing import APIRoute, RouteContext, iter_route_contexts

from app.deps import (
    CSRF_HEADER,
    collection_access,
    deck_editor,
    deck_owner,
    require_admin,
    require_csrf_header,
)
from app.main import LARGER_BODIES, MAX_BODY_BYTES, app
from app.routers.auth import REFRESH_COOKIE, REFRESH_COOKIE_PATH

BACKEND_DIR = Path(__file__).resolve().parent.parent
SPEC_PATH = BACKEND_DIR.parent / "docs" / "openapi.json"
MIB = 1024 * 1024

DESCRIPTION = f"""\
The JSON API behind the Engram web app. The page and the API share one origin, and every
API path starts with `/api`.

## Signing in

1. `POST /api/auth/login` (or redeeming an invite) returns an `access_token` and sets the
   `{REFRESH_COOKIE}` cookie: httpOnly, Secure, SameSite=Lax, `Path={REFRESH_COOKIE_PATH}`.
2. Send `Authorization: Bearer <access_token>` with every other request. Access tokens last
   15 minutes.
3. On a 401, call `POST /api/auth/refresh` with the cookie and the header
   `{CSRF_HEADER}: 1`, then retry the request once. Each refresh token works once, so run
   one refresh at a time: presenting a used token signs out every session from that sign-in.

A password change, or an admin deactivating the account, ends every session at once, access
tokens included.

## Errors

An error is JSON with a `detail` sentence written to be shown to the user as it is. A 422
adds `errors`, one `{{field, message}}` per problem, with paths like `cards[12].options`.

## Decks and roles

Each member of a deck is its owner, an editor or a viewer. A deck you aren't a member of
answers 404, exactly like one that doesn't exist. A member whose role is too low gets 403.

## Collections

A deck named `Java::Day 1` is the deck `Day 1` in the collection `Java`. Collections aren't
stored: `/api/collections` routes take the path as `?path=Java` and act on the decks under it
that you're a member of. Changing names or members needs you to own a deck, and decks you
don't own are left alone and counted as `skipped`.

## Limits

Request bodies are capped at 2 MiB (64 MiB for an Anki upload) and need a `Content-Length`
(411 without one). Sign-in, refresh and invite routes are rate-limited per client IP; a 429
carries `Retry-After` in seconds.
"""

TAGS = [
    {"name": "health", "description": "Probes for Kubernetes and compose."},
    {"name": "auth", "description": "Signing in and out, and refreshing the access token."},
    {"name": "invites", "description": "Signing up with an invite link from an admin."},
    {"name": "me", "description": "The signed-in user's account and statistics."},
    {"name": "admin", "description": "Invites and accounts. Admins only."},
    {"name": "decks", "description": "Decks, deck files, forks and imports."},
    {"name": "members", "description": "Who a deck is shared with, and their roles."},
    {"name": "cards", "description": "Cards and tags in a deck."},
    {"name": "reviews", "description": "Studying: the next card, ratings and quiz answers."},
    {
        "name": "collections",
        "description": "Every deck under a `::` path at once: studying, sharing and settings.",
    },
]

INVITE_GONE = "The invite is unknown, used, expired or revoked; all four look the same."
CARD_GONE = "The card isn't in this deck."
NEW_CARD_LIMIT = "The card is new and today's new-card limit for the deck is reached."
NOT_AN_OWNER = "You don't own any deck in the collection."

# Errors a route raises itself. Those shared by every route of a kind (401, the deck 404,
# role and admin 403s, 413, 429) come from its dependencies in _errors().
ROUTE_ERRORS: dict[str, dict[int, str]] = {
    "login": {401: "Wrong username or password, or the account is deactivated."},
    "refresh": {
        401: "No refresh cookie, or it expired, was revoked or was already used. The "
        "cookie is cleared."
    },
    "get_invite": {404: INVITE_GONE},
    "redeem_invite": {404: INVITE_GONE, 409: "The username is taken."},
    "change_password": {400: "The current password is wrong."},
    "revoke_invite": {404: "No such invite.", 409: "The invite was already used."},
    "update_user": {
        404: "No such account.",
        409: "Admins can't deactivate or demote themselves.",
    },
    "import_anki_deck": {422: "The upload isn't an Anki collection Engram can read."},
    "share_deck": {404: "No user has that username.", 409: "They already have access."},
    "change_member_role": {404: "That user isn't a member.", 409: "The owner's role can't change."},
    "remove_member": {
        403: "Only the owner can remove other members.",
        404: "That user isn't a member.",
        409: "The owner can't leave; delete the deck instead.",
    },
    "list_cards": {422: "The cursor is invalid."},
    "get_card": {404: CARD_GONE},
    "update_card": {404: CARD_GONE},
    "delete_card": {404: CARD_GONE},
    "rate_card": {
        404: CARD_GONE,
        409: f"A quiz card without a correct answer first, or rated Again. Or: {NEW_CARD_LIMIT}",
    },
    "answer_quiz": {
        404: CARD_GONE,
        409: f"The card isn't a quiz card. Or: {NEW_CARD_LIMIT}",
        422: "The options aren't this card's (it may have been edited), or more than one was "
        "picked for a single-answer question.",
    },
    "rename_collection": {
        403: NOT_AN_OWNER,
        422: "The name is only `::`, or a deck's new name would pass 200 characters.",
    },
    "delete_collection": {403: NOT_AN_OWNER},
    "rate_collection_card": {
        404: "The card isn't in the collection.",
        409: f"A quiz card without a correct answer first, or rated Again. Or: {NEW_CARD_LIMIT}",
    },
    "answer_collection_quiz": {
        404: "The card isn't in the collection.",
        409: f"The card isn't a quiz card. Or: {NEW_CARD_LIMIT}",
        422: "The options aren't this card's (it may have been edited), or more than one was "
        "picked for a single-answer question.",
    },
    "share_collection": {
        403: NOT_AN_OWNER,
        404: "No user has that username.",
        409: "It's you, or they already have that role on every deck you own there.",
    },
    "remove_collection_member": {
        403: NOT_AN_OWNER,
        404: "They have no access to any deck you own there.",
        409: "You're leaving, but you own every deck in the collection.",
    },
}


def _api_routes() -> Iterator[tuple[str, RouteContext]]:
    # Route contexts carry the full path and the router-level dependencies merged in.
    for route in iter_route_contexts(app.routes):
        if isinstance(route.original_route, APIRoute):
            yield route.original_route.name, route


def _calls(dependant: Dependant) -> Iterator[Any]:
    for dependency in dependant.dependencies:
        yield dependency.call
        yield from _calls(dependency)


def _errors(name: str, route: RouteContext, operation: dict[str, Any]) -> dict[int, list[str]]:
    calls = list(_calls(route.dependant))
    errors: dict[int, list[str]] = {}
    if "security" in operation:
        errors[401] = ["The access token is missing or expired. Refresh it and retry."]
    if require_admin in calls:
        errors[403] = ["You aren't an admin."]
    if require_csrf_header in calls:
        errors[403] = [f"The `{CSRF_HEADER}: 1` header is missing."]
    if deck_editor in calls:
        errors[403] = ["Your role on the deck is viewer; this needs editor or owner."]
    if deck_owner in calls:
        errors[403] = ["Only the deck's owner can do this."]
    if "{deck_id}" in (route.path or ""):
        errors[404] = ["The deck doesn't exist, or you aren't a member."]
    if collection_access in calls:
        errors[404] = ["You aren't a member of any deck in the collection."]
    if "requestBody" in operation:
        limit = LARGER_BODIES.get(route.path or "", (MAX_BODY_BYTES,))[0]
        errors[413] = [f"The body is larger than {limit // MIB} MiB."]
    if any(getattr(call, "__qualname__", "").startswith("limit_by_ip.") for call in calls):
        errors[429] = ["Too many requests from this IP. Wait `Retry-After` seconds."]
    if "422" in operation["responses"]:
        errors[422] = ["The request doesn't match the schema; `errors` lists each problem."]
    for code, description in ROUTE_ERRORS.get(name, {}).items():
        errors.setdefault(code, []).append(description)
    return errors


def _error_response(code: int, descriptions: list[str]) -> dict[str, Any]:
    schema = "ValidationError" if code == 422 else "Error"
    response: dict[str, Any] = {
        "description": " ".join(descriptions),
        "content": {"application/json": {"schema": {"$ref": f"#/components/schemas/{schema}"}}},
    }
    if code == 429:
        response["headers"] = {
            "Retry-After": {"description": "Seconds to wait.", "schema": {"type": "integer"}}
        }
    return response


def build_spec() -> dict[str, Any]:
    pyproject = tomllib.loads((BACKEND_DIR / "pyproject.toml").read_text())
    spec = get_openapi(
        title="Engram API",
        version=pyproject["project"]["version"],
        description=DESCRIPTION,
        routes=app.routes,
        tags=TAGS,
    )

    routes = {
        (method.lower(), route.path): (name, route)
        for name, route in _api_routes()
        for method in route.methods or ()
    }
    names = [name for name, _ in routes.values()]
    duplicates = {name for name in names if names.count(name) > 1}
    unknown = set(ROUTE_ERRORS) - set(names)
    if duplicates or unknown:
        raise ValueError(f"Duplicate route names {duplicates}; ROUTE_ERRORS for {unknown}")

    for path, operations in spec["paths"].items():
        for method, operation in operations.items():
            name, route = routes[method, path]
            operation["operationId"] = name
            # A docstring's first paragraph is the summary; the rest, if any, the description.
            summary, _, description = operation.pop("description", "").partition("\n\n")
            if summary:
                operation["summary"] = summary.replace("\n", " ")
            if description:
                operation["description"] = description
            for parameter in operation.get("parameters", []):
                if parameter["name"] == REFRESH_COOKIE:
                    parameter["description"] = "Set by sign-in; the browser sends it."
                elif parameter["name"] == CSRF_HEADER:
                    parameter["description"] = "Must be `1`."
            responses = operation["responses"]
            for code, descriptions in _errors(name, route, operation).items():
                responses[str(code)] = _error_response(code, descriptions)
            operation["responses"] = dict(sorted(responses.items()))

    schemas = spec["components"]["schemas"]
    del schemas["HTTPValidationError"]
    schemas["Error"] = {
        "type": "object",
        "required": ["detail"],
        "properties": {"detail": {"type": "string"}},
    }
    schemas["ValidationError"] = {
        "type": "object",
        "required": ["detail"],
        "properties": {
            "detail": {"type": "string", "description": "The first problem, as a sentence."},
            "errors": {
                "description": "Every problem, when the request doesn't match the schema. "
                "Absent when the route itself rejects the request.",
                "type": "array",
                "items": {
                    "type": "object",
                    "required": ["field", "message"],
                    "properties": {
                        "field": {"type": "string", "examples": ["cards[12].options"]},
                        "message": {"type": "string"},
                    },
                },
            },
        },
    }
    spec["components"]["schemas"] = dict(sorted(schemas.items()))
    spec["components"]["securitySchemes"]["HTTPBearer"].update(
        bearerFormat="JWT",
        description="The access token from sign-in or refresh.",
    )
    return spec


def render_spec() -> str:
    return json.dumps(build_spec(), indent=2, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    SPEC_PATH.write_text(render_spec())
    print(f"Wrote {SPEC_PATH}")  # noqa: T201
