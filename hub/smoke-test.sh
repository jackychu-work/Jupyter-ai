#!/usr/bin/env bash
# End-to-end check: hub -> DockerSpawner -> sibling container -> proxy -> lab API.
# Uses the same cookie/xsrf flow a browser would; no API tokens needed.
# Run inside WSL (or anywhere with curl+docker against the hub daemon):
#   ./smoke-test.sh
set -euo pipefail

BASE_URL=${BASE_URL:-http://127.0.0.1:8000}
SMOKE_USER=${SMOKE_USER:-smoke}
JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT
API="${BASE_URL}/hub/api"

echo "== wait for hub"
for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "${BASE_URL}/hub/login"; then break; fi
    sleep 2
done
curl -fsS -o /dev/null "${BASE_URL}/hub/login" || { echo "hub not reachable"; exit 1; }

echo "== login as ${SMOKE_USER} (dummy auth)"
curl -fsS -o /dev/null -b "$JAR" -c "$JAR" "${BASE_URL}/hub/login"
XS=$(awk '$6 ~ /_xsrf/ {print $7}' "$JAR" | tail -1)
[ -n "$XS" ] || { echo "no xsrf cookie"; exit 1; }
curl -fsS -o /dev/null -b "$JAR" -c "$JAR" -X POST \
    --data-urlencode "username=${SMOKE_USER}" \
    --data-urlencode "password=x" \
    --data-urlencode "_xsrf=${XS}" \
    "${BASE_URL}/hub/login"

echo "== spawn"
# /hub/spawn starts the server and redirects; pending page redirects when ready.
curl -fsS -o /dev/null -b "$JAR" -c "$JAR" -L -w 'spawn %{http_code} -> %{url_effective}\n' \
    "${BASE_URL}/hub/spawn"

echo "== wait for ready"
for _ in $(seq 1 90); do
    loc=$(curl -sS -o /dev/null -b "$JAR" -c "$JAR" -w '%{redirect_url}' \
        "${BASE_URL}/hub/spawn-pending/${SMOKE_USER}")
    if [ -n "$loc" ]; then echo "ready -> $loc"; break; fi
    sleep 10
done
[ -n "$loc" ] || { echo "server never became ready"; docker logs "jupyter-${SMOKE_USER}" 2>&1 | tail -40; exit 1; }

echo "== lab page"
curl -fsS -o /dev/null -b "$JAR" -c "$JAR" -L \
    -w 'lab HTTP %{http_code}\n' "${BASE_URL}/user/${SMOKE_USER}/lab"

echo "== single-user server status"
curl -fsS -b "$JAR" -c "$JAR" "${BASE_URL}/user/${SMOKE_USER}/api/status" \
    | python3 -c 'import json,sys;d=json.load(sys.stdin);print("started:",d.get("started"))'

echo "== lab extensions (jupyter-ai present?)"
curl -fsS -b "$JAR" -c "$JAR" "${BASE_URL}/user/${SMOKE_USER}/lab/api/extensions" \
    | grep -o '"jupyter_ai[^"]*"' | sort -u || echo "no jupyter_ai extension key found"

echo "== container"
docker ps --filter "name=jupyter-${SMOKE_USER}" --format '{{.Names}} {{.Image}} {{.Status}}'

echo "== ok"
