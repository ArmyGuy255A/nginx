# Docker Hub pipeline

GitHub Actions builds and publishes `armyguy255a/nginx` to Docker Hub.

## Automatic upstream updates

`check-versions.yml` runs daily at 06:00 UTC and can be run manually from
the Actions tab. It reads `NGINX_VERSION` from `nginx/nginx`'s `master`
branch. A version bump is adopted only after nginx.org publishes both
the source tarball and its detached signature. When master contains an
unpublished development version, the checker uses the newest published
nginx release with signed source instead.

The checker retains the existing Alpine update logic: select a Docker Hub
Alpine version with a signed OpenTelemetry module package matching the
exact nginx binary version, from the correct stable/mainline channel.
Before committing updated versions, it builds the proposed Dockerfile and
runs the default HTTP and compiled-module smoke tests. Failures leave
`main` unchanged. It also tracks headers-more release tags, fancyindex
releases, the substitutions repository commit, and the exact OpenTelemetry
APK filename in `versions.json`.

Each day, even when version strings are unchanged, the checker calls the
reusable `build.yml` workflow with
the exact commit SHA. This explicit call is necessary because pushes made
using `GITHUB_TOKEN` do not trigger another push workflow.

The publishing workflow builds the image, checks its nginx version and
configuration, starts it as the default non-root user, and checks HTTP on
port 8080. Every verification build pulls its base and disables build cache,
so `apk upgrade` and downloads run again to pick up repository fixes.
Publishing reuses those freshly verified layers from Buildx cache with
SBOM and provenance attestations, then creates the `v<nginx-version>`
Git tag and GitHub release. An unsuccessful publication without a release
is retried on the next scheduled check even if the version commit landed.

Trivy scans the locally tested image before registry login. Its current
stable scanner and vulnerability database are refreshed, and fixable HIGH
or CRITICAL findings block publication. All detected severities, including
findings without a fix, are retained in the run's `vulnerability-report`
artifact for 30 days. Missing scans or unsupported/EOL Alpine scan results
also fail. Scanners have limited visibility into custom compiled C modules;
keeping source versions current and monitoring upstream advisories remain
necessary. No scan result guarantees that an image has no vulnerabilities.

The OpenTelemetry APK's signature is checked using nginx's public key with
a pinned SHA256 fingerprint. Every linked runtime library is installed and
module loading is smoke-tested. Unexpected signing-key rotation fails visibly
and requires a verified key update.

Dependabot checks GitHub Actions dependencies daily and opens grouped update
PRs. Those PRs must pass the same build, module, and scan checks before merge.

## Published tags

| Image tag | Behavior |
| --- | --- |
| `latest` | Rolling image from current `main` |
| `alpine-latest` | Same image as `latest`; existing consumer alias |
| `alpine-<nginx-version>` | Image for the pinned nginx version; refreshed on rebuilds |
| `sha-<commit>` | Image associated with the full repository commit SHA |
| `build-<run-id>-<attempt>` | Image associated with one publication attempt |

Version image tags can change when Alpine or this repository changes while
the nginx version remains the same. Daily security rebuilds can also refresh
the same commit tag. Pin an image digest for reproducibility.
Existing Git release tags are never moved. A manual historical tag build
publishes only its version image tag and does not roll back `latest`.

Pull requests build and smoke-test without logging in or publishing.
Pushes to `main` publish. Manual `build-push` runs must target current
`main` or a release tag matching `versions.json`. Publication runs are
serialized and are not canceled partway through.

## Required repository setup

The repository must enable GitHub Actions and allow its token to push
version commits and release tags to `main`. If branch rules prohibit bot
pushes, the version commit will fail visibly and those rules need an
appropriate automation exception.

Configure these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `DOCKERHUB_USERNAME` | `armyguy255a` |
| `DOCKERHUB_TOKEN` | Docker Hub access token with Read & Write access |

Do not configure a second Docker Hub automated build for the same tags;
GitHub Actions owns publishing. Confirm successful publication before
removing any existing automated build configuration.

## Verification

1. Merge the pipeline changes to `main`.
2. Run `check-versions` from the Actions tab to check upstream immediately.
3. Confirm both the version check and its called publication job succeed.
4. Confirm the GitHub release and pull `armyguy255a/nginx:latest`.
5. Run the container with `-p 8080:8080` and check HTTP at port 8080.

The default image uses `ConfigTemplate/container-nginx.conf`. Service-specific
configurations remain available under `Services/`; downstream configurations
must support the non-root nginx user.

## Module compatibility note

Fancyindex 0.6.0 removes the `fancyindex_name_length` directive. It is not
used by this repository, but downstream configurations must remove it when
upgrading from 0.5.2. See the upstream release notes:
https://github.com/aperezdc/ngx-fancyindex/releases/tag/v0.6.0
