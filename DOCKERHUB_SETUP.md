# Docker Hub setup for `armyguy255a/nginx`

One-time UI configuration in Docker Hub to wire up Automated Builds against this GitHub repo. Produces **exactly 4 image tags** with **3-segment nginx version** (no build counter):

```
armyguy255a/nginx:alpine-latest      ← rebuilds on every push to main
armyguy255a/nginx:ubuntu-latest      ← rebuilds on every push to main
armyguy255a/nginx:alpine-<version>   ← built on git-tag push v<version>
armyguy255a/nginx:ubuntu-<version>   ← built on git-tag push v<version>
```

> Docker Hub Automated Builds require a **Pro / Team / Business** plan.

## 1. Link GitHub source

Docker Hub → top-right avatar → **Account Settings** → **Linked accounts** → Connect GitHub and authorize for `ArmyGuy255A/nginx`.

## 2. Create 4 Build Rules

Docker Hub → `armyguy255a/nginx` repo → **Builds** → **Configure Automated Builds**. All four rules target the same Docker Hub repo + same source repo. Differences are highlighted.

### Rule 1 — `alpine-latest` (rolling)

| Setting | Value |
|---|---|
| Source type | **Branch** |
| Source | `main` |
| **Docker tag** | **`alpine-latest`** |
| **Dockerfile location** | **`Dockerfile.alpine`** |
| Build context | `/` |
| Autobuild | ON |
| Build caching | ON |

### Rule 2 — `ubuntu-latest` (rolling)

Same as Rule 1 except:

| Setting | Value |
|---|---|
| **Docker tag** | **`ubuntu-latest`** |
| **Dockerfile location** | **`Dockerfile.ubuntu`** |

### Rule 3 — `alpine-<version>` (immutable)

| Setting | Value |
|---|---|
| Source type | **Tag** |
| Source | `/^v(.+)$/`  *(regex; captures the version)* |
| **Docker tag** | **`alpine-{\1}`** |
| **Dockerfile location** | **`Dockerfile.alpine`** |
| Build context | `/` |
| Autobuild | ON |

### Rule 4 — `ubuntu-<version>` (immutable)

Same as Rule 3 except:

| Setting | Value |
|---|---|
| **Docker tag** | **`ubuntu-{\1}`** |
| **Dockerfile location** | **`Dockerfile.ubuntu`** |

## 3. (Optional) Description sync

Repo → **Settings** → **Description** → toggle **Sync with source repository** so the Docker Hub overview mirrors this repo's README.

## How it all flows

```
       ┌──────────────────────────────────────┐
       │ check-versions.yml (daily 06:00 UTC) │
       │ probes nginx.org / DH library tags / │
       │ openssl.org / zlib.net              │
       └──────────────────┬───────────────────┘
                          │ if any version drifts
                          ▼
       ┌──────────────────────────────────────┐
       │ rewrites versions.json + Dockerfiles │
       │ commits "chore(deps): …"             │
       │ pushes to main                       │
       └──────────────────┬───────────────────┘
                          │
       ┌──────────────────┴───────────────────┐
       │  branch-push triggers (Rules 1 + 2)  │
       │  → :alpine-latest, :ubuntu-latest    │
       └──────────────────────────────────────┘
                          │
                          │ if nginx version specifically changed
                          ▼
       ┌──────────────────────────────────────┐
       │ also pushes tag v<new-nginx>         │
       └──────────────────┬───────────────────┘
                          │
       ┌──────────────────┴───────────────────┐
       │  tag-push triggers (Rules 3 + 4)     │
       │  → :alpine-<new>, :ubuntu-<new>      │
       └──────────────────────────────────────┘
```

Alpine / openssl / zlib bumps surface through `:alpine-latest` and `:ubuntu-latest` only. **Versioned tags are immutable snapshots** of "this exact nginx version on the Alpine/Ubuntu state when the version was first cut." Consumers wanting auto-updated base images pin `:alpine-latest`; consumers wanting reproducibility pin a specific version.

## Verifying after setup

1. Push a no-op commit to `main` (e.g. README typo fix). Both Rule 1 + Rule 2 should fire and complete within a few minutes.
2. Manually push the existing `v1.26.2` tag (already created during branch consolidation): `git push origin refs/tags/v1.26.2`. Rules 3 + 4 should fire. *(Skip if you've already done this once.)*
3. `docker pull armyguy255a/nginx:alpine-latest` → 200 OK; image labels include `org.opencontainers.image.version=1.26.2`.
