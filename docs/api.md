# API

The web app is the API's only client, but nothing stops you scripting against it. The full reference is [`openapi.json`](openapi.json), an OpenAPI 3.1 file covering every route, request body, response and error. Open it in any OpenAPI viewer, or read it as it is.

The running server doesn't publish the reference or any interactive docs. They would be the one page anyone could load without signing in that lists every route. The committed file is the reference instead, generated from the code.

## In short

- Every path starts with `/api`, on the same origin as the app.
- Sign in with `POST /api/auth/login`, then send `Authorization: Bearer <access_token>`. Access tokens last 15 minutes.
- To get a new one, call `POST /api/auth/refresh` with the refresh cookie from sign-in and the header `X-Engram-CSRF: 1`. A refresh token works once, and presenting a used one signs out every session from that sign-in. A script that doesn't keep cookies can sign in again instead.
- An error is JSON with a `detail` sentence meant for people. A 422 also lists each problem in `errors` as `{field, message}`.
- A deck you aren't a member of answers 404, the same as a deck that doesn't exist. A role that's too low answers 403.

[Security](security.md) has the reasons behind each of these.

## Example

Listing your decks against the Compose stack. This needs `jq`, and reads the password from a prompt so it stays out of your shell history:

```bash
API=http://127.0.0.1:6767/api
read -rs "PASSWORD?Password: "   # bash: read -rsp "Password: " PASSWORD
TOKEN=$(jq -n --arg u alice --arg p "$PASSWORD" '{username: $u, password: $p}' |
  curl -fsS -H 'Content-Type: application/json' --data @- "$API/auth/login" |
  jq -r .access_token)
curl -fsS -H "Authorization: Bearer $TOKEN" "$API/decks" | jq '.[] | {name, due_count}'
```

## Changing routes

The reference is regenerated from the routes, so edit the code and not the file. Each route's docstring becomes its summary (the first paragraph) and its description (the rest). Errors a route raises itself go in `ROUTE_ERRORS` in [`backend/app/openapi.py`](../backend/app/openapi.py). The common ones, such as 401, the deck 404 and the role 403s, are worked out from each route's dependencies.

Then regenerate the file:

```bash
cd backend
DATABASE_URL=postgresql://unused/unused JWT_SECRET=$(openssl rand -hex 32) uv run python -m app.openapi
```

The settings are checked on import, so both variables must be set; nothing connects to them. If the committed file falls behind the routes, `tests/test_openapi.py` fails.
