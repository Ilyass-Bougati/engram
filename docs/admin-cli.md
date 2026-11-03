# Admin CLI

Run these inside the backend container:

- Compose: `docker compose exec backend …`
- k8s: `kubectl -n engram exec -it deploy/backend -- …`
- From a checkout: `uv run …` in `backend/`, with `DATABASE_URL` and `JWT_SECRET` set.

| Command | What it does |
|---|---|
| `python -m app.cli create-admin <username>` | Creates an admin. Prompts for the password twice. |
| `python -m app.cli set-password <username>` | Sets a new password and signs out all of that user's sessions. The app sends no email, so this is how a forgotten password gets reset. |
| `python -m app.cli wait-for-migrations [--timeout 300]` | Blocks until the database schema matches the code, then exits 0. It exits non-zero at the timeout. The k8s initContainer uses it. |

`create-admin` and `set-password` accept `--password-stdin`, which reads the password from the first line of stdin instead of prompting:

```bash
printf '%s\n' "$PASSWORD" | docker compose exec -T backend python -m app.cli set-password noor --password-stdin
```

Everything else is done in the app:

- **Invites:** admins create invite links under Admin → Invites. A link works once and expires after 7 days.
- **Accounts:** admins can deactivate users or change their role under Admin → Users. Nobody can deactivate or demote themselves or the last admin.
