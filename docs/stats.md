# Stats

The **Stats** page shows your own study history. It covers the decks you're a member of, and only your own progress on them. Nobody else sees it, admins included.

All days are study days: they run from 04:00 to 04:00 in your timezone (set in Settings), the same as the daily new-card limit.

## Activity

- **Heatmap:** reviews per day over the last year.
- **Current streak:** consecutive study days up to today. A streak isn't broken until a whole day passes without a review, so it still counts in the morning before you study.
- **Longest streak, total reviews and days studied** cover your whole history, including any imported from Anki.

## Retention

The share of answers that weren't "Again", counting only answers given on a later study day than the card's previous answer. Repeats on the same day are learning steps, not tests of memory, so they are left out.

Shown for the last 30 days, per month for the past year, and per deck for the past year.

## Card states

| State | Meaning |
|---|---|
| New | Not studied yet |
| Learning | In learning or relearning steps |
| Young | In review, with an interval under 21 days |
| Mature | In review, with an interval of 21 days or more |

The 21-day line is the same as Anki's.

## API

`GET /api/me/stats` returns everything on the page in one response: `activity`, `retention_last_30_days`, `retention_by_month`, `states` and `decks`.
