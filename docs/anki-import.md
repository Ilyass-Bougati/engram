# Importing from Anki

On the deck list, choose **Import → Anki package (.apkg)**. In Anki, make the file with File → Export and "Anki Deck Package (.apkg)". Packages from current Anki and from older versions both work.

The import always creates a new deck that you own. Nothing is added to an existing deck.

## What comes across

- **Each Anki card becomes one front-and-back card.** Engram renders the card's own template, so reversed cards, custom note types and conditional fields come out as they look in Anki. The back is what Anki shows below the line on the answer side.
- **Cloze cards** become basic cards: the front shows the blank as `[...]` (or the hint), and the back shows the full text with the answer in bold.
- **Formatting** is converted to Markdown: bold, italic, strikethrough, links (`http`, `https` and `mailto` only), lists, headings, tables and code. Anything else keeps its text and loses its styling.
- **Math:** MathJax `\(...\)` and `\[...\]`, and `[latex]...[/latex]`, become `$...$` and `$$...$$`.
- **Images, sounds and video are left out.** The result says how many were removed. A card that is empty without its media is skipped.
- **Tags** are lowercased. Tags Engram doesn't allow (see [tags](deck-format.md#tags)) are dropped, as are any past the 20th.
- **Subdecks:** the deck is named after the subdecks' common parent. Cards from several subdecks get the subdeck path as a tag, for example `europe::capitals` for `Geography::Europe::Capitals`. Cards from Anki's "Default" deck take the file's name instead. You can rename the deck afterwards.
- **Skipped cards:** a card is skipped if either side is empty or longer than 20,000 characters.

## Keeping your Anki progress

With **Keep my Anki progress** checked, each card's review history is replayed through Engram's scheduler. Studied cards keep a schedule close to Anki's, and the history counts toward your [stats](stats.md).

The progress is yours only. People you share the deck with start it fresh, and so does anyone who forks it.

## Limits

| What | Limit |
|---|---|
| Collection uploaded | 64 MiB |
| Collection after unpacking | 256 MiB |
| Cards per import | 20,000 |

The browser unpacks the `.apkg` and uploads only the collection database, without the media. So the limit is on the collection, not the whole file, and media-heavy decks still fit. A collection over the limit can be split by exporting subdecks one at a time.

## API

`POST /api/decks/import/anki?keep_progress=true&name=...` takes the collection database (`collection.anki21b` decompressed, `collection.anki21` or `collection.anki2`) as the request body, gzipped (`Content-Type: application/gzip`) or as is. `keep_progress` defaults to `false`. `name` (optional, the file name in the web client) names the deck only when the cards have no common Anki deck.

The answer is `201` with:

```json
{ "deck": { "id": "...", "name": "Geography", "...": "..." },
  "imported": 6, "skipped": 1, "media_removed": 3, "reviews_imported": 4 }
```

A body that isn't an Anki collection gets `422` with a message saying why, and a body over 64 MiB gets `413`.
