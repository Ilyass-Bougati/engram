# Development

## Backend

Requirements: [uv](https://docs.astral.sh/uv/), and Docker for the tests, which start a throwaway Postgres 16 container.

```bash
cd backend
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy --strict app tests migrations
uv run pytest
```

The tests run against a real Postgres started by testcontainers and migrated with Alembic. Nothing is mocked, and nothing runs on SQLite.

To run the API against the Compose database, start the stack (see the [README](../README.md)). The backend is then on `127.0.0.1:6767`.

## Frontend

Requirements: Node 22 and npm.

```bash
cd frontend
npm ci
npm run dev        # http://localhost:6969, proxies /api to ENGRAM_API_URL
npm run lint
npm run format:check
npm run typecheck
npm test           # Vitest: Markdown/XSS and contrast tests
npm run build
```

By default the dev server uses the Compose backend on `127.0.0.1:6767`. To use the k3s deployment on this machine instead, with no port-forward, put this in `frontend/.env.local`:

```
ENGRAM_API_URL=http://10.43.67.67:8000
```

That is the backend Service's fixed address. A k3s node can reach Service addresses directly.

## End-to-end tests

```bash
cd frontend
npx playwright install chromium   # once
npm run e2e
```

The run needs Docker and two free ports, 6768 and 6970. It doesn't touch a stack you already have running:

1. It brings up its own Compose project, `engram-e2e`, with a fresh volume. Its backend listens on `127.0.0.1:6768`.
2. It starts a second Vite server on 6970 that proxies to that backend.
3. A setup step creates an admin with the CLI, and test users through invites.
4. Afterwards the stack is removed with `down -v`.

The `screens` project also writes full-page screenshots of every screen to `frontend/screenshots/`.

## Releases

[`.github/workflows/release.yml`](../.github/workflows/release.yml) runs when a `v*.*.*` tag is pushed:

1. The backend checks and the frontend checks run as two parallel jobs. Playwright is left out, to keep the run short.
2. If both pass, the image is built for `linux/amd64` and `linux/arm64` and pushed to `ghcr.io/l03x/engram-backend:<version>`. The push uses the workflow's own `GITHUB_TOKEN`, so no registry secret is stored.

The tag must equal `v` plus the `version` in `backend/pyproject.toml`, or the run fails before anything is built.
