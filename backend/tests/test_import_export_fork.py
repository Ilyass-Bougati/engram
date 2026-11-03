import copy
import json
from collections.abc import Callable
from typing import Any

from tests.conftest import SignedIn, Team
from tests.helpers import BASIC_CARD, create_card
from tests.test_deck_roles import EXAMPLE_DECK


def test_import_example_deck_creates_a_new_owned_deck(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    response = client.post("/api/decks/import", json=EXAMPLE_DECK)
    assert response.status_code == 201
    deck = response.json()
    assert (deck["name"], deck["role"], deck["card_count"]) == ("Linear algebra basics", "owner", 4)
    cards = client.get(f"/api/decks/{deck['id']}/cards").json()["cards"]
    assert [card["type"] for card in cards] == ["basic", "basic", "quiz", "quiz"]


def test_export_then_import_round_trips(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = client.post("/api/decks/import", json=EXAMPLE_DECK).json()["id"]
    exported = client.get(f"/api/decks/{deck_id}/export")
    assert exported.status_code == 200
    assert 'filename="linear-algebra-basics.engram.json"' in exported.headers["content-disposition"]
    # Tags come back sorted; everything else exactly as written.
    expected = copy.deepcopy(EXAMPLE_DECK)
    for card in expected["cards"]:
        card["tags"] = sorted(card["tags"])
    assert exported.json() == expected


def test_invalid_files_are_rejected_with_the_bad_field(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")

    def detail_for(mutate: Callable[[dict[str, Any]], object]) -> str:
        body = copy.deepcopy(EXAMPLE_DECK)
        mutate(body)
        response = client.post("/api/decks/import", json=body)
        assert response.status_code == 422
        message: str = response.json()["detail"]
        return message

    assert detail_for(
        lambda b: b["cards"][2]["options"].extend([{"text": "x", "correct": False}] * 6)
    ).startswith("cards[2].options: List should have at most 8 items")
    assert detail_for(lambda b: b["cards"][1].update(colour="red")).startswith(
        "cards[1].colour: Extra inputs are not permitted"
    )
    assert detail_for(lambda b: b["cards"][0].update(type="cloze")).startswith("cards[0]")
    assert detail_for(lambda b: b["cards"][3].update(select_all=False)).startswith(
        "cards[3]: a single-answer quiz card needs exactly one correct option (got 2)"
    )
    assert detail_for(lambda b: b.update(version=2)).startswith("version:")
    assert detail_for(lambda b: b["deck"].update(name="  ")).startswith("deck.name:")
    assert client.get("/api/decks").json() == []


def test_import_caps_card_count_and_body_size(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    too_many = {**EXAMPLE_DECK, "cards": [BASIC_CARD] * 5001}
    response = client.post("/api/decks/import", json=too_many)
    assert response.status_code == 422
    assert response.json()["detail"].startswith("cards: List should have at most 5000 items")

    huge = json.dumps(
        {**EXAMPLE_DECK, "deck": {"name": "x", "description": "y" * (2 * 1024 * 1024)}}
    )
    response = client.post(
        "/api/decks/import", content=huge, headers={"content-type": "application/json"}
    )
    assert response.status_code == 413
    assert client.get("/api/decks").json() == []


def test_fork_is_an_independent_copy_owned_by_the_forker(team: Team) -> None:
    fork = team.viewer.post(f"/api/decks/{team.deck_id}/fork")
    assert fork.status_code == 201
    fork_id = fork.json()["id"]
    assert (fork.json()["role"], fork.json()["card_count"]) == ("owner", 2)
    assert [m["username"] for m in team.viewer.get(f"/api/decks/{fork_id}/members").json()] == [
        "vic"
    ]
    # The forker now owns a full copy, answer key included.
    fork_cards = team.viewer.get(f"/api/decks/{fork_id}/cards").json()["cards"]
    assert {card["id"] for card in fork_cards}.isdisjoint({team.card_id, team.quiz_card_id})
    assert all("correct" in o for c in fork_cards if c["type"] == "quiz" for o in c["options"])
    assert team.owner.get(f"/api/decks/{fork_id}").status_code == 404

    original = f"/api/decks/{team.deck_id}"
    team.owner.put(f"{original}/cards/{team.card_id}", json={**BASIC_CARD, "front": "Changed"})
    create_card(team.owner, team.deck_id, BASIC_CARD)
    fork_fronts = [
        c.get("front") for c in team.viewer.get(f"/api/decks/{fork_id}/cards").json()["cards"]
    ]
    assert fork_fronts == [BASIC_CARD["front"], None]

    fork_card = next(c for c in fork_cards if c["type"] == "basic")["id"]
    team.viewer.put(f"/api/decks/{fork_id}/cards/{fork_card}", json={**BASIC_CARD, "front": "Mine"})
    assert team.owner.get(f"{original}/cards/{team.card_id}").json()["front"] == "Changed"

    team.owner.delete(original)
    assert team.viewer.get(f"/api/decks/{fork_id}").json()["card_count"] == 2
