"""Collections come from deck names, as in Anki and the web app (frontend/src/lib/collections.ts).

"Java::Day 1" is the deck "Day 1" in the collection "Java". Nothing is stored for a collection:
it holds whichever of your decks have names under its path, and renaming a deck moves it.
"""

import re

SEPARATOR = "::"


def deck_path(name: str) -> list[str]:
    path = [part.strip() for part in name.split(SEPARATOR)]
    return [part for part in path if part] or [name]


def in_collection(name: str, collection: list[str]) -> bool:
    # A deck named exactly like the collection ("Java" next to "Java::Day 1") is in it too.
    return deck_path(name)[: len(collection)] == collection


def moved_name(name: str, collection: list[str], destination: list[str]) -> str:
    return SEPARATOR.join(destination + deck_path(name)[len(collection) :])


def _natural(part: str) -> list[tuple[int, str]]:
    # Numbers compare as numbers, so "Day 2" comes before "Day 10", as on the deck list.
    return [
        (int(chunk), "") if index % 2 else (0, chunk.casefold())
        for index, chunk in enumerate(re.split(r"(\d+)", part))
    ]


def path_sort_key(name: str) -> list[list[tuple[int, str]]]:
    # The deck list's order: a collection's own deck first, then everything by name.
    return [_natural(part) for part in deck_path(name)]
