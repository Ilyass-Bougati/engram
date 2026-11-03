from app.openapi import SPEC_PATH, render_spec


def test_the_committed_api_reference_matches_the_routes() -> None:
    # Regenerate with the command at the top of app/openapi.py.
    assert SPEC_PATH.read_text() == render_spec(), "docs/openapi.json is out of date"
