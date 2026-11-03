import gzip
from pathlib import Path

import pytest
from sqlmodel import Session, col, select

from app import main
from app.models import ReviewLog, ReviewState
from app.routers import decks
from tests.conftest import SignedIn

FIXTURES = Path(__file__).parent / "fixtures"
URL = "/api/decks/import/anki"


def collection(name: str) -> bytes:
    # Made with the real Anki library from the same notes in both export formats (see
    # fixtures/make_anki_fixtures.py), gzipped as the browser uploads them.
    return (FIXTURES / f"anki-{name}.sqlite.gz").read_bytes()


@pytest.mark.parametrize("export_format", ["modern", "legacy"])
def test_both_export_formats_become_the_same_markdown_cards(
    signed_in: SignedIn, export_format: str
) -> None:
    client, _ = signed_in("alice")
    response = client.post(URL, params={"name": "geo"}, content=collection(export_format))
    assert response.status_code == 201, response.text
    result = response.json()
    assert result["deck"]["name"] == "Geography"
    assert result["deck"]["role"] == "owner"
    # Seven Anki cards: the image-only one is skipped; three lose an image or a sound.
    assert (result["imported"], result["skipped"], result["media_removed"]) == (6, 1, 3)
    assert result["reviews_imported"] == 0

    cards = client.get(f"/api/decks/{result['deck']['id']}/cards").json()["cards"]
    sides = [(card["front"], card["back"]) for card in cards]
    assert sides == [
        ("Capital of **France**?", "Paris  \nOn the Seine & costs \\$5 a coffee"),
        # Basic (and reversed card): both directions; the sound tag is gone.
        ("Río Bravo", "*Rio Grande*"),
        ("*Rio Grande*", "Río Bravo"),
        # One card per cloze, MathJax turned into $…$.
        (
            "\\[...\\] is the capital of Canada, at $45^\\circ$ N.",
            "**Ottawa** is the capital of Canada, at $45^\\circ$ N.\n\n- Since 1857\n- Ontario",
        ),
        (
            "Ottawa is the capital of \\[country\\], at $45^\\circ$ N.",
            "Ottawa is the capital of **Canada**, at $45^\\circ$ N.\n\n- Since 1857\n- Ontario",
        ),
        ("Use `a*b` in [docs](https://example.com)", "Line one  \nLine two"),
    ]
    # Anki tags are lowercased; the subdeck below the common root becomes a tag.
    assert cards[0]["tags"] == ["capitals", "capitals-of-europe", "europe::west"]


def test_keeping_progress_replays_history_for_the_importer_only(
    signed_in: SignedIn, db: Session
) -> None:
    client, alice = signed_in("alice")
    response = client.post(URL, params={"keep_progress": "true"}, content=collection("modern"))
    assert response.status_code == 201, response.text
    assert response.json()["reviews_imported"] == 4

    logs = db.exec(select(ReviewLog).order_by(col(ReviewLog.reviewed_at))).all()
    assert sorted(log.rating for log in logs) == [1, 3, 3, 3]
    assert {log.user_id for log in logs} == {alice.id}
    states = db.exec(select(ReviewState)).all()
    # France (Again, Good, Good) graduated to review; Ottawa (Good once) is still learning.
    assert sorted(state.state for state in states) == [1, 2]
    for state in states:
        card_logs = [log for log in logs if log.card_id == state.card_id]
        assert state.introduced_at == card_logs[0].reviewed_at
        assert state.last_review == card_logs[-1].reviewed_at


def test_without_progress_every_card_is_new(signed_in: SignedIn, db: Session) -> None:
    client, _ = signed_in("alice")
    response = client.post(URL, content=collection("modern"))
    assert response.status_code == 201
    assert response.json()["deck"]["new_count"] == 6
    assert db.exec(select(ReviewState)).all() == []


def test_uncompressed_collections_are_accepted(signed_in: SignedIn) -> None:
    client, _ = signed_in("alice")
    response = client.post(URL, content=gzip.decompress(collection("legacy")))
    assert response.status_code == 201
    assert response.json()["imported"] == 6


def test_files_that_are_not_collections_are_refused(
    signed_in: SignedIn, monkeypatch: pytest.MonkeyPatch
) -> None:
    client, _ = signed_in("alice")
    for body in (
        b'{"format": "engram-deck"}',
        gzip.compress(b"SQLite format 3\x00" + b"\x00" * 99),
    ):
        response = client.post(URL, content=body)
        assert response.status_code == 422
        assert "isn't an Anki collection" in response.json()["detail"]

    response = client.post(URL, content=collection("modern")[:-20])
    assert (response.status_code, response.json()["detail"]) == (
        422,
        "The upload is incomplete. Try importing the file again.",
    )

    # A small gzip that would inflate past the cap stops at the cap.
    monkeypatch.setattr(decks, "MAX_ANKI_COLLECTION_BYTES", 1_000)
    response = client.post(URL, content=collection("modern"))
    assert response.status_code == 422
    assert "once unpacked" in response.json()["detail"]


def test_upload_size_is_capped_before_reading(
    signed_in: SignedIn, monkeypatch: pytest.MonkeyPatch
) -> None:
    client, _ = signed_in("alice")
    monkeypatch.setitem(main.LARGER_BODIES, decks.ANKI_IMPORT_PATH, (100, "Too large."))
    response = client.post(URL, content=b"x" * 101)
    assert (response.status_code, response.json()["detail"]) == (413, "Too large.")
    # Other routes keep the 2 MiB cap.
    response = client.post("/api/decks/import", content=b"x" * (2 * 1024 * 1024 + 1))
    assert response.status_code == 413
