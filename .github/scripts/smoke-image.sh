#!/usr/bin/env bash
set -euo pipefail
image=${1:?image name required}
version=$("${PYTHON:-python3}" -c 'import json; print(json.load(open("versions.json"))["nginx"])')
docker run --rm "$image" nginx -v 2>&1 | grep -F "nginx/$version"
docker run --rm "$image" nginx -t
name="nginx-smoke-${GITHUB_RUN_ID:-local}-$$"
cleanup() { docker logs "$name"; docker rm -f "$name"; }
trap cleanup EXIT
docker run -d --name "$name" -p 127.0.0.1:8080:8080 "$image"
curl --silent --show-error --output /dev/null --retry 10 --retry-connrefused --retry-delay 2 --fail http://127.0.0.1:8080/
docker rm -f "$name"
# Copying a test config avoids platform-specific bind-mount translations.
docker create --name "$name" -p 127.0.0.1:8080:8080 "$image" nginx -c /tmp/smoke.conf -g 'daemon off;'
docker cp .github/scripts/smoke-nginx.conf "$name:/tmp/smoke.conf"
docker start "$name"
docker exec "$name" sh -c 'mkdir -p /var/www/html/module-smoke && printf test > /var/www/html/module-smoke/module-file.txt'
response=$(curl --silent --show-error --retry 10 --retry-connrefused --retry-delay 2 --fail -i http://127.0.0.1:8080/module-smoke/)
grep -qi 'X-Module-Smoke: passed' <<< "$response"
grep -q 'module-substitution-passed' <<< "$response"
grep -q 'module-file.txt' <<< "$response"
echo 'Default HTTP, OpenTelemetry loading, headers-more, fancyindex, and substitutions passed'
