# Verification — 2026-11-27T01:54:12Z — run 45924735482

Image: `ghcr.io/maxinung/openbot-altare:v1.2.0` (built from CopilotKit/OpenBot v1.2.0).
Config: dummy env only (no real keys). The server is expected to refuse at the licence gate (exit 78) — reaching the gate at all proves the dispatcher started the services.

Control (original image, --init): s6 PID 1 error PRESENT (as expected).
## PASS: no s6 PID 1 error in fixed image, --init run.
Fixed image, PID 1 run: no s6 PID 1 error.

States: noinit state=exited exit=78 | pid1 state=exited exit=78

## Log evidence (fixed image, --init run)
```
[openbot-altare-entrypoint] not PID 1 (7); starting OpenBot services without s6
```

## Log evidence (fixed image, PID 1 run)
```
s6-rc: info: service refusal-reason: starting
s6-rc: info: service refusal-reason successfully started
```

## /health (expected unreachable without real keys)
```
noinit /health: 000
noinit /health: unreachable
pid1 /health: 000
pid1 /health: unreachable
```
