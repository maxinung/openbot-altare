# OpenBot image rebuilt for Altare (free tier Docker Apps).
#
# Altare's runner owns PID 1, so s6-overlay's /init — the official image's
# entrypoint — aborts with "s6-overlay-suexec: fatal: can only run as pid 1".
# Altare has no entrypoint override (its Start command only replaces CMD).
#
# This image keeps the official image untouched and only swaps the entrypoint
# for a dispatcher (openbot-altare-entrypoint.sh): as PID 1 it execs /init as
# upstream intends; as a child process it starts s6's services directly
# (Hermes-style, cf. NousResearch/hermes-agent#75974).
FROM ghcr.io/copilotkit/openbot:v1.2.0

COPY openbot-altare-entrypoint.sh /app/bin/openbot-altare-entrypoint.sh
RUN chmod +x /app/bin/openbot-altare-entrypoint.sh

ENTRYPOINT ["/app/bin/openbot-altare-entrypoint.sh"]
