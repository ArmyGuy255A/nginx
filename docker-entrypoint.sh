#!/bin/sh
###############################################################################
# Container entrypoint for image variants that bake a Services/<name>/
# config set into /etc/nginx/ and need runtime env-var substitution.
#
# Renders any /etc/nginx/*.conf and /etc/nginx/server-*.conf files in place,
# substituting only an allowlist of variables so nginx's own $variables
# (like $host, $remote_addr, $http_upgrade) survive intact.
#
# Currently substituted:
#   PORT                container listen port (default 8080)
#   SWA_UPSTREAM        Static Web Apps default hostname (no scheme)
#   FOUNDRY_UPSTREAM    Foundry host[:port]; empty -> /foundryvtt returns 503
#
# Add new placeholders by appending them to ALLOWLIST below and to the
# `envsubst` invocation. Keeping the allowlist explicit is intentional —
# silently substituting unknown variables would corrupt nginx-native
# expressions like $http_authorization at startup.
###############################################################################
set -eu

: "${PORT:=8080}"
: "${SWA_UPSTREAM:=}"
: "${FOUNDRY_UPSTREAM:=}"

export PORT SWA_UPSTREAM FOUNDRY_UPSTREAM

ALLOWLIST='${PORT} ${SWA_UPSTREAM} ${FOUNDRY_UPSTREAM}'

echo "[entrypoint] rendering nginx configs (PORT=${PORT}," \
     "SWA_UPSTREAM=${SWA_UPSTREAM:-<unset>}," \
     "FOUNDRY_UPSTREAM=${FOUNDRY_UPSTREAM:-<unset>})"

# Render every .conf file under /etc/nginx/ in place. Skip files inside
# /etc/nginx/conf.d/ unless we explicitly add them — that's reserved for
# vendor drop-ins which should not be templated.
for f in /etc/nginx/nginx.conf /etc/nginx/server-*.conf; do
    if [ -f "$f" ]; then
        tmp="${f}.rendered"
        envsubst "$ALLOWLIST" < "$f" > "$tmp"
        mv "$tmp" "$f"
    fi
done

# Fail fast on config errors — surfaces the offending line in ACA logs.
nginx -t

exec "$@"

