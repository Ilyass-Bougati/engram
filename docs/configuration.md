# Configuration

Engram reads its configuration from environment variables only. It reads no `.env` file and no config file. The backend exits at startup if a required value is missing or invalid, and it has no fallback secrets.

## Backend

| Variable | Required | Meaning |
|---|---|---|
| `DATABASE_URL` | yes | Postgres URL. `postgresql://…` and `postgres://…` are accepted and pinned to the psycopg driver. |
| `JWT_SECRET` | yes | Signs access tokens. At least 32 characters; generate it with `openssl rand -hex 32`. Changing it signs everyone out. |
| `REFRESH_TOKEN_DAYS` | no (default 30) | Lifetime of a refresh token, from 1 to 365. Each refresh rotates the token. |
| `FORWARDED_ALLOW_IPS` | no (default `127.0.0.1,::1`) | Addresses or CIDR ranges whose `X-Forwarded-For` header uvicorn trusts. See [proxies](#proxies-and-client-ips). |

The migration Job, the `wait-for-migrations` initContainer and the admin CLI load the same settings, so they need `DATABASE_URL` and `JWT_SECRET` too.

The web app needs no configuration: it's built into the image and calls the API on its own origin.

## Deployment files

| Variable | Where | Meaning |
|---|---|---|
| `POSTGRES_PASSWORD` | `.env` (Compose), `secret.yaml` (k8s) | Password for the bundled Postgres. Both deployments build `DATABASE_URL` from it, unescaped, so keep it to URL-safe characters (`openssl rand -hex 32` is). |
| `JWT_SECRET` | `.env` (Compose), `secret.yaml` (k8s) | Passed through to the backend. |

## Frontend (development only)

| Variable | Default | Meaning |
|---|---|---|
| `ENGRAM_API_URL` | `http://127.0.0.1:6767` (the Compose backend) | Where the Vite dev server proxies `/api`. Put it in `frontend/.env.local` (gitignored) to keep it. Use `ENGRAM_API_URL=http://10.43.67.67:8000` for the k3s backend on the same machine. A value set in the environment wins, which is how the E2E run points at its own backend. |

## Proxies and client IPs

The rate limiter counts requests per client IP. uvicorn takes that address from `X-Forwarded-For`, but only when the request comes from an address in `FORWARDED_ALLOW_IPS`. Otherwise it uses the TCP peer. With the default, nothing in a cluster is trusted. Behind a tunnel or reverse proxy, every visitor then shares the proxy's address, and so shares one login budget (10 per minute).

To count visitors separately, trust the proxy's address. On k3s, pod addresses come from the cluster CIDR (`10.42.0.0/16` unless you changed it), so add this to the backend container's `env` in `deploy/k8s/backend.yaml`:

```yaml
- name: FORWARDED_ALLOW_IPS
  value: 10.42.0.0/16
```

That is safe for two reasons:

- **Only allowed pods can connect.** The `backend` NetworkPolicy admits only pods you allow (by default, those in the `engram` namespace).
- **Spoofed entries are skipped.** uvicorn reads `X-Forwarded-For` from the right and stops at the first untrusted address. A value the visitor sent sits to the left of the address Cloudflare appends, so it is never reached.

Don't set `*`.
