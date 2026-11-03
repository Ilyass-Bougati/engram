# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm AS build
COPY --from=ghcr.io/astral-sh/uv:0.11.15 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY alembic.ini ./
COPY migrations ./migrations
COPY app ./app

# The runtime stage gets the virtualenv and the code, and nothing that built them: no uv, no
# compiler, no package cache.
FROM python:3.12-slim-bookworm
RUN groupadd --system --gid 10001 engram \
    && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin engram
WORKDIR /app
COPY --from=build /app /app
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
USER 10001:10001
EXPOSE 8000
# One worker: the login/refresh/invite rate limiter keeps its counters in process memory.
# X-Forwarded-For is honored only from the addresses in FORWARDED_ALLOW_IPS (uvicorn's
# default: 127.0.0.1 and ::1). Set it to the proxy's address once something sits in front.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", \
     "--proxy-headers", "--no-server-header"]
