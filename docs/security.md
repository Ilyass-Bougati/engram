# Security

## Sessions

- **Login** returns a 15-minute access token. The web client keeps it in memory only. Login also sets an httpOnly, Secure, SameSite=Lax refresh cookie scoped to `/api/auth`.
- **Refresh tokens rotate** on every use. Presenting one that was already used revokes that login's whole token chain.
- **Logout, password change and deactivation** revoke refresh tokens. Password change and deactivation also invalidate live access tokens at once: every request checks the account's state in the database.
- **CSRF:** `POST /api/auth/refresh` and `/api/auth/logout` require the header `X-Engram-CSRF: 1`. No CORS is configured, so a page on another site can't send it.
- **Passwords** are hashed with Argon2. Login gives the same answer, in about the same time, for an unknown user, a wrong password and a deactivated account.
- **Invite and refresh tokens** are 32 random bytes, stored as SHA-256 hashes.

## Rate limits

| What | Limit |
|---|---|
| Login | 10 per minute per IP, and 5 failed attempts per 15 minutes per username |
| Refresh | 30 per minute per IP |
| Invite lookup and redemption | 10 per minute per IP |

Going over the limit returns `429` with `Retry-After`. The counters live in process memory. That is why the backend runs as one uvicorn worker and one replica: a second process would get its own counters. Behind a proxy, the per-IP limits need `FORWARDED_ALLOW_IPS` (see [configuration](configuration.md#proxies-and-client-ips)).

Request bodies are capped at 2 MiB. A proxy in front may cap lower, never higher.

## Access rules

- **Hidden decks:** someone who isn't a member gets `404` for a deck and everything in it, so they can't tell it exists. A member without the needed role gets `403`.
- **Roles:**
  - the **owner** can do everything, including sharing, renaming and deleting
  - an **editor** can change cards
  - a **viewer** can study only
  - any member can leave a deck
- **Hidden answer keys:** viewers browsing a deck don't see which quiz options are correct, or the explanation. While studying, options are shuffled and sent without the key, and the server grades the answer. A wrong answer forces "Again".
- **Not secret from members:** exports and forks include the answer key, and any member can export or fork. Hiding the key prevents spoilers; it isn't secrecy.
- **Scheduling stays on the server.** Due dates and scheduler state are never read from a request. Unknown fields are rejected with `422`.

## Card content

Cards are Markdown with math and code. The client never renders raw HTML. Its pipeline:

1. Drop raw HTML.
2. Sanitize against an allowlist. Links may use `http`, `https` and `mailto` only.
3. Render math (KaTeX with `trust: false`) and highlight code on the sanitized tree.
4. Output React elements. Nothing is set through `innerHTML`.

## Containers

- **Users:** the backend image runs as uid 10001; Postgres runs as uid 70 on k8s.
- **Filesystems:** root filesystems are read-only, with tmpfs or emptyDir for `/tmp`.
- **Privileges:** all capabilities are dropped and privilege escalation is disabled.
- **k8s:** the namespace enforces Pod Security `restricted`, pods get no service account token, and NetworkPolicies limit who reaches Postgres and the API.
