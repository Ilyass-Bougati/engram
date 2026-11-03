from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import Team
from tests.helpers import BASIC_CARD, create_deck
from tests.test_deck_roles import EXAMPLE_DECK
from tests.test_route_auth import api_routes

# A valid body for every route that takes one, so a 404 can only come from the access check.
VALID_BODIES: dict[tuple[str, str], object] = {
    ("PATCH", "/api/decks/{deck_id}"): {"name": "Hijacked"},
    ("PUT", "/api/decks/{deck_id}/me"): {"new_cards_per_day": 1},
    ("POST", "/api/decks/{deck_id}/import"): EXAMPLE_DECK,
    ("POST", "/api/decks/{deck_id}/members"): {"username": "bob", "role": "editor"},
    ("PATCH", "/api/decks/{deck_id}/members/{user_id}"): {"role": "editor"},
    ("POST", "/api/decks/{deck_id}/cards"): BASIC_CARD,
    ("PUT", "/api/decks/{deck_id}/cards/{card_id}"): {**BASIC_CARD, "front": "Hijacked"},
}


def _deck_routes() -> list[tuple[str, str]]:
    return sorted(
        (method, route.path)
        for route in api_routes(app)
        if route.path and "{deck_id}" in route.path
        for method in route.methods or ()
    )


def _request(client: TestClient, method: str, path: str, ids: dict[str, str]) -> int:
    url = path.format(**ids)
    body = VALID_BODIES.get((method, path))
    return client.request(method, url, json=body).status_code


def test_outsider_gets_404_on_every_deck_route(team: Team) -> None:
    ids = {
        "deck_id": team.deck_id,
        "card_id": team.card_id,
        "user_id": str(team.viewer_user.id),
    }
    routes = _deck_routes()
    assert len(routes) >= 15
    statuses = {
        f"{method} {path}": _request(team.outsider, method, path, ids) for method, path in routes
    }
    assert statuses == dict.fromkeys(statuses, 404)
    _assert_untouched(team)


def test_card_from_another_deck_is_404_through_your_own_deck(team: Team) -> None:
    own_deck = create_deck(team.outsider, "Mine")
    ids = {"deck_id": own_deck, "card_id": team.card_id, "user_id": str(team.viewer_user.id)}
    card_routes = [(m, p) for m, p in _deck_routes() if "{card_id}" in p]
    assert card_routes
    statuses = {f"{m} {p}": _request(team.outsider, m, p, ids) for m, p in card_routes}
    assert statuses == dict.fromkeys(statuses, 404)
    _assert_untouched(team)


def test_member_routes_reject_users_outside_the_deck(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    outsider_id = team.outsider_user.id
    assert (
        team.owner.patch(f"{deck}/members/{outsider_id}", json={"role": "editor"}).status_code
        == 404
    )
    assert team.owner.delete(f"{deck}/members/{outsider_id}").status_code == 404


def test_missing_and_foreign_decks_look_the_same(team: Team) -> None:
    missing = team.outsider.get("/api/decks/00000000-0000-4000-8000-000000000000")
    foreign = team.outsider.get(f"/api/decks/{team.deck_id}")
    assert missing.status_code == foreign.status_code == 404
    assert missing.json() == foreign.json()


def _assert_untouched(team: Team) -> None:
    deck = team.owner.get(f"/api/decks/{team.deck_id}").json()
    assert (deck["name"], deck["card_count"]) == ("Geography", 2)
    card = team.owner.get(f"/api/decks/{team.deck_id}/cards/{team.card_id}").json()
    assert card["front"] == BASIC_CARD["front"]
    members = team.owner.get(f"/api/decks/{team.deck_id}/members").json()
    assert {m["username"] for m in members} == {"alice", "erin", "vic"}
    outsider_decks = team.outsider.get("/api/decks").json()
    assert team.deck_id not in {d["id"] for d in outsider_decks}
    # A fork attempt must not have produced a copy either.
    assert all(d["name"] == "Mine" for d in outsider_decks)
