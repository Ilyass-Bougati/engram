from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.web import IMMUTABLE, web_mount

INDEX = "<!doctype html><title>Engram</title>"


@pytest.fixture
def client(tmp_path: Path) -> Iterator[TestClient]:
    # A stand-in for the frontend build, mounted the way the image mounts the real one.
    (tmp_path / "index.html").write_text(INDEX)
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets" / "index-abc123.js").write_text("console.log(1)")
    (tmp_path / "favicon.svg").write_text("<svg/>")
    (tmp_path.parent / "secret.txt").write_text("not served")
    mount = web_mount(tmp_path)
    assert mount is not None
    app.router.routes.append(mount)
    try:
        yield TestClient(app)
    finally:
        app.router.routes.remove(mount)


def test_serves_the_app_for_any_page_and_caches_only_hashed_assets(client: TestClient) -> None:
    for path in ("/", "/decks/42/study", "/stats"):
        page = client.get(path)
        assert (page.status_code, page.text) == (200, INDEX), path
        assert page.headers["cache-control"] == "no-cache"
        assert page.headers["content-type"].startswith("text/html")

    asset = client.get("/assets/index-abc123.js")
    assert asset.status_code == 200
    assert asset.headers["cache-control"] == IMMUTABLE
    assert client.get("/favicon.svg").headers["cache-control"] == "no-cache"

    # A missing asset is a real 404, not the page: a stale chunk must fail, not parse HTML.
    assert client.get("/assets/gone-123.js").status_code == 404
    assert "not served" not in client.get("/../secret.txt").text
    assert client.get("/%2e%2e/secret.txt").text == INDEX


def test_api_paths_keep_their_json_errors(client: TestClient) -> None:
    missing = client.get("/api/no-such-thing")
    assert (missing.status_code, missing.json()) == (404, {"detail": "Not Found"})
    # GET on a POST-only route is still a 405, not the app's page.
    assert client.get("/api/auth/login").status_code == 405
    assert client.get("/api").status_code == 404


def test_every_response_carries_the_security_headers(client: TestClient) -> None:
    for response in (client.get("/"), client.get("/api/health")):
        csp = response.headers["content-security-policy"]
        assert "script-src 'self';" in csp
        assert "frame-ancestors 'none'" in csp
        assert response.headers["x-content-type-options"] == "nosniff"
        assert response.headers["referrer-policy"] == "no-referrer"
