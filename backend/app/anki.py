"""Turns an Anki collection into Engram basic cards.

The input is the SQLite database inside an .apkg: collection.anki2 or .anki21 (schema 11, note
types as JSON) or a decompressed collection.anki21b (schema 18, note types in tables with
protobuf configs). Each Anki card becomes one card by rendering its template, so reversed cards,
clozes and custom note types come out as they look in Anki, minus media.
"""

import json
import re
import sqlite3
from collections import defaultdict
from contextlib import closing
from dataclasses import dataclass, field
from datetime import UTC, datetime
from html.parser import HTMLParser
from pathlib import Path

from pydantic import TypeAdapter, ValidationError

from app.deck_format import MAX_TEXT_LENGTH, BasicCardData, Tag

MAX_ANKI_CARDS = 20_000
MAX_TAGS = 20


class AnkiFormatError(ValueError):
    """The upload isn't a collection we can read. The message is shown to the user."""


@dataclass
class NoteType:
    cloze: bool
    fields: list[str]
    # Template ord -> (question format, answer format).
    templates: dict[int, tuple[str, str]]


@dataclass
class AnkiCard:
    data: BasicCardData
    # (when, rating 1-4) in review order.
    reviews: list[tuple[datetime, int]]


@dataclass
class Conversion:
    deck_name: str | None
    cards: list[AnkiCard] = field(default_factory=list)
    skipped: int = 0
    media_removed: int = 0


# --- Reading the collection ---------------------------------------------------------------


