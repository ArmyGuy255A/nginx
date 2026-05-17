# Docker Hub setup for `armyguy255a/nginx`

One-time UI configuration in Docker Hub. Produces **2 image tags** (alpine-only — Ubuntu variant dropped for build-cost / pipeline simplicity):

```
armyguy255a/nginx:alpine-latest    ← rebuilds on every push to main
armyguy255a/nginx:alpine-<ver>     ← built on git-tag push v<ver>
```

> Docker Hub Automated Builds require a **Pro / Team / Business** plan.

## 1. Link GitHub source

Docker Hub → top-right avatar → **Account Settings** → **Linked accounts** → Connect GitHub. Authorize for `ArmyGuy255A/nginx`.

## 2. Create 2 Build Rules

Docker Hub → `armyguy255a/nginx` → **Builds** → **Configure Automated Builds**.

### Rule 1 — `alpine-latest` (rolling)

| Setting | Value |
|---|---|
| Source type | **Branch** |
| Source | `main` |
| **Docker tag** | **`alpine-latest`** |
| Dockerfile location | `Dockerfile.alpine` |
| Build context | `/` |
| Autobuild | ON |
| Build caching | ON |

### Rule 2 — `alpine-<version>` (immutable)

| Setting | Value |
|---|---|
| Source type | **Tag** |
| Source | `/^v(.+)$/` |
| **Docker tag** | **`alpine-{\1}`** |
| Dockerfile location | `Dockerfile.alpine` |
| Build context | `/` |
| Autobuild | ON |

## 3. (Optional) Description sync

Repo → **Settings** → **Description** → **Sync with source repository**.

## How it flows

```
       ┌──────────────────────────────────────┐
       │ check-versions.yml (daily 06:00 UTC) │
       │ probes nginx.org / DH alpine tags    │
       └──────────────────┬───────────────────┘
                          │ if any version drifts
                          ▼
                rewrites versions.json + Dockerfile.alpine
                commits "chore(deps): …" + pushes to main
                          │
                          │  branch-push trigger
                          ▼
                  Rule 1 → :alpine-latest
                          │
                          │ if nginx version specifically changed
                          ▼
                also pushes tag v<new-nginx>
                          │  tag-push trigger
                          ▼
                  Rule 2 → :alpine-<new>
```

Alpine patch-level bumps (3.22.4 → 3.22.5) surface through `:alpine-latest` only. Versioned tags are immutable snapshots.

## Major.minor Alpine bumps

The workflow stays within whichever `major.minor` is currently pinned (e.g. 3.22.x). To migrate to a new minor:

```diff
- "alpine": "3.22.4",
+ "alpine": "3.23.0",
```

Commit + push. Workflow's next run then tracks 3.23.x patches. Guard prevents auto-bumper from grabbing a too-new Alpine where `nginx-module-otel` hasn't been published yet.

## Verifying after setup

1. Push a no-op commit to `main`. Rule 1 fires (~1 min).
2. Push the existing `v1.26.2` tag: `git push origin refs/tags/v1.26.2`. Rule 2 fires.
3. `docker pull armyguy255a/nginx:alpine-latest` → 200 OK.