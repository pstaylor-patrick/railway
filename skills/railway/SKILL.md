---
name: railway
description: Inspect and operate Railway projects with the local `railway` CLI (a personal Ruby CLI on Railway's public GraphQL API, on PATH via ~/.local/bin/railway; source at ~/code/pstaylor-patrick/railway). Use for listing projects, services, deployments, logs, variables, and domains, and for redeploys, rollbacks, and guarded deletes.
---

# /railway skill

Use the local `railway` CLI for Railway operations. It shadows the official
Railway CLI on PATH on purpose; the commands below are this CLI's, not the
official one's.

## Auth

`bin/railway` loads the repo `.env` (a symlink to a secrets store) with
`RAILWAY_PAT_ACCOUNT` (account or workspace token) and `RAILWAY_PAT_PROJECT`
(project token, used with `--project-token`). Run `railway whoami` to see which
token type each key holds.

## Commands

Global: `-j/--json`, `--project-token`, `--project NAME|ID`, `--env NAME|ID`,
`--service NAME|ID`, `-n/--limit N`.

Reads: `whoami`, `projects`, `project`, `environments`, `services`, `status`,
`deployments`, `domains`, `volumes`, `rate`, `logs [--build] [-f] [--filter Q]`,
`vars [--reveal]`, `vars diff --env A --env2 B`.

Writes: `redeploy`, `restart`, `rollback`, `stop`, `cancel` (`--deployment ID`
or latest for `--service`), `deploy`, `vars set KEY=VALUE`, `vars delete KEY`,
`domain create|delete`, `env create|delete`, `project create|delete`,
`gql --write`.

Run `railway help` for the full option list.

## Rules

- Never print, echo, or paste token values. `vars` masks values; use
  `--reveal` only when the user asks to see a specific value.
- Deletes need `--confirm <exact name>`. Agents have no TTY, so the typed-name
  prompt is unavailable; without `--confirm` the command exits 3.
- Prefer `-j` and read the JSON rather than parsing table output.
- `gql` is read-only by default. Pass `--write` (and `--confirm OPNAME`) only
  when the user asked for that mutation.
- Ambiguous names are refused with a candidate list; retry with the ID.
- Mutations are never retried. On a network error, check the dashboard before
  running it again.
