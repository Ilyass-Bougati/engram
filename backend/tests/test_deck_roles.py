import json
from pathlib import Path

from fastapi.testclient import TestClient

from app.models import User
from tests.conftest import Team
from tests.helpers import BASIC_CARD

EXAMPLE_DECK = json.loads(
    (Path(__file__).resolve().parents[2] / "docs" / "example-deck.json").read_text()
)


def _card_writes(client: TestClient, team: Team) -> list[int]:
    deck = f"/api/decks/{team.deck_id}"
    edited = {**BASIC_CARD, "front": "Edited"}
    return [
        client.post(f"{deck}/cards", json=BASIC_CARD).status_code,
        client.put(f"{deck}/cards/{team.card_id}", json=edited).status_code,
        client.post(f"{deck}/import", json=EXAMPLE_DECK).status_code,
        client.delete(f"{deck}/cards/{team.quiz_card_id}").status_code,
    ]


def test_viewer_cannot_edit_cards(team: Team) -> None:
    assert _card_writes(team.viewer, team) == [403, 403, 403, 403]
    card = team.owner.get(f"/api/decks/{team.deck_id}/cards/{team.card_id}").json()
    assert card["front"] == BASIC_CARD["front"]
    assert team.owner.get(f"/api/decks/{team.deck_id}").json()["card_count"] == 2


def test_editor_can_edit_cards(team: Team) -> None:
    assert _card_writes(team.editor, team) == [201, 200, 200, 204]
    card = team.owner.get(f"/api/decks/{team.deck_id}/cards/{team.card_id}").json()
    assert card["front"] == "Edited"


def _owner_actions(client: TestClient, team: Team, other: User) -> list[int]:
    # `other` must be a member other than the caller: removing yourself is leaving, which
    # every member may do.
    deck = f"/api/decks/{team.deck_id}"
    outsider = {"username": "bob", "role": "viewer"}
    return [
        client.post(f"{deck}/members", json=outsider).status_code,
        client.patch(f"{deck}/members/{other.id}", json={"role": "editor"}).status_code,
        client.delete(f"{deck}/members/{other.id}").status_code,
        client.patch(deck, json={"name": "Renamed"}).status_code,
        client.delete(deck).status_code,
    ]


def test_editor_cannot_share_rename_or_delete(team: Team) -> None:
    assert _owner_actions(team.editor, team, team.viewer_user) == [403, 403, 403, 403, 403]
    _assert_deck_untouched(team)


def _assert_deck_untouched(team: Team) -> None:
    deck = team.owner.get(f"/api/decks/{team.deck_id}")
    assert deck.json()["name"] == "Geography"
    members = team.owner.get(f"/api/decks/{team.deck_id}/members").json()
    assert {(m["username"], m["role"]) for m in members} == {
        ("alice", "owner"),
        ("erin", "editor"),
        ("vic", "viewer"),
    }


def test_revoked_member_loses_access(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    assert team.owner.delete(f"{deck}/members/{team.editor_user.id}").status_code == 204
    assert team.editor.get(deck).status_code == 404
    assert team.editor.get(f"{deck}/cards/{team.card_id}").status_code == 404
    assert team.deck_id not in {d["id"] for d in team.editor.get("/api/decks").json()}


def test_deleting_a_deck_removes_access_for_every_member(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    assert team.owner.delete(deck).status_code == 204
    for client in (team.owner, team.editor, team.viewer):
        assert client.get(deck).status_code == 404
        assert client.get(f"{deck}/cards/{team.card_id}").status_code == 404
        assert client.get("/api/decks").json() == []
