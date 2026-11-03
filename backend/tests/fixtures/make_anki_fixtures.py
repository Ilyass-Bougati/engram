"""Rebuilds the Anki fixtures with the real Anki library. Not run by the tests.

    uv run --no-project --python 3.12 --with anki --with zstandard \
        python tests/fixtures/make_anki_fixtures.py tests/fixtures ../frontend/e2e/fixtures

Writes anki-modern.sqlite.gz and anki-legacy.sqlite.gz (the collection from each export format,
gzipped as the browser uploads it) and geography.apkg (the modern package, for the frontend).
"""

import gzip
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import zstandard  # type: ignore[import-not-found]
from anki.collection import (  # type: ignore[import-not-found]
    Collection,
    DeckIdLimit,
    ExportAnkiPackageOptions,
)

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"


def build(out_dir: Path, apkg_dir: Path) -> None:
    work = Path(tempfile.mkdtemp())
    col = Collection(str(work / "collection.anki2"))
    geography = col.decks.id("Geography")
    capitals = col.decks.id("Geography::Capitals of Europe")
    col.media.write_data("map.png", b"\x89PNG\r\n\x1a\nfake")

    def add(model: str, deck: int, fields: dict[str, str], tags: list[str]) -> object:
        note = col.new_note(col.models.by_name(model))
        for name, value in fields.items():
            note[name] = value
        note.tags = tags
        col.add_note(note, deck)
        return note

    france = add(
        "Basic",
        capitals,
        {
            "Front": "Capital of <b>France</b>?",
            "Back": 'Paris<br>On the Seine &amp; costs $5 &nbsp;a coffee<img src="map.png">',
        },
        ["europe::west", "Capitals"],
    )
    add(
        "Basic (and reversed card)",
        geography,
        {"Front": "Río Bravo", "Back": "<i>Rio Grande</i> [sound:river.mp3]"},
        ["rivers"],
    )
    ottawa = add(
        "Cloze",
        geography,
        {
            "Text": "{{c1::Ottawa}} is the capital of {{c2::Canada::country}},"
            " at \\(45^\\circ\\) N.",
            "Back Extra": "<ul><li>Since 1857</li><li>Ontario</li></ul>",
        },
        ["canada"],
    )
    add("Basic", geography, {"Front": '<img src="map.png">', "Back": "Europe"}, [])
    add(
        "Basic",
        geography,
        {
            "Front": 'Use <code>a*b</code> in <a href="https://example.com">docs</a>',
            "Back": "<div>Line one</div><div>Line two</div>",
        },
        [],
    )

    # History: the France card rated Again, Good, Good; the Ottawa cloze rated Good once.
    for note, ratings in ((france, [1, 3, 3]), (ottawa, [3])):
        card_id = note.cards()[0].id  # type: ignore[attr-defined]
        for rating in ratings:
            card = col.get_card(card_id)
            card.start_timer()
            col.sched.answerCard(card, rating)

    for legacy, name in ((False, "modern.apkg"), (True, "legacy.apkg")):
        col.export_anki_package(
            out_path=str(work / name),
            options=ExportAnkiPackageOptions(
                with_scheduling=True, with_deck_configs=False, with_media=True, legacy=legacy
            ),
            limit=DeckIdLimit(geography),
        )
    col.close()

    for package, entry, out in (
        ("modern.apkg", "collection.anki21b", "anki-modern.sqlite.gz"),
        ("legacy.apkg", "collection.anki21", "anki-legacy.sqlite.gz"),
    ):
        data = zipfile.ZipFile(work / package).read(entry)
        if data.startswith(ZSTD_MAGIC):
            data = zstandard.ZstdDecompressor().stream_reader(data).read()
        with gzip.GzipFile(out_dir / out, "wb", mtime=0) as file:
            file.write(data)
    shutil.copy(work / "modern.apkg", apkg_dir / "geography.apkg")
    shutil.rmtree(work)


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]))
