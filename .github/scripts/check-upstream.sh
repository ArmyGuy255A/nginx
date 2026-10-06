#!/usr/bin/env bash
set -euo pipefail

nginx=$(curl --retry 3 -fsSL https://raw.githubusercontent.com/nginx/nginx/master/src/core/nginx.h \
  | sed -nE 's/^#define NGINX_VERSION[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p')
[[ "$nginx" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid nginx version' >&2; exit 1; }
for suffix in tar.gz tar.gz.asc; do
  status=$(curl --retry 3 -sSL --head -o /dev/null -w '%{http_code}' "https://nginx.org/download/nginx-$nginx.$suffix")
  if [ "$status" = 404 ]; then
    echo "Master version $nginx is unpublished; resolving the newest signed release"
    nginx=$(gh api 'repos/nginx/nginx/releases?per_page=100' \
      --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
      | sed -nE 's/^release-([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' | sort -V | tail -n 1)
    [[ "$nginx" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'No valid nginx release found' >&2; exit 1; }
    curl --retry 3 -fsSL --head "https://nginx.org/download/nginx-$nginx.tar.gz" >/dev/null
    curl --retry 3 -fsSL --head "https://nginx.org/download/nginx-$nginx.tar.gz.asc" >/dev/null
    break
  fi
  [ "$status" = 200 ] || { echo "nginx source probe failed: HTTP $status" >&2; exit 1; }
done

headers_more=$(gh api --paginate 'repos/openresty/headers-more-nginx-module/tags?per_page=100' --jq '.[].name' \
  | sed -nE 's/^v([0-9]+\.[0-9]+(\.[0-9]+)?)$/\1/p' | sort -V | tail -n 1)
fancyindex=$(gh api --paginate 'repos/aperezdc/ngx-fancyindex/releases?per_page=100' \
  --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
  | sed -nE 's/^v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' | sort -V | tail -n 1)
substitutions=$(gh api repos/yaoweibin/ngx_http_substitutions_filter_module/commits/HEAD --jq .sha)
[[ "$headers_more" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo 'Invalid headers-more version' >&2; exit 1; }
[[ "$fancyindex" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid fancyindex version' >&2; exit 1; }
[[ "$substitutions" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid substitutions commit' >&2; exit 1; }

channel=stable
minor=$(echo "$nginx" | cut -d. -f2)
if (( minor % 2 == 1 )); then channel=mainline; fi
base=https://nginx.org/packages
if [ "$channel" = mainline ]; then base=$base/mainline; fi

# Follow all tag pages instead of relying on Docker Hub's first 200 tags.
url='https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100'
tags='[]'
while [ -n "$url" ]; do
  [[ "$url" == https://hub.docker.com/v2/repositories/library/alpine/tags* ]] || { echo 'Unexpected Docker Hub pagination URL' >&2; exit 1; }
  page=$(curl --retry 3 -fsSL "$url")
  names=$(jq -c '[.results[].name]' <<< "$page")
  tags=$(jq -cn --argjson previous "$tags" --argjson names "$names" '$previous + $names')
  url=$(jq -r '.next // empty' <<< "$page")
done
minors=$(jq -r '.[] | select(test("^[0-9]+\\.[0-9]+$"))' <<< "$tags" | sort -Vr | uniq)
alpine=''
otel=''
for mm in $minors; do
  url="$base/alpine/v$mm/main/x86_64/"
  listing=$(curl --retry 3 -sSL -w '\n%{http_code}' "$url")
  status=${listing##*$'\n'}
  if [ "$status" = 404 ]; then continue; fi
  [ "$status" = 200 ] || { echo "nginx module probe failed: HTTP $status" >&2; exit 1; }
  # The module must match nginx's binary version, not merely exist.
  otel=$(grep -oE 'nginx-module-otel-[0-9.]+-r[0-9]+\.apk' <<< "${listing%$'\n'*}" \
    | grep -F "nginx-module-otel-$nginx." | sort -Vu | tail -n 1 || true)
  if [ -z "$otel" ]; then
    echo "::warning::Alpine $mm has no OpenTelemetry APK for nginx $nginx; trying an older Alpine"
    continue
  fi
  alpine=$(jq -r '.[]' <<< "$tags" | grep -E "^${mm//./\\.}\\.[0-9]+$" | sort -V | tail -n 1 || true)
  if [ -z "$alpine" ]; then alpine=$mm; fi
  break
done
[ -n "$alpine" ] && [ -n "$otel" ] || { echo 'No Alpine with a matching nginx module found' >&2; exit 1; }
{
  echo "nginx=$nginx"
  echo "alpine=$alpine"
  echo "headers_more=$headers_more"
  echo "fancyindex=$fancyindex"
  echo "substitutions=$substitutions"
  echo "otel=$otel"
  echo "channel=$channel"
} >> "$GITHUB_OUTPUT"
echo "Resolved nginx $nginx / Alpine $alpine / headers-more $headers_more / fancyindex $fancyindex / substitutions $substitutions / $otel"
