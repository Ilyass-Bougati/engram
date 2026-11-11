from collections.abc import Iterator

from fastapi import APIRouter, FastAPI
from fastapi.dependencies.models import Dependant
from fastapi.routing import APIRoute, RouteContext, iter_route_contexts

from app.deps import DECK_ROLE_DEPENDENCIES, PUBLIC, collection_access, get_current_user
from app.main import app

EXPECTED_PUBLIC_ROUTES = {
    ("GET", "/api/health"),
    ("GET", "/api/health/ready"),
    ("POST", "/api/auth/login"),
    ("POST", "/api/auth/refresh"),
    ("POST", "/api/auth/logout"),
    ("GET", "/api/invites/{token}"),
    ("POST", "/api/invites/{token}/redeem"),
}


def _depends_on(dependant: Dependant, target: object) -> bool:
    return any(
        dependency.call is target or _depends_on(dependency, target)
        for dependency in dependant.dependencies
    )


def api_routes(application: FastAPI) -> Iterator[RouteContext]:
    # Included routers are resolved lazily; route contexts carry the effective path and the
    # router-level dependencies merged in.
    for route in iter_route_contexts(application.routes):
        if isinstance(route.original_route, APIRoute):
            yield route


def _is_public(route: RouteContext) -> bool:
    return bool(route.openapi_extra and route.openapi_extra.get("x-public"))


def unprotected_routes(application: FastAPI) -> list[str]:
    return [
        f"{sorted(route.methods or ())} {route.path}"
        for route in api_routes(application)
        if not _is_public(route) and not _depends_on(route.dependant, get_current_user)
    ]


def test_every_route_is_authenticated_or_explicitly_public() -> None:
    assert unprotected_routes(app) == []


def test_every_deck_route_checks_deck_membership() -> None:
    unchecked = [
        f"{sorted(route.methods or ())} {route.path}"
        for route in api_routes(app)
        if route.path
        and "{deck_id}" in route.path
        and not any(_depends_on(route.dependant, dep) for dep in DECK_ROLE_DEPENDENCIES)
    ]
    assert unchecked == []


def test_every_collection_route_resolves_the_callers_decks() -> None:
    unchecked = [
        f"{sorted(route.methods or ())} {route.path}"
        for route in api_routes(app)
        if route.path
        and route.path.startswith("/api/collections")
        and not _depends_on(route.dependant, collection_access)
    ]
    assert unchecked == []


def test_card_and_member_routes_are_nested_under_a_deck() -> None:
    # Card and member IDs are only ever resolved inside a deck the caller can access, or
    # inside the decks of a collection the caller is a member of.
    loose = [
        route.path
        for route in api_routes(app)
        if route.path
        and ("{card_id}" in route.path or "/members" in route.path)
        and "{deck_id}" not in route.path
        and not _depends_on(route.dependant, collection_access)
    ]
    assert loose == []


def test_public_routes_are_exactly_the_expected_set() -> None:
    public = {
        (method, route.path)
        for route in api_routes(app)
        if _is_public(route)
        for method in route.methods or ()
    }
    assert public == EXPECTED_PUBLIC_ROUTES


def test_checker_flags_a_route_without_auth() -> None:
    router = APIRouter()

    @router.get("/leaky")
    def leaky() -> None:
        return None

    @router.get("/open", openapi_extra=PUBLIC)
    def open_route() -> None:
        return None

    probe = FastAPI()
    probe.include_router(router)
    assert unprotected_routes(probe) == ["['GET'] /leaky"]
