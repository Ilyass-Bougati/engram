from typing import Any

from fastapi.testclient import TestClient

from tests.conftest import SignedIn, Team
from tests.helpers import BASIC_CARD, QUIZ_CARD, create_card, create_deck


def test_create_and_read_both_card_types(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    basic_id = create_card(client, deck_id, BASIC_CARD)
    quiz_id = create_card(client, deck_id, QUIZ_CARD)

    basic = client.get(f"/api/decks/{deck_id}/cards/{basic_id}").json()
    assert (basic["type"], basic["front"], basic["back"], basic["tags"]) == (
        "basic",
        "Capital of Morocco?",
        "Rabat",
        ["geo"],
    )
    quiz = client.get(f"/api/decks/{deck_id}/cards/{quiz_id}").json()
    assert quiz["select_all"] is True
    assert [(o["text"], o["correct"]) for o in quiz["options"]] == [
        ("2", True),
        ("4", False),
        ("7", True),
    ]
    assert quiz["explanation"] == "4 = 2 x 2."


def test_viewer_sees_no_answer_key_in_the_card_browser(team: Team) -> None:
    deck = f"/api/decks/{team.deck_id}"
    for payload in (
        team.viewer.get(f"{deck}/cards/{team.quiz_card_id}").json(),
        next(c for c in team.viewer.get(f"{deck}/cards").json()["cards"] if c["type"] == "quiz"),
    ):
        assert all(set(option) == {"id", "text"} for option in payload["options"])
        assert payload["explanation"] is None
        assert "4 = 2 x 2." not in str(payload)

    editor_view = team.editor.get(f"{deck}/cards/{team.quiz_card_id}").json()
    assert all("correct" in option for option in editor_view["options"])


def _create_error(client: TestClient, deck_id: str, card: dict[str, Any]) -> str:
    response = client.post(f"/api/decks/{deck_id}/cards", json=card)
    assert response.status_code == 422
    detail: str = response.json()["detail"]
    return detail


def test_quiz_validation_messages_name_the_problem(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    one_option = {**QUIZ_CARD, "options": [{"text": "2", "correct": True}]}
    nine_options = {**QUIZ_CARD, "options": [{"text": str(n), "correct": True} for n in range(9)]}
    two_correct_single = {**QUIZ_CARD, "select_all": False}
    none_correct = {**QUIZ_CARD, "options": [{"text": "4", "correct": False}] * 2}

    assert _create_error(client, deck_id, one_option).startswith(
        "options: List should have at least 2"
    )
    assert _create_error(client, deck_id, nine_options).startswith(
        "options: List should have at most 8"
    )
    assert "exactly one correct option (got 2)" in _create_error(
        client, deck_id, two_correct_single
    )
    assert "at least one correct option" in _create_error(client, deck_id, none_correct)
    assert _create_error(client, deck_id, {**BASIC_CARD, "back": ""}).startswith("back:")
    assert _create_error(client, deck_id, {**BASIC_CARD, "due": "2030-01-01"}).startswith("due:")


def test_update_replaces_content_and_can_change_type(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    card_id = create_card(client, deck_id, BASIC_CARD)
    response = client.put(f"/api/decks/{deck_id}/cards/{card_id}", json=QUIZ_CARD)
    assert response.status_code == 200
    card = client.get(f"/api/decks/{deck_id}/cards/{card_id}").json()
    assert (card["type"], card["question"], card["tags"]) == ("quiz", "Which are prime?", ["math"])
    assert card["updated_at"] > card["created_at"]


def test_delete_card(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    card_id = create_card(client, deck_id, BASIC_CARD)
    assert client.delete(f"/api/decks/{deck_id}/cards/{card_id}").status_code == 204
    assert client.get(f"/api/decks/{deck_id}/cards/{card_id}").status_code == 404
    assert client.get(f"/api/decks/{deck_id}").json()["card_count"] == 0


def test_search_by_text_and_tag(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    capital = create_card(client, deck_id, BASIC_CARD)
    prime = create_card(client, deck_id, QUIZ_CARD)
    percent = create_card(
        client, deck_id, {"type": "basic", "front": "50% of 8?", "back": "4", "tags": ["Math"]}
    )

    def found(**params: str) -> list[str]:
        page = client.get(f"/api/decks/{deck_id}/cards", params=params).json()
        return [card["id"] for card in page["cards"]]

    assert found(q="rabat") == [capital]
    # Option text and explanations are searchable too.
    assert found(q="2 x 2") == [prime]
    # LIKE wildcards in the query are literal characters.
    assert found(q="%") == [percent]
    assert found(q="_") == []
    assert found(tag="math") == [prime, percent]
    assert found(tag="MATH", q="50") == [percent]
    assert found(q="nothing like this") == []


def test_search_does_not_leak_other_decks(signed_in: SignedIn) -> None:
    alice, _ = signed_in("alice")
    bob, _ = signed_in("bob")
    create_card(alice, create_deck(alice), BASIC_CARD)
    bob_deck = create_deck(bob)
    assert bob.get(f"/api/decks/{bob_deck}/cards", params={"q": "Rabat"}).json()["cards"] == []
    assert bob.get(f"/api/decks/{bob_deck}/tags").json() == []


def test_card_list_paginates_in_creation_order(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    created = [
        create_card(client, deck_id, {"type": "basic", "front": f"Q{n}", "back": "A"})
        for n in range(5)
    ]
    seen: list[str] = []
    cursor: str | None = None
    while True:
        params = {"limit": "2", **({"cursor": cursor} if cursor else {})}
        page = client.get(f"/api/decks/{deck_id}/cards", params=params).json()
        seen += [card["id"] for card in page["cards"]]
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert seen == created
    bad = client.get(f"/api/decks/{deck_id}/cards", params={"cursor": "garbage"})
    assert bad.status_code == 422


def test_tags_are_normalised_and_counted(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    deck_id = create_deck(client)
    create_card(client, deck_id, {**BASIC_CARD, "tags": [" Geo ", "geo", "Africa"]})
    create_card(client, deck_id, {**BASIC_CARD, "tags": ["africa"]})
    assert client.get(f"/api/decks/{deck_id}/tags").json() == [
        {"tag": "africa", "card_count": 2},
        {"tag": "geo", "card_count": 1},
    ]
