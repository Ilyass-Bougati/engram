# Engram deck format, version 1

A deck file is one JSON document, UTF-8 encoded. Exporting a deck produces this format, and importing accepts it. An import can either create a new deck or add the cards to an existing one; adding to an existing deck ignores `deck`. A complete example is in [`example-deck.json`](example-deck.json). Anki packages are imported separately; see [Importing from Anki](anki-import.md).

Exported files include quiz answer keys. Anyone who receives one can see the answers.

## Top level

| Field | Type | Required | Rules |
|---|---|---|---|
| `format` | string | yes | Exactly `"engram-deck"`. |
| `version` | integer | yes | Exactly `1`. |
| `deck` | object | yes | See [Deck](#deck). |
| `cards` | array | yes | 0 to 5,000 [cards](#cards). |

## Deck

| Field | Type | Required | Rules |
|---|---|---|---|
| `name` | string | yes | 1 to 200 characters. Leading and trailing spaces are trimmed. |

A `::` in the name puts the deck in a collection, as in Anki: `Spanish::Verbs` is listed as "Verbs" inside "Spanish", and collections can nest. Collections exist only through deck names; renaming a deck moves it, and a collection disappears with its last deck.
| `description` | string | no | Up to 2,000 characters. Defaults to `""`. |

## Cards

Each card is an object, and its `type` decides which other fields it takes.

All text fields are Markdown. They support:
- KaTeX math: `$...$` inline, `$$...$$` as a block
- fenced code blocks with a language: ` ```python `
- tables and strikethrough (GitHub-flavoured Markdown)

Raw HTML is not rendered.

Each text field holds at most 20,000 characters.

### `"type": "basic"` (front and back)

| Field | Type | Required | Rules |
|---|---|---|---|
| `type` | string | yes | `"basic"` |
| `front` | string | yes | 1 to 20,000 characters. |
| `back` | string | yes | 1 to 20,000 characters. |
| `tags` | array of strings | no | See [Tags](#tags). |

### `"type": "quiz"` (multiple choice)

| Field | Type | Required | Rules |
|---|---|---|---|
| `type` | string | yes | `"quiz"` |
| `question` | string | yes | 1 to 20,000 characters. |
| `select_all` | boolean | no | `false` (default): exactly one option is correct. `true`: "select all that apply", where at least one option is correct. |
| `options` | array | yes | 2 to 8 objects, each `{ "text": string, "correct": boolean }`. `text` is 1 to 20,000 characters. The order in the file is kept for editing; reviews shuffle it. |
| `explanation` | string | no | Shown after answering. Up to 20,000 characters. Defaults to `""`. |
| `tags` | array of strings | no | See [Tags](#tags). |

### Tags

- At most 20 tags per card, each 1 to 50 characters.
- Allowed characters: letters, digits, `_`, `-`, `.`, `/`, `:`, `+`, `#`.
- Tags are lowercased and trimmed, and duplicates are dropped.

## Limits and errors

The request body may be at most 2 MiB. A larger file is rejected with `413` before it is read.

An invalid file is rejected as a whole with `422`, and nothing is imported. The response names the first bad field, then lists every problem:

```json
{
  "detail": "cards[3].options: List should have at most 8 items after validation, not 9 (and 1 more problem)",
  "errors": [
    { "field": "cards[3].options", "message": "List should have at most 8 items after validation, not 9" },
    { "field": "cards[7].colour", "message": "Extra inputs are not permitted" }
  ]
}
```

Unknown fields are errors, not silently dropped, so a typo like `"qestion"` is caught.
