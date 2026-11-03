# syntax=docker/dockerfile:1
# The whole app in one image: the API, and the web app it serves on the same origin.

# The web app is static files, the same on every architecture, so it builds once on the build
# machine's own platform instead of under emulation. Type checks and tests run in CI before
# this, so only the bundle is built here.
FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS web
WORKDIR /web
COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npx vite build

FROM python:3.12-slim-bookworm AS build
COPY --from=ghcr.io/astral-sh/uv:0.11.15 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY backend/pyproject.toml backend/uv.lock backend/.python-version ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY backend/alembic.ini ./
COPY backend/migrations ./migrations
COPY backend/app ./app

# The runtime stage gets the virtualenv, the code and the built web app, and nothing that
# built them: no uv, no Node, no compiler, no package cache.
FROM python:3.12-slim-bookworm
RUN groupadd --system --gid 10001 engram \
    && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin engram
WORKDIR /app
COPY --from=build /app /app
COPY --from=web /web/dist /app/web
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
USER 10001:10001
EXPOSE 8000
# One worker: the login/refresh/invite rate limiter keeps its counters in process memory.
# X-Forwarded-For is honored only from the addresses in FORWARDED_ALLOW_IPS (uvicorn's
# default: 127.0.0.1 and ::1). Set it to the proxy's address once something sits in front.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", \
     "--proxy-headers", "--no-server-header"]