def _varint(data: bytes, position: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        if position >= len(data) or shift > 63:
            raise AnkiFormatError("A note type in this collection is damaged.")
        byte = data[position]
        position += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return value, position


def _protobuf_fields(data: bytes) -> dict[int, int | bytes]:
    # Just enough protobuf for note type kinds and template formats: the first value of each
    # field number, skipping fixed-width ones.
    values: dict[int, int | bytes] = {}
    position = 0
    while position < len(data):
        key, position = _varint(data, position)
        number, wire_type = key >> 3, key & 7
        value: int | bytes
        if wire_type == 0:
            value, position = _varint(data, position)
        elif wire_type == 2:
            length, position = _varint(data, position)
            value = data[position : position + length]
            position += length
        elif wire_type in (1, 5):
            position += 8 if wire_type == 1 else 4
            continue
        else:
            raise AnkiFormatError("A note type in this collection is damaged.")
        values.setdefault(number, value)
    return values


def _text_field(values: dict[int, int | bytes], number: int) -> str:
    value = values.get(number, b"")
    return value.decode("utf-8", "replace") if isinstance(value, bytes) else ""


def _note_types_schema18(db: sqlite3.Connection) -> dict[int, NoteType]:
    note_types: dict[int, NoteType] = {}
    for note_type_id, config in db.execute("SELECT id, config FROM notetypes"):
        kind = _protobuf_fields(config or b"").get(1, 0)
        note_types[note_type_id] = NoteType(cloze=kind == 1, fields=[], templates={})
    for note_type_id, _, name in db.execute(
        "SELECT ntid, ord, name FROM fields ORDER BY ntid, ord"
    ):
        if note_type_id in note_types:
            note_types[note_type_id].fields.append(name)
    for note_type_id, ordinal, config in db.execute("SELECT ntid, ord, config FROM templates"):
        if note_type_id in note_types:
            values = _protobuf_fields(config or b"")
            note_types[note_type_id].templates[ordinal] = (
                _text_field(values, 1),
                _text_field(values, 2),
            )
    return note_types


def _note_types_schema11(db: sqlite3.Connection) -> dict[int, NoteType]:
    models = json.loads(db.execute("SELECT models FROM col").fetchone()[0] or "{}")
    return {
        int(model_id): NoteType(
            cloze=model.get("type") == 1,
            fields=[f["name"] for f in sorted(model["flds"], key=lambda f: f["ord"])],
            templates={t["ord"]: (t["qfmt"], t["afmt"]) for t in model["tmpls"]},
        )
        for model_id, model in models.items()
    }


def _decks(db: sqlite3.Connection, schema18: bool) -> dict[int, list[str]]:
    if schema18:
        return {
            deck_id: name.split("\x1f")
            for deck_id, name in db.execute("SELECT id, name FROM decks")
        }
    decks = json.loads(db.execute("SELECT decks FROM col").fetchone()[0] or "{}")
    return {int(deck_id): deck["name"].split("::") for deck_id, deck in decks.items()}


def convert_collection(path: Path, *, keep_reviews: bool) -> Conversion:
    try:
        with closing(sqlite3.connect(f"file:{path}?mode=ro", uri=True)) as db:
            # A collection is untrusted input: no triggers or views may run functions.
            db.execute("PRAGMA trusted_schema = OFF")
            db.execute("PRAGMA query_only = ON")
            return _convert(db, keep_reviews=keep_reviews)
    except (sqlite3.DatabaseError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise AnkiFormatError(
            "This file isn't an Anki collection Engram can read. Export the deck from Anki as "
            "an .apkg (Deck package) and try again."
        ) from error


def _convert(db: sqlite3.Connection, *, keep_reviews: bool) -> Conversion:
    tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if not {"col", "notes", "cards"} <= tables:
        raise sqlite3.DatabaseError("not a collection")
    schema18 = "notetypes" in tables
    note_types = _note_types_schema18(db) if schema18 else _note_types_schema11(db)
    decks = _decks(db, schema18)

    card_count = db.execute("SELECT count(*) FROM cards").fetchone()[0]
    if card_count > MAX_ANKI_CARDS:
        raise AnkiFormatError(
            f"This collection has {card_count:,} cards; Engram imports up to "
            f"{MAX_ANKI_CARDS:,} at a time. Export smaller subdecks from Anki."
        )

    notes = {
        note_id: (note_type_id, tags.split(), fields.split("\x1f"))
        for note_id, note_type_id, tags, fields in db.execute(
            "SELECT id, mid, tags, flds FROM notes"
        )
    }
    reviews: defaultdict[int, list[tuple[datetime, int]]] = defaultdict(list)
    if keep_reviews and "revlog" in tables:
        # Ease 0 marks manual reschedules, which aren't answers.
        for card_id, timestamp_ms, ease in db.execute(
            "SELECT cid, id, ease FROM revlog WHERE ease BETWEEN 1 AND 4 ORDER BY cid, id"
        ):
            reviews[card_id].append((datetime.fromtimestamp(timestamp_ms / 1000, UTC), ease))

    # A card in a filtered deck remembers its home deck in odid.
    rows = db.execute(
        "SELECT id, nid, CASE WHEN odid != 0 THEN odid ELSE did END, ord"
        " FROM cards ORDER BY nid, ord"
    ).fetchall()
    deck_paths = [decks.get(deck_id, []) for _, _, deck_id, _ in rows]
    root = _common_prefix(deck_paths)
    conversion = Conversion(deck_name="::".join(root) if root and root != ["Default"] else None)

    for (card_id, note_id, _, ordinal), deck_path in zip(rows, deck_paths, strict=True):
        note = notes.get(note_id)
        note_type = note_types.get(note[0]) if note else None
        if note is None or note_type is None:
            conversion.skipped += 1
            continue
        _, tags, values = note
        template = note_type.templates.get(0 if note_type.cloze else ordinal)
        if template is None:
            conversion.skipped += 1
            continue
        fields = dict(zip(note_type.fields, values, strict=False))
        specials = {
            "Tags": " ".join(tags),
            "Deck": "::".join(deck_path),
            "Subdeck": deck_path[-1] if deck_path else "",
        }
        cloze_number = ordinal + 1 if note_type.cloze else None
        front_html = render_template(template[0], fields, specials, cloze_number, answer=False)
        back_html = render_template(template[1], fields, specials, cloze_number, answer=True)
        front, front_media = html_to_markdown(front_html)
        back, back_media = html_to_markdown(_answer_part(back_html))
        if not front or not back or max(len(front), len(back)) > MAX_TEXT_LENGTH:
            conversion.skipped += 1
            continue
        if front_media or back_media:
            conversion.media_removed += 1
        subdeck = deck_path[len(root) :]
        card_tags = _tags([*tags, "::".join(subdeck).replace(" ", "-")] if subdeck else tags)
        conversion.cards.append(
            AnkiCard(
                data=BasicCardData(type="basic", front=front, back=back, tags=card_tags),
                reviews=reviews.get(card_id, []),
            )
        )
    return conversion


def _common_prefix(paths: list[list[str]]) -> list[str]:
    if not paths:
        return []
    prefix = paths[0]
    for path in paths[1:]:
        length = 0
        while length < min(len(prefix), len(path)) and prefix[length] == path[length]:
            length += 1
        prefix = prefix[:length]
    return prefix


_tag_adapter: TypeAdapter[str] = TypeAdapter(Tag)


def _tags(raw: list[str]) -> list[str]:
    # Anki allows tags Engram doesn't (any characters, any length); those are dropped.
    tags: list[str] = []
    for tag in raw:
        try:
            normalized = _tag_adapter.validate_python(tag)
        except ValidationError:
            continue
        if normalized not in tags:
            tags.append(normalized)
    return tags[:MAX_TAGS]


# --- Templates ----------------------------------------------------------------------------

_SECTION = re.compile(r"\{\{([#^])\s*([^{}]+?)\s*\}\}(.*?)\{\{/\s*\2\s*\}\}", re.DOTALL)
_REPLACEMENT = re.compile(r"\{\{\s*([^{}#^/][^{}]*?)\s*\}\}")
_CLOZE = re.compile(r"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}", re.DOTALL)
_EMPTY_FIELD = re.compile(r"<br\s*/?>|</?div>|&nbsp;|\s", re.IGNORECASE)
_RUBY = re.compile(r" ?([^ >]+?)\[(.+?)\]")
_ANSWER_RULE = re.compile(r"<hr[^>]*\bid\s*=\s*[\"']?answer\b[^>]*>", re.IGNORECASE)
_FRONT_SIDE = "\x00front-side\x00"


def _cloze(text: str, number: int | None, *, answer: bool) -> str:
    def replace(match: re.Match[str]) -> str:
        content, hint = match[2], match[3]
        if int(match[1]) != number:
            return content
        return f"<b>{content}</b>" if answer else f"[{hint or '...'}]"

    return _CLOZE.sub(replace, text)


_RUBY_FILTERS = {"furigana": r"\1(\2)", "kana": r"\2", "kanji": r"\1"}


def _apply_filter(name: str, value: str, cloze_number: int | None, *, answer: bool) -> str:
    if name == "cloze":
        return _cloze(value, cloze_number, answer=answer)
    if name in _RUBY_FILTERS:
        return _RUBY.sub(_RUBY_FILTERS[name], value)
    if name == "text":
        return re.sub(r"<[^>]*>", "", value)
    if name == "type":
        # The type-in-answer box: nothing to type into on the front, the answer on the back.
        return value if answer else ""
    # tts speaks the field instead of showing it; other filters (hint, unknown) show it.
    return "" if name in ("tts", "tts-voices") else value


def render_template(
    template: str,
    fields: dict[str, str],
    specials: dict[str, str],
    cloze_number: int | None,
    *,
    answer: bool,
) -> str:
    def is_filled(name: str) -> bool:
        cloze = re.fullmatch(r"c(\d+)", name)
        if cloze and cloze_number is not None:
            return any(f"{{{{c{cloze[1]}::" in value for value in fields.values())
        return bool(_EMPTY_FIELD.sub("", fields.get(name, specials.get(name, ""))))

    def section(match: re.Match[str]) -> str:
        shown = is_filled(match[2]) == (match[1] == "#")
        return match[3] if shown else ""

    # Innermost sections resolve first; a few passes cover any realistic nesting.
    for _ in range(10):
        resolved = _SECTION.sub(section, template)
        if resolved == template:
            break
        template = resolved

    def replacement(match: re.Match[str]) -> str:
        *filters, name = match[1].split(":")
        name = name.strip()
        if name == "FrontSide":
            return _FRONT_SIDE
        value = fields.get(name, specials.get(name, ""))
        for filter_name in reversed(filters):
            value = _apply_filter(filter_name.strip(), value, cloze_number, answer=answer)
        return value

    return _REPLACEMENT.sub(replacement, template)


def _answer_part(rendered: str) -> str:
    # Engram shows the front above the back, so the back is what Anki shows below the
    # answer rule, or the answer side without its copy of the front.
    rule = _ANSWER_RULE.search(rendered)
    if rule:
        rendered = rendered[rule.end() :]
    return rendered.replace(_FRONT_SIDE, "")


# --- HTML to Markdown ---------------------------------------------------------------------

_SOUND = re.compile(r"\[sound:[^\]]*\]")
_MATH = re.compile(
    r"\\\((?P<inline>.*?)\\\)|\\\[(?P<display>.*?)\\\]"
    r"|\[\$\](?P<inline2>.*?)\[/\$\]|\[\$\$\](?P<display2>.*?)\[/\$\$\]"
    r"|\[latex\](?P<display3>.*?)\[/latex\]",
    re.DOTALL | re.IGNORECASE,
)
_ESCAPED = re.compile(r"([\\`*_\[\]<>$~])")
_ENTITY_LIKE = re.compile(r"&(?=#?\w+;)")
_LINE_START = re.compile(r"(?:^|\n) *(?:- |\d+\. )?$")
_SKIPPED_CONTENT = {"script", "style", "title", "head", "audio", "video", "object", "svg"}
_MEDIA = {"img", "audio", "video", "source", "embed", "object", "svg"}
_BLOCKS = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "hr"}
_EMPHASIS = {"b": "**", "strong": "**", "i": "*", "em": "*", "s": "~~", "strike": "~~", "del": "~~"}
_SAFE_LINK = re.compile(r"^(https?:|mailto:)", re.IGNORECASE)


@dataclass
class _Inline:
    tag: str
    opening: str
    closing: str
    # Markers are written when the first text arrives, so <b></b> leaves nothing behind and
    # <b> Paris</b> becomes " **Paris**" (Markdown ignores ** next to a space).
    opened: bool = False


class _MarkdownWriter(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.buffers: list[list[str]] = [[]]
        self.skipping = 0
        self.media = False
        self.inline: list[_Inline] = []
        # One entry per open list: (ordered, next number, indent of its items' content).
        self.lists: list[tuple[bool, int, int]] = []
        self.code_depth = 0
        self.pre = False
        self.tables: list[list[list[str]]] = []
        self.cell_depth = 0

    # Output helpers

    @property
    def _out(self) -> list[str]:
        return self.buffers[-1]

    def _text(self) -> str:
        return "".join(self._out)

    def _at_line_start(self) -> bool:
        # Also true right after a list marker or the indent of a continued item.
        return _LINE_START.search(self._text()) is not None

    def _indent(self) -> str:
        return " " * (self.lists[-1][2] if self.lists else 0)

    def _line_break(self) -> None:
        if not self._at_line_start():
            self._out.append("  \n" + self._indent())

    def _block(self) -> None:
        if self.lists:
            # A blank line would end the list; inside an item, blocks are just new lines.
            self._line_break()
            return
        text = self._text()
        if text and not text.endswith("\n\n"):
            self._out.append("\n\n" if not text.endswith("\n") else "\n")

    def _open_pending(self) -> None:
        for item in self.inline:
            if not item.opened:
                self._out.append(item.opening)
                item.opened = True

    # Parser callbacks

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in _MEDIA:
            self.media = True
        if tag in _SKIPPED_CONTENT:
            self.skipping += 1
        if self.skipping or self.pre or tag in _MEDIA:
            return
        if tag in _EMPHASIS or tag == "a":
            self._start_inline(tag, dict(attrs).get("href") or "")
        elif tag in ("ul", "ol", "li"):
            self._start_list(tag)
        elif tag in ("table", "tr", "td", "th"):
            self._start_table(tag)
        else:
            self._start_block(tag)

    def _start_block(self, tag: str) -> None:
        if tag == "br" and self._text().endswith("  \n") and not self.lists:
            # Anki users separate paragraphs with a blank line made of two <br>s.
            self._block()
        elif tag in ("br", "div"):
            self._line_break()
        elif tag in _BLOCKS:
            self._block()
            if tag == "hr":
                self._out.append("* * *\n\n")
            elif tag.startswith("h"):
                self._out.append("#" * int(tag[1]) + " ")
        elif tag == "code":
            self.code_depth += 1
            self.buffers.append([])
        elif tag == "pre":
            self._block()
            self._out.append("```\n")
            self.pre = True

    def _start_inline(self, tag: str, href: str) -> None:
        if tag != "a":
            self.inline.append(_Inline(tag, _EMPHASIS[tag], _EMPHASIS[tag]))
        elif _SAFE_LINK.match(href):
            url = href.replace(" ", "%20").replace("(", "%28").replace(")", "%29")
            self.inline.append(_Inline("a", "[", f"]({url})"))

    def _start_list(self, tag: str) -> None:
        if tag != "li":
            if self.lists:
                self._out.append("\n")
            else:
                self._block()
            indent = self.lists[-1][2] if self.lists else 0
            self.lists.append((tag == "ol", 1, indent))
        elif self.lists:
            ordered, number, _ = self.lists[-1]
            # Items are indented to their parent item's content; nested lines line up with
            # this item's text.
            base = self.lists[-2][2] if len(self.lists) > 1 else 0
            marker = f"{number}. " if ordered else "- "
            if not self._at_line_start():
                self._out.append("\n")
            self._out.append(" " * base + marker)
            self.lists[-1] = (ordered, number + 1, base + len(marker))

    def _start_table(self, tag: str) -> None:
        if tag == "table":
            self._block()
            self.tables.append([])
        elif not self.tables:
            # Stray row or cell markup outside a table: just a new line.
            self._line_break()
        elif tag == "tr":
            self.tables[-1].append([])
        else:
            if not self.tables[-1]:
                self.tables[-1].append([])
            self.cell_depth += 1
            self.buffers.append([])

    def handle_endtag(self, tag: str) -> None:
        if tag in _SKIPPED_CONTENT:
            self.skipping = max(0, self.skipping - 1)
            return
        if self.skipping:
            return
        if tag == "pre" and self.pre:
            self.pre = False
            if not self._at_line_start():
                self._out.append("\n")
            self._out.append("```\n\n")
        elif self.pre:
            return
        elif tag in _EMPHASIS or tag == "a":
            self._end_inline(tag)
        elif tag == "code" and self.code_depth:
            self._end_code()
        elif tag in ("td", "th", "table"):
            self._end_table(tag)
        elif tag in ("ul", "ol") and self.lists:
            self.lists.pop()
            if not self.lists:
                self._block()
        elif tag in _BLOCKS:
            self._block()
        elif tag == "div" and not self.tables:
            self._line_break()

    def _end_inline(self, tag: str) -> None:
        for index in range(len(self.inline) - 1, -1, -1):
            item = self.inline[index]
            if item.tag != tag:
                continue
            del self.inline[index]
            if item.opened:
                # Markdown ignores a closing marker right after a space, so spaces go outside.
                text = self._text()
                trailing = text[len(text.rstrip(" ")) :]
                if trailing:
                    self.buffers[-1] = [text.rstrip(" ")]
                self._out.append(item.closing + trailing)
            return

    def _end_table(self, tag: str) -> None:
        if tag == "table" and self.tables:
            self._write_table(self.tables.pop())
        elif tag != "table" and self.cell_depth:
            self.cell_depth -= 1
            cell = " ".join("".join(self.buffers.pop()).split())
            self.tables[-1][-1].append(cell)

    def _end_code(self) -> None:
        self.code_depth -= 1
        code = " ".join("".join(self.buffers.pop()).split())
        if code:
            fence = "``" if "`" in code else "`"
            padding = " " if code.startswith("`") or code.endswith("`") else ""
            self._open_pending()
            self._out.append(f"{fence}{padding}{code}{padding}{fence}")

    def _write_table(self, rows: list[list[str]]) -> None:
        rows = [row for row in rows if row]
        if not rows:
            return
        width = max(len(row) for row in rows)
        lines = ["| " + " | ".join(row + [""] * (width - len(row))) + " |" for row in rows]
        lines.insert(1, "|" + " --- |" * width)
        self._block()
        self._out.append("\n".join(lines) + "\n\n")

    def handle_data(self, data: str) -> None:
        if self.skipping:
            return
        if _SOUND.search(data):
            self.media = True
            data = _SOUND.sub("", data)
        if self.pre:
            self._out.append(data)
            return
        if self.code_depth:
            self._out.append(data)
            return
        data = re.sub(r"\s+", " ", data.replace("\xa0", " "))
        if self._at_line_start():
            data = data.lstrip(" ")
        if not data:
            return
        position = 0
        for match in _MATH.finditer(data):
            self._write_text(data[position : match.start()])
            inline = match["inline"] or match["inline2"]
            if inline is not None and inline.strip():
                self._open_pending()
                self._out.append(f"${inline.strip()}$")
            elif (display := match["display"] or match["display2"] or match["display3"]) and (
                display.strip()
            ):
                self._block()
                self._out.append(f"$$\n{display.strip()}\n$$\n\n")
            position = match.end()
        self._write_text(data[position:])

    def _write_text(self, text: str) -> None:
        if not text:
            return
        stripped = text.lstrip(" ")
        if not stripped:
            if not self._at_line_start():
                self._out.append(" ")
            return
        escaped = _ENTITY_LIKE.sub(r"\\&", _ESCAPED.sub(r"\\\1", stripped))
        if self.cell_depth:
            escaped = escaped.replace("|", "\\|")
        pending = any(not item.opened for item in self.inline)
        if not pending and self._at_line_start():
            # Text that would start a heading, list or rule if it began a line.
            if escaped[0] in "#+=-":
                escaped = "\\" + escaped
            else:
                escaped = re.sub(r"^(\d+)([.)])", r"\1\\\2", escaped)
        if len(stripped) < len(text) and not self._at_line_start():
            self._out.append(" ")
        self._open_pending()
        self._out.append(escaped)

    def markdown(self) -> str:
        self.close()
        while len(self.buffers) > 1:
            inner = "".join(self.buffers.pop())
            self._out.append(inner)
        lines = "".join(self._out).split("\n")
        kept: list[str] = []
        for index, line in enumerate(lines):
            stripped = line.rstrip()
            following = lines[index + 1] if index + 1 < len(lines) else ""
            # A hard break only means something when another line of the paragraph follows.
            hard_break = line.endswith("  ") and stripped and following.strip()
            kept.append(stripped + "  " if hard_break else stripped)
        text = "\n".join(kept)
        return re.sub(r"\n{3,}", "\n\n", text).strip()


def html_to_markdown(html: str) -> tuple[str, bool]:
    """Converts a rendered Anki card side; also reports whether media was removed."""
    writer = _MarkdownWriter()
    writer.feed(html)
    return writer.markdown(), writer.media
