#!/bin/bash
# OpenBot entrypoint dispatcher for hosts whose runner owns PID 1 (Altare free tier).
#
# The official image's entrypoint is s6-overlay's /init, which aborts with
#   "s6-overlay-suexec: fatal: can only run as pid 1"
# when the container runtime's own init already owns PID 1 (Altare's runner
# execs the image entrypoint as a child). This dispatcher keeps the official
# image untouched and only changes how its services are started:
#
#   - PID 1     -> exec /init, exactly as upstream intends (s6 supervises).
#   - not PID 1 -> start the s6 services directly, without s6 (Hermes-style,
#                  cf. NousResearch/hermes-agent#75974: if PID 1, exec /init;
#                  otherwise bypass s6 and run the services' own commands).
#
# The services (read from /etc/s6-overlay/s6-rc.d in the image):
#   postgres-init  (oneshot)  initdb + password, writes DATABASE_URL
#   computer-token (oneshot)  generates COMPUTER_TOKEN
#   postgres       (longrun)   embedded PostgreSQL, EMBEDDED_POSTGRES=on only
#   computer       (longrun)   the Bot's browser, EMBEDDED_COMPUTER=on (default)
#   api            (longrun)   the server; foreground process here, so when it
#                              exits (e.g. exit 78 on a start refusal, exactly
#                              as s6's api/finish halts the container) the
#                              container stops too.
set -u

export PATH="/command:/package/admin/s6/command:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# PID 1: the normal path. s6 supervises everything from here.
if [ "$$" -eq 1 ]; then
  exec /init
fi

echo "[openbot-altare-entrypoint] not PID 1 ($$); starting OpenBot services without s6" >&2

# s6-overlay's env dir (normally created by /init stage 1). The oneshots below
# write generated values (DATABASE_URL, COMPUTER_TOKEN) into it, and
# with-contenv hands them to the services, exactly as under s6.
mkdir -p /run/s6/container_environment
chmod 0700 /run/s6/container_environment 2>/dev/null || true

# Dump the container environment into the env dir, exactly as /init stage 1
# does at boot (s6-dumpenv). This is load-bearing: with-contenv clears the
# process environment and rebuilds it from this dir, so without the dump the
# services would see none of the operator's variables (no EMBEDDED_POSTGRES,
# no keys) and exit immediately.
# (Do NOT use S6_KEEP_ENV=1 instead: it skips the env-dir load entirely, so
# the generated DATABASE_URL / COMPUTER_TOKEN would never reach the services.)
/command/s6-dumpenv /run/s6/container_environment

# Persist the embedded database in the platform's data folder when one is
# present (Altare mounts it at /data). Without this, a redeploy wipes the
# cluster and its password file, since files outside /data are replaced.
if [ -d /data ] && [ ! -L /var/lib/postgresql ]; then
  if [ ! -e /data/postgresql/data/PG_VERSION ]; then
    mkdir -p /data/postgresql
    if cp -a /var/lib/postgresql/. /data/postgresql/; then
      rm -rf /var/lib/postgresql
      ln -s /data/postgresql /var/lib/postgresql
    fi
  else
    rm -rf /var/lib/postgresql
    ln -s /data/postgresql /var/lib/postgresql
  fi
  chown postgres:postgres /data/postgresql 2>/dev/null || true
fi

# Oneshots, as root, exactly as s6 would run them.
# (postgres-init.sh is a no-op unless EMBEDDED_POSTGRES=on; computer-token.sh
# leaves a preset COMPUTER_TOKEN alone.)
/command/with-contenv /etc/s6-overlay/scripts/postgres-init.sh
/command/with-contenv /etc/s6-overlay/scripts/computer-token.sh

# Long-running services, each in the background. Their run scripts exec the
# server process, so each background shell becomes that service.
pids=""
if [ "${EMBEDDED_POSTGRES:-off}" = "on" ]; then
  /command/with-contenv /etc/s6-overlay/s6-rc.d/postgres/run &
  pids="$pids $!"
fi
if [ "${EMBEDDED_COMPUTER:-on}" = "on" ]; then
  /command/with-contenv /etc/s6-overlay/s6-rc.d/computer/run &
  pids="$pids $!"
fi
/command/with-contenv /etc/s6-overlay/s6-rc.d/api/run &
api_pid=$!
pids="$pids $api_pid"

cleanup() {
  kill $pids 2>/dev/null
  wait 2>/dev/null
}
trap 'cleanup; exit 143' TERM INT

# Wait for the first service to exit, then stop the rest and exit with its
# code — mirroring s6 bringing the container down when a supervised process
# exits (and api/finish halting it on a start refusal, exit 78).
wait -n $pids
code=$?
cleanup
exit "$code"
