# Engram

A self-hosted spaced-repetition flashcard app for a small group of people. Accounts are invite-only.

Status: Phase 2 of 6. Done so far: accounts, invites, sessions, the admin CLI, decks, cards, sharing, roles, forking, and JSON import/export. See `PLAN.md`.

## Run it with Docker Compose

Requirements: Docker with Compose v2.

```bash
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 32)/; s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" .env
docker compose up -d --build --wait
docker compose exec backend python -m app.cli create-admin <your-username>
```

Compose starts three services:

| Service | What it does |
|---|---|
| `db` | Postgres 16. Data lives in the named volume `engram_pgdata`. |
| `migrate` | Runs `alembic upgrade head` once, then exits. |
| `backend` | The API. It starts only after `migrate` succeeds. |

The API is published at `http://127.0.0.1:6767/api`. From Phase 4 on, the app is served at `http://localhost:6969`, with nginx proxying `/api` to the backend.

## Environment variables

Config comes only from the environment. The backend exits at startup if a required value is missing or invalid. There are no fallback secrets.

| Variable | Required | Meaning |
|---|---|---|
| `DATABASE_URL` | yes | Postgres URL. `postgresql://…` is accepted and pinned to the psycopg driver. |
| `JWT_SECRET` | yes | Signs access tokens. At least 32 characters; use `openssl rand -hex 32`. |
| `REFRESH_TOKEN_DAYS` | no (default 30) | Lifetime of a refresh token. Each refresh rotates it. |
| `POSTGRES_PASSWORD` | compose only | Password for the bundled Postgres. Compose builds `DATABASE_URL` from it. |

## Admin CLI

Run inside the backend container (`docker compose exec backend …`), or from `backend/` with `uv run`.

| Command | What it does |
|---|---|
| `python -m app.cli create-admin <username>` | Creates an admin. Prompts for the password twice. |
| `python -m app.cli set-password <username>` | Sets a new password and signs out all of that user's sessions. This is the recovery path for a forgotten password, since the app sends no email. |
| `python -m app.cli wait-for-migrations [--timeout 300]` | Blocks until the database schema matches the code. Used by the k8s initContainer. |

`create-admin` and `set-password` accept `--password-stdin`, which reads the password from the first line of stdin.

Admins invite people from the app. An invite link is single-use and expires after 7 days.

## Decks and sharing

Each deck has one owner, who can share it by username as `editor` (may edit cards) or `viewer` (study only). The owner can change or revoke a member's role, and any member can leave a deck.

- **Hidden decks:** someone who isn't a member gets `404` for a deck and everything in it, so they can't tell it exists.
- **Hidden answer keys:** viewers browsing a deck don't see which quiz options are correct, or the explanation. Exports and forks do include the answer key, and any member can export or fork.
- **Forks:** a fork is an independent copy owned by whoever forked it. It has no link back to the original, and no review progress carries over.
- **Import/export:** the JSON deck format is documented in [`docs/deck-format.md`](docs/deck-format.md), with an example in [`docs/example-deck.json`](docs/example-deck.json). Imports are capped at 2 MiB and 5,000 cards.

## How sessions work

- **Login** returns a 15-minute access token. It also sets an httpOnly, Secure, SameSite=Lax refresh cookie scoped to `/api/auth`.
- **Refresh tokens rotate** on every use. Presenting one that was already used revokes that login's whole token chain.
- **Logout, password change and deactivation** revoke refresh tokens. Password change and deactivation also invalidate live access tokens at once.
- **`POST /api/auth/refresh` and `/api/auth/logout`** require the header `X-Engram-CSRF: 1`.
- **Rate limits:**
  - login: 10 per minute per IP, and 5 failed attempts per 15 minutes per username
  - refresh: 30 per minute per IP
  - invite lookup and redemption: 10 per minute per IP
- **One process only.** The limiter keeps its counters in memory, so the backend must run as one process (one uvicorn worker, one replica).

## Development

Requirements: [uv](https://docs.astral.sh/uv/) and Docker (the tests start a throwaway Postgres 16 container).

```bash
cd backend
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy --strict app tests migrations
uv run pytest
```

The tests run against a real Postgres started by testcontainers, migrated with Alembic. Nothing is mocked or run on SQLite.
