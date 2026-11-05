# Engram

A self-hosted spaced-repetition flashcard app for a small group of people. Accounts are invite-only.

This file covers deployment only. Everything else is in [`docs/`](docs):

- [Configuration](docs/configuration.md): environment variables
- [Admin CLI](docs/admin-cli.md): creating admins, resetting passwords
- [Deck format](docs/deck-format.md): the JSON import/export format
- [Importing from Anki](docs/anki-import.md): what an `.apkg` import keeps and drops
- [Stats](docs/stats.md): how streaks, retention and card states are counted
- [Security](docs/security.md): sessions, rate limits, access rules, proxies
- [API](docs/api.md): scripting against the API, and its OpenAPI reference
- [Development](docs/development.md): running the checks and the end-to-end tests
- [Mobile app](docs/mobile.md): the Flutter app for Android and iOS

Engram ships as one image, `ghcr.io/l03x/engram`. The backend serves the web app and the API (`/api`) from the same origin, which the refresh cookie and the CSRF header rely on. Next to it runs Postgres.

## Option 1: Docker Compose on one machine

Requirements: Docker with Compose v2.

```bash
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 32)/; s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" .env
docker compose up -d --build --wait
docker compose exec backend python -m app.cli create-admin <your-username>
curl -fsS http://127.0.0.1:6767/api/health/ready
```

Then open http://127.0.0.1:6767 and sign in.

| Service | What it does |
|---|---|
| `db` | Postgres 16. Data lives in the named volume `engram_pgdata`. |
| `migrate` | Runs `alembic upgrade head` once, then exits. |
| `backend` | The app: web pages and `/api`, published on `127.0.0.1:6767` only. It starts after `migrate` succeeds. |

To upgrade, pull the new code and run `docker compose up -d --build --wait` again. Migrations run first.

## Option 2: k3s behind a Cloudflare Tunnel

The manifests in [`deploy/k8s/`](deploy/k8s) are plain kustomize. They contain no Ingress: cloudflared reaches the Services directly.

| Object | Kind | Notes |
|---|---|---|
| `engram` | Namespace | Pod Security `restricted` enforced |
| `postgres` | StatefulSet + headless Service | 5 Gi PVC on `local-path` |
| `engram-migrate` | Job | `alembic upgrade head`, removed 10 minutes after it finishes |
| `backend` | Deployment + ClusterIP Service at the fixed address `10.43.67.67:8000` | The app (web pages and `/api`). 1 replica. An initContainer waits until the schema matches the image. |
| `default-deny-ingress`, `postgres`, `backend` | NetworkPolicy | Postgres accepts the backend and the Job only. The app accepts pods in the namespace only. |

Every pod runs as non-root with a read-only root filesystem, no capabilities, the runtime's seccomp profile and no service account token.

### Resources (sized for a 4 GB node shared with other workloads)

| Workload | Memory request / limit | CPU request / limit |
|---|---|---|
| Postgres (`shared_buffers=128MB`, `max_connections=30`) | 256Mi / 512Mi | 100m / 1 |
| Backend (1 uvicorn worker) | 160Mi / 384Mi | 50m / 1 |
| Migration Job (only while it runs) | 128Mi / 256Mi | 50m / 500m |

In steady state Engram requests 416Mi and is capped at 896Mi.

### 1. Build and push the image

The usual way is to let GitHub do it. Set `version` in `backend/pyproject.toml`, commit, then push a matching tag:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The [release workflow](.github/workflows/release.yml) then:

1. Runs the backend and frontend checks.
2. Builds the image for amd64 and arm64. The web app is built inside it, once, since its files are the same for both.
3. Pushes it as `ghcr.io/l03x/engram:0.3.0`.

It fails if the tag and the pyproject version disagree. It doesn't touch the cluster.

To build by hand instead, run this from the repository root on any machine with Docker, logged in to GHCR with a token that has `write:packages`:

```bash
docker login ghcr.io -u l03x
docker build -t ghcr.io/l03x/engram:0.3.0 .
docker push ghcr.io/l03x/engram:0.3.0
```

If the server's CPU architecture differs from the build machine (an arm64 server, say), build for it instead:

```bash
docker buildx build --platform linux/arm64 -t ghcr.io/l03x/engram:0.3.0 --push .
```

The tag the cluster runs is set in `deploy/k8s/kustomization.yaml` under `images`.

### 2. Let the cluster pull the image

