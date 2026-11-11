from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.conftest import SignedIn
from tests.helpers import BASIC_CARD, QUIZ_CARD, create_card, create_deck, share


def _card(front: str) -> dict[str, Any]:
    return {**BASIC_CARD, "front": front}


def _names(client: TestClient) -> set[str]:
    return {deck["name"] for deck in client.get("/api/decks").json()}


@pytest.fixture
def java(signed_in: SignedIn) -> tuple[TestClient, TestClient, TestClient]:
    # alice owns two decks in "Java" and is a viewer on carol's third; "Javascript" isn't in it.
    alice, _ = signed_in("alice")
    bob, _ = signed_in("bob")
    carol, _ = signed_in("carol")
    for name in ("Java::Day 10", "Java :: Day 2", "Javascript"):
        create_card(alice, create_deck(alice, name), _card(f"{name} card"))
    shared = create_deck(carol, "Java::Extras::Quirks")
    create_card(carol, shared, _card("Quirks card"))
    share(carol, shared, "alice", "viewer")
    return alice, bob, carol


def test_studies_every_deck_in_the_collection_in_list_order(
    java: tuple[TestClient, TestClient, TestClient],
) -> None:
    alice, _, _ = java
    study = alice.get("/api/collections/study/next", params={"path": "Java"}).json()
    assert (study["due_count"], study["new_count"]) == (0, 3)
    fronts = []
    while study["card"]:
        fronts.append(study["card"]["front"])
        response = alice.post(
            "/api/collections/reviews",
            params={"path": "Java"},
            json={"card_id": study["card"]["id"], "rating": 4},
        )
        assert response.status_code == 200, response.text
        study = response.json()
    # New cards come one deck after another, numbers in order, the subcollection's last.
    assert fronts == ["Java :: Day 2 card", "Java::Day 10 card", "Quirks card"]
    assert study["next_due_at"] is not None


