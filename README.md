# railway

A personal Railway CLI on the public GraphQL API
(`https://backboard.railway.com/graphql/v2`), written in Ruby with the standard
library only. MIT licensed (see `LICENSE`).

This binary is named `railway` and shadows the official Railway CLI on PATH. That is deliberate. Do not install the official CLI to ~/.local/bin/railway.

## Install

```bash
ruby install.rb
```

The installer is idempotent. It:

- symlinks `~/.local/bin/railway` to `bin/railway`, and aborts if that path holds
  anything other than a symlink into this repo;
- sets `git config core.hooksPath .githooks` (pre-commit leak guard);
- links `skills/railway` into `~/.claude/skills`, registers it for Pi, and
  copies it for OpenCode.

## Environment

Keys (see `.env.example`):

| Key | Purpose |
| --- | --- |
| `RAILWAY_PAT_ACCOUNT` | account or workspace token |
| `RAILWAY_PAT_PROJECT` | project token, used with `--project-token` |

Keep the real values outside the repo and symlink them in:

```bash
ln -s /path/to/secrets/railway.env .env
```

`.env` is git-ignored and the pre-commit hook refuses to commit it.

## Token types

| Type | Header | Detected by |
| --- | --- | --- |
| Account | `Authorization: Bearer <t>` | `me` |
| Workspace | `Authorization: Bearer <t>` | `apiToken { workspaces }` |
| Project | `Project-Access-Token: <t>` | `projectToken { projectId environmentId }` |

`railway whoami` reports the type of each configured token.

## Commands

Global options: `-j/--json`, `--project-token`, `--project NAME|ID`,
`--env NAME|ID`, `--service NAME|ID`, `-n/--limit N`.

| Command | What it does |
| --- | --- |
| `whoami` | token type and identity |
| `projects`, `project` | list projects; one project's environments, services, last deploy |
| `environments`, `services`, `status` | listing and per-service deploy status |
| `deployments`, `domains`, `volumes` | recent deployments, domains, volumes and backups |
| `logs` | deploy or build logs, `-f` to follow by polling |
| `vars` | masked variables, `--reveal`, `diff`, `set`, `delete` |
| `redeploy`, `restart`, `rollback`, `stop`, `cancel`, `deploy` | deployment actions |
| `domain create/delete`, `env create/delete`, `project create/delete` | resource writes |
| `gql` | raw GraphQL; mutations need `--write` |
| `rate` | last known rate-limit headers |

Deletes require typing the resource name, or `--confirm <name>` when there is no
TTY. Run `railway help` for every option.

## Exit codes

- 0: success
- 1: API, auth, or network error
- 2: usage error, including a `--project`, `--env`, `--service`, or delete target that does not resolve (nothing is deleted)
- 3: delete refused because the name was not confirmed

## Leak guard

```bash
cp .leakguard.local.example .leakguard.local   # add your own identifiers, one regex per line
ruby bin/leakguard
```

`.leakguard.local` is git-ignored. CI reads the same patterns from the
`LEAKGUARD_PATTERNS` secret.

## Schema refresh

`docs/railway-schema.json` is an introspection snapshot. To refresh it, run an
introspection query through `railway gql -j -f <introspection.graphql>`, write
the result over the snapshot, and update `lib/railway_cli/queries.rb` for any
renamed fields.

## Rate limits

Railway rate-limits API tokens per hour and per second. Queries retry on 429
using `Retry-After`; mutations report and stop. `logs -f` polls no faster than
every 2 seconds and backs off when under 10% of the budget remains. `railway rate`
shows the last seen limits.