GHCR packages start out private. Either make `engram` public (on GitHub: the package → Package settings → Change visibility), or give the namespace a pull secret. For the pull secret, create the namespace first, then use a token that has `read:packages` only:

```bash
kubectl apply -f deploy/k8s/namespace.yaml
read -rs GHCR_TOKEN
kubectl -n engram create secret docker-registry ghcr --docker-server=ghcr.io --docker-username=l03x --docker-password="$GHCR_TOKEN"
kubectl -n engram patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr"}]}'
```

### 3. Create the secret

```bash
kubectl apply -f deploy/k8s/namespace.yaml
cp deploy/k8s/secret.example.yaml deploy/k8s/secret.yaml
sed -i "s/POSTGRES_PASSWORD: \"\"/POSTGRES_PASSWORD: \"$(openssl rand -hex 32)\"/; s/JWT_SECRET: \"\"/JWT_SECRET: \"$(openssl rand -hex 32)\"/" deploy/k8s/secret.yaml
kubectl apply -f deploy/k8s/secret.yaml
```

`deploy/k8s/secret.yaml` is gitignored. Keep a copy somewhere safe, such as a password manager: the database password in it can't be recovered from the cluster once the PVC is the only thing left.

### 4. Deploy

```bash
kubectl apply -k deploy/k8s
kubectl -n engram wait --for=condition=complete job/engram-migrate --timeout=5m
kubectl -n engram rollout status deploy/backend --timeout=5m
```

On a fresh install the Job may fail once or twice while Postgres initializes. It retries on its own.

### 5. Create the first admin

```bash
kubectl -n engram exec -it deploy/backend -- python -m app.cli create-admin <your-username>
```

The admin then invites everyone else from the app.

### 6. Check it

On the k3s node itself:

```bash
curl -fsS http://10.43.67.67:8000/api/health/ready
```

http://10.43.67.67:8000 in a browser on the node opens the app. From another machine, use `kubectl -n engram port-forward svc/backend 6767:8000` and `127.0.0.1:6767` instead.

The Service's address is fixed in `backend.yaml` and sits in k3s's default service range. If your cluster uses a different `--service-cidr`, change it or remove the line. A Service's address can't change in place: if `apply` reports `may not change once set`, run `kubectl -n engram delete svc backend` once, then apply again.

### 7. Point the tunnel at it

Inside the cluster the app is `http://backend.engram.svc.cluster.local:8000`. On the node itself it is `http://10.43.67.67:8000`, which is the address to use if cloudflared runs as a host service rather than a pod. One rule sends the whole hostname there, pages and `/api` alike:

```yaml
ingress:
  - hostname: engram.example.com
    service: http://backend.engram.svc.cluster.local:8000
  - service: http_status:404
```

If your tunnel still has a separate `^/api/` rule from before 0.2.0, remove it: the backend now answers every path.

Two things depend on where cloudflared runs:

- **The NetworkPolicy.** The `backend` policy admits pods in the `engram` namespace only. If cloudflared runs in another namespace, add a `namespaceSelector` for it to [`networkpolicy.yaml`](deploy/k8s/networkpolicy.yaml).
- **Client IPs.** The rate limiter sees cloudflared's address, not the visitor's, until the backend is told to trust it. See `FORWARDED_ALLOW_IPS` in [configuration](docs/configuration.md).

### Upgrading

**From 0.1.x to 0.2.0:** the image was renamed from `engram-backend` to `engram`, and it now contains the web app. On GitHub that's a new package, which starts out private again: make it public, or keep using the pull secret from step 2. Also simplify the tunnel to the single rule in step 7.

Release the new version (step 1), wait for the workflow to finish, then set the new tag under `images` in `kustomization.yaml`. A Job can't be changed in place, so delete the finished one before applying:

```bash
kubectl -n engram delete job engram-migrate --ignore-not-found
kubectl apply -k deploy/k8s
kubectl -n engram rollout status deploy/backend --timeout=5m
```

The new backend pod waits until the Job has migrated the schema. The Deployment uses `Recreate`, so the API is down for a few seconds during the switch.

### Backups

```bash
kubectl -n engram exec postgres-0 -- pg_dump -U engram -d engram --format=custom > engram-$(date +%F).dump
```

To restore into an empty database:

```bash
kubectl -n engram exec -i postgres-0 -- pg_restore -U engram -d engram --clean --if-exists < engram-YYYY-MM-DD.dump
```

The data itself lives under k3s's local-path directory on the node (`/var/lib/rancher/k3s/storage` by default). Deleting the namespace deletes the PVC and that data with it.
