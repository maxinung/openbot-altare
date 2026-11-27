# openbot-altare

OpenBot rebuilt so it runs on **Altare (free tier) Docker Apps**.

## The problem

Altare's runner owns PID 1, so the official image's s6-overlay entrypoint
`/init` aborts on every start:

```
s6-overlay-suexec: fatal: can only run as pid 1
[altare] The app exited with code 100.
```

Altare has no entrypoint override (its Start command only replaces CMD),
and no s6-free OpenBot image exists. Free Workstation seats are all taken,
so the fix has to be a rebuilt image in the existing Docker App.

## The fix

This image keeps the official `ghcr.io/copilotkit/openbot:v1.2.0` untouched
and only swaps the entrypoint for a dispatcher
(`openbot-altare-entrypoint.sh`):

- **As PID 1** it execs `/init`, exactly as upstream intends — s6 supervises.
- **Not PID 1** (Altare's runner owns PID 1) it starts s6's services
  directly, without s6 — Hermes-style
  (cf. NousResearch/hermes-agent#75974): it dumps the container environment
  into s6's env dir (what `/init` stage 1 does at boot, via `s6-dumpenv`),
  runs the oneshots (`postgres-init`, `computer-token`), then starts
  `postgres`, `computer` and `api` from their own `run` scripts, with `api`
  in the foreground so its exit (e.g. exit 78 on a start refusal) stops the
  container, as s6 would.

It also persists the embedded PostgreSQL data in the platform's data folder
(`/data`, Altare's Data folder) when one is present, so a redeploy does not
wipe the cluster.

## Use in Altare

Image: **`ghcr.io/maxinung/openbot-altare:v1.2.0`** (public, no registry login)

- Port: **3001**
- Data folder: `/data`
- Variables (set in the Altare app, never in this repo): `EMBEDDED_POSTGRES=on`
  (or a `DATABASE_URL`), `KEY_ENCRYPTION_KEY`, `INTELLIGENCE_API_URL`,
  `INTELLIGENCE_GATEWAY_WS_URL`, `CPK_INTELLIGENCE_API_KEY`,
  a model key (`OPENAI_API_KEY` or an OpenAI-compatible `OPENAI_BASE_URL`
  + key), `OPENBOT_SINGLE_USER=true`, plus an identity provider
  (`GOOGLE_OAUTH_*` / `MICROSOFT_OAUTH_*` / `OKTA_OAUTH_*` with
  `BETTER_AUTH_URL`, `BETTER_AUTH_SECRET`, `INITIAL_ADMIN_EMAILS`).
  See OpenBot's `docs/configuration.md` for the full list.

## Verification

Every push builds the image, pushes it to ghcr.io, and runs it both as
PID 1 and with `docker --init` (entrypoint not PID 1, like Altare) using
dummy config only. The latest result is in
[`verification/last-run.md`](verification/last-run.md). `/health` can only
serve with real CopilotKit Intelligence + model keys, so the check asserts
"no s6 PID 1 error + services reach the licence gate", not `/health`.
