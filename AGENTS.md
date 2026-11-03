# Engram: notes for coding agents

Engram is a self-hosted spaced-repetition flashcard app for a handful of users. It runs on a single-node k3s server behind a Cloudflare Tunnel. Read [`PLAN.md`](PLAN.md) for the design and the reasons behind it, and [`docs/`](docs) for each topic.

## Layout

| Path | What |
|---|---|
| `backend/` | FastAPI, SQLModel, Postgres 16, Alembic, py-fsrs. uv, Python 3.12 |
| `backend/app/routers/` | One module per tag. Shared access checks are in `app/deps.py` |
| `backend/migrations/` | Alembic. Every schema change is a new revision |
| `frontend/` | React 19, Vite, TypeScript strict, Tailwind v4, shadcn, TanStack Query, React Router |
| `frontend/src/styles/tokens.css` | Every color, radius, shadow, duration and glass value |
| `frontend/e2e/` | Playwright, run against its own Compose stack |
| `docs/openapi.json` | The API reference, generated from the routes |
| `Dockerfile` | One image: builds the web app, then the backend serves it |
| `deploy/k8s/` | Kustomize manifests |

## Checks

Run these before saying the work is done, and report what they printed.

```bash
cd backend
uv run ruff check
uv run ruff format --check
uv run mypy --strict app tests migrations
uv run pytest            # needs Docker: a throwaway Postgres via testcontainers
```

```bash
cd frontend
npm run lint
npm run format:check
npm run typecheck
npm test
npm run build
npm run e2e              # needs Docker and port 6768; see docs/development.md
```

The end-to-end run uses its own Compose project, `engram-e2e`, and removes it afterwards. Never stop, rebuild or wipe the Compose stack or k3s deployment someone already has running.

## Rules

### Git and attribution

- Don't commit, push, tag or rewrite history unless you're asked to. The maintainer handles git.
- Never add AI attribution anywhere: no `Co-Authored-By`, no "Generated with" lines, nothing in commits, PRs, code comments or docs.

### Secrets and config

- Config comes only from environment variables (`backend/app/config.py`). The backend refuses to start without `DATABASE_URL` or `JWT_SECRET`. Never add a default for a secret.
- Real secrets live in `.env` and `deploy/k8s/secret.yaml`, both gitignored. They are filled in from `.env.example` and `secret.example.yaml`. Never commit them, print them or copy them into other files.

### Backend

- Every route either depends on `get_current_user` or carries `openapi_extra=PUBLIC`. Every route with `{deck_id}` depends on `ViewerAccess`, `EditorAccess` or `OwnerAccess`. `tests/test_route_auth.py` enforces both.
- Non-members get 404, never 403, so deck IDs can't be probed. Cards and members are looked up only within the deck from the path.
- Request models subclass `StrictModel` (`extra="forbid"`). Scheduling fields (due dates, stability and the like) are never read from a request; the server computes them.
- `review_log` is append-only. A trigger rejects updates.
- Error `detail` messages are full sentences shown to users as they are. Say what went wrong and what to do.
- Tests run against real Postgres; nothing is mocked or run on SQLite. Keep tests to what matters: access rules, scheduling, validation limits, regressions.
- After changing a route, its models or its errors, regenerate `docs/openapi.json` (see [docs/api.md](docs/api.md#changing-routes)) and update `frontend/src/lib/types.ts` to match.

### Frontend

- Use the tokens in `tokens.css` through Tailwind; no raw colors in components. No purple, indigo, violet or cyan.
- Glass only on surfaces that float over content: the nav, the sticky deck toolbar, the review card, dialogs and menus. `src/styles/contrast.test.ts` checks text contrast over every backdrop; keep it passing when changing colors or glass.
- Motion uses the duration and easing tokens, stays short and respects `prefers-reduced-motion`.
- Card text goes through the one `<Markdown>` component (`src/components/markdown`). Raw HTML is never rendered, and nothing uses `dangerouslySetInnerHTML`.
- Icons come from `lucide-react`, with `aria-hidden` next to a visible label, or an `aria-label` when there isn't one.
- Every screen has loading, empty and error states.
- The production page runs under a strict Content Security Policy (`backend/app/web.py`): no inline scripts, no third-party origins. The end-to-end tests fail on any CSP violation.

### Releases

The version appears in three places, which must agree: `backend/pyproject.toml`, `newTag` in `deploy/k8s/kustomization.yaml`, and `image` in `compose.yaml`. The release workflow builds `ghcr.io/l03x/engram:<version>` when the matching `v<version>` tag is pushed. See [docs/development.md](docs/development.md#releases).
