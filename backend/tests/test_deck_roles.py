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


def test_viewer_cannot_share_rename_or_delete(team: Team) -> None:
    assert _owner_actions(team.viewer, team, team.editor_user) == [403, 403, 403, 403, 403]
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


def test_owner_can_do_everything(team: Team) -> None:
    assert _card_writes(team.owner, team) == [201, 200, 200, 204]
    assert _owner_actions(team.owner, team, team.viewer_user) == [201, 200, 204, 200, 204]


def test_every_member_can_read_export_fork_and_set_their_limit(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    for client in (team.owner, team.editor, team.viewer):
        assert client.get(deck).status_code == 200
        assert client.get(f"{deck}/cards").status_code == 200
        assert client.get(f"{deck}/cards/{team.card_id}").status_code == 200
        assert client.get(f"{deck}/tags").status_code == 200
        assert client.get(f"{deck}/members").status_code == 200
        assert client.get(f"{deck}/export").status_code == 200
        assert client.post(f"{deck}/fork").status_code == 201
        assert client.put(f"{deck}/me", json={"new_cards_per_day": 5}).status_code == 200


def test_new_card_limit_is_per_member(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    team.viewer.put(f"{deck}/me", json={"new_cards_per_day": 5})
    assert team.viewer.get(deck).json()["new_cards_per_day"] == 5
    assert team.owner.get(deck).json()["new_cards_per_day"] == 20


def test_role_change_takes_effect_immediately(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    team.owner.patch(f"{deck}/members/{team.viewer_user.id}", json={"role": "editor"})
    assert team.viewer.post(f"{deck}/cards", json=BASIC_CARD).status_code == 201
    team.owner.patch(f"{deck}/members/{team.viewer_user.id}", json={"role": "viewer"})
    assert team.viewer.post(f"{deck}/cards", json=BASIC_CARD).status_code == 403


def test_revoked_member_loses_access(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    assert team.owner.delete(f"{deck}/members/{team.editor_user.id}").status_code == 204
    assert team.editor.get(deck).status_code == 404
    assert team.editor.get(f"{deck}/cards/{team.card_id}").status_code == 404
    assert team.deck_id not in {d["id"] for d in team.editor.get("/api/decks").json()}


def test_members_can_leave_but_not_remove_others(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    assert team.viewer.delete(f"{deck}/members/{team.editor_user.id}").status_code == 403
    assert team.viewer.delete(f"{deck}/members/{team.viewer_user.id}").status_code == 204
    assert team.viewer.get(deck).status_code == 404


def test_owner_role_cannot_be_changed_or_removed(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    owner_id = team.owner_user.id
    assert (
        team.owner.patch(f"{deck}/members/{owner_id}", json={"role": "viewer"}).status_code == 409
    )
    assert team.owner.delete(f"{deck}/members/{owner_id}").status_code == 409


def test_owner_cannot_grant_ownership(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    response = team.owner.patch(f"{deck}/members/{team.viewer_user.id}", json={"role": "owner"})
    assert response.status_code == 422
    share = team.owner.post(f"{deck}/members", json={"username": "bob", "role": "owner"})
    assert share.status_code == 422


def test_sharing_with_unknown_or_existing_user(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    unknown = team.owner.post(f"{deck}/members", json={"username": "ghost", "role": "viewer"})
    assert unknown.status_code == 404
    again = team.owner.post(f"{deck}/members", json={"username": "VIC", "role": "editor"})
    assert again.status_code == 409


def test_deleting_a_deck_removes_access_for_every_member(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    assert team.owner.delete(deck).status_code == 204
    for client in (team.owner, team.editor, team.viewer):
        assert client.get(deck).status_code == 404
        assert client.get(f"{deck}/cards/{team.card_id}").status_code == 404
        assert client.get("/api/decks").json() == []