def test_cards_outside_the_collection_are_not_found(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    create_card(client, create_deck(client, "Java::Basics"), _card("In"))
    outside = create_card(client, create_deck(client, "Javascript"), QUIZ_CARD)
    path = {"path": "Java"}
    rated = client.post(
        "/api/collections/reviews", params=path, json={"card_id": outside, "rating": 3}
    )
    answered = client.post(
        "/api/collections/reviews/quiz-answer",
        params=path,
        json={"card_id": outside, "selected_option_ids": [outside]},
    )
    assert (rated.status_code, answered.status_code) == (404, 404)


def test_new_card_limits_stay_per_deck(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    for name in ("Spanish::Verbs", "Spanish::Nouns"):
        deck_id = create_deck(client, name)
        for front in ("one", "two", "three"):
            create_card(client, deck_id, _card(front))
    path = {"path": "Spanish"}
    updated = client.put("/api/collections/me", params=path, json={"new_cards_per_day": 2})
    assert {d["new_cards_per_day"] for d in updated.json()["decks"]} == {2}
    assert client.get("/api/collections/study/next", params=path).json()["new_count"] == 4


def test_a_collection_without_your_decks_is_not_found(
    java: tuple[TestClient, TestClient, TestClient],
) -> None:
    _, bob, _ = java
    path = {"path": "Java"}
    responses = [
        bob.get("/api/collections", params=path),
        bob.get("/api/collections/study/next", params=path),
        bob.get("/api/collections/members", params=path),
        bob.post(
            "/api/collections/members", params=path, json={"username": "bob", "role": "editor"}
        ),
        bob.patch("/api/collections", params=path, json={"name": "Mine"}),
        bob.delete("/api/collections", params=path),
    ]
    assert [r.status_code for r in responses] == [404] * 6
    assert responses[0].json() == bob.get("/api/collections", params={"path": "Nope"}).json()


def test_sharing_covers_only_the_decks_you_own(
    java: tuple[TestClient, TestClient, TestClient],
) -> None:
    alice, bob, carol = java
    path = {"path": "Java"}
    shared = alice.post(
        "/api/collections/members", params=path, json={"username": "bob", "role": "viewer"}
    )
    assert shared.json() == {"changed": 2, "skipped": 1}
    assert _names(bob) == {"Java::Day 10", "Java :: Day 2"}
    again = alice.post(
        "/api/collections/members", params=path, json={"username": "bob", "role": "viewer"}
    )
    assert again.status_code == 409
    promoted = alice.post(
        "/api/collections/members", params=path, json={"username": "bob", "role": "editor"}
    )
    assert promoted.json()["changed"] == 2
    assert {d["role"] for d in bob.get("/api/decks").json()} == {"editor"}

    members = {
        m["username"]: m["roles"] for m in alice.get("/api/collections/members", params=path).json()
    }
    assert members == {
        "alice": {"owner": 2, "viewer": 1},
        "bob": {"editor": 2},
        "carol": {"owner": 1},
    }
    # alice is only a viewer on carol's deck, so carol keeps access to it.
    carol_id = carol.get("/api/me").json()["id"]
    assert alice.delete(f"/api/collections/members/{carol_id}", params=path).status_code == 404


def test_a_collection_of_shared_decks_cannot_be_shared_or_changed(
    java: tuple[TestClient, TestClient, TestClient],
) -> None:
    alice, bob, _ = java
    path = {"path": "Java::Extras"}
    responses = [
        alice.post(
            "/api/collections/members", params=path, json={"username": "bob", "role": "viewer"}
        ),
        alice.patch("/api/collections", params=path, json={"name": "Mine"}),
        alice.delete("/api/collections", params=path),
    ]
    assert [r.status_code for r in responses] == [403, 403, 403]
    assert _names(bob) == set()


def test_removing_and_leaving(java: tuple[TestClient, TestClient, TestClient]) -> None:
    alice, bob, _ = java
    path = {"path": "Java"}
    alice.post("/api/collections/members", params=path, json={"username": "bob", "role": "viewer"})
    bob_id = bob.get("/api/me").json()["id"]
    removed = alice.delete(f"/api/collections/members/{bob_id}", params=path)
    assert removed.json() == {"changed": 2, "skipped": 1}
    assert _names(bob) == set()

    alice_id = alice.get("/api/me").json()["id"]
    left = alice.delete(f"/api/collections/members/{alice_id}", params=path)
    assert left.json() == {"changed": 1, "skipped": 2}
    assert "Java::Extras::Quirks" not in _names(alice)
    # Only owned decks are left, and an owner can't leave them.
    assert alice.delete(f"/api/collections/members/{alice_id}", params=path).status_code == 409


def test_renaming_moves_only_owned_decks(java: tuple[TestClient, TestClient, TestClient]) -> None:
    alice, _, carol = java
    renamed = alice.patch(
        "/api/collections", params={"path": "Java"}, json={"name": "Old :: Java 17"}
    )
    assert renamed.json() == {"changed": 2, "skipped": 1}
    assert _names(alice) == {
        "Old::Java 17::Day 10",
        "Old::Java 17::Day 2",
        "Javascript",
        "Java::Extras::Quirks",
    }
    assert _names(carol) == {"Java::Extras::Quirks"}

    too_long = alice.patch("/api/collections", params={"path": "Old"}, json={"name": "x" * 195})
    assert too_long.status_code == 422
    only_separators = alice.patch("/api/collections", params={"path": "Old"}, json={"name": "::"})
    assert only_separators.status_code == 422
    assert "Old::Java 17::Day 2" in _names(alice)


def test_deleting_removes_only_owned_decks(java: tuple[TestClient, TestClient, TestClient]) -> None:
    alice, _, carol = java
    deleted = alice.delete("/api/collections", params={"path": "Java"})
    assert deleted.json() == {"changed": 2, "skipped": 1}
    assert _names(alice) == {"Javascript", "Java::Extras::Quirks"}
    assert _names(carol) == {"Java::Extras::Quirks"}
