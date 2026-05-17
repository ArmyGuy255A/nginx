# Docker Hub setup for `armyguy255a/nginx`

One-time configuration in the Docker Hub UI to wire up Automated Builds against this GitHub repo, and a Docker Hub → GitHub webhook so ACA deploys automatically when a new image lands.

> Note: Docker Hub Automated Builds require a **Pro / Team / Business** plan. The classic free tier had the feature removed in 2021.

## 1. Link GitHub source code

1. Docker Hub → top-right avatar → **Account Settings** → **Linked accounts**.
2. Click **Connect** next to GitHub. Authorize the Docker Hub OAuth app against `ArmyGuy255A/nginx` (organization scope is fine).

## 2. Create two Build Rules

Both rules target the same Docker Hub repo (`armyguy255a/nginx`) and the same GitHub repo (`ArmyGuy255A/nginx`). They differ only in **Dockerfile location** + **Docker Tag** pattern.

Docker Hub → `armyguy255a/nginx` repo → **Builds** → **Configure Automated Builds**.

### Rule 1 — base nginx image

| Setting | Value |
|---|---|
| Source repository | `ArmyGuy255A/nginx` |
| Source type | **Tag** |
| Source | `/^v(.+)$/` (regex; captures the version part) |
| Docker tag | `alpine-{\1}` |
| Dockerfile location | `Dockerfile.alpine` |
| Build context | `/` |
| Autobuild | ON |
| Build caching | ON |

Result: pushing tag `v1.26.2.5` to GitHub builds and publishes `armyguy255a/nginx:alpine-1.26.2.5`. `hooks/post_push` additionally pushes `:latest` and `:alpine-1.26.2.5-<sha>`.

### Rule 2 — appeid edge-proxy variant

| Setting | Value |
|---|---|
| Source repository | `ArmyGuy255A/nginx` |
| Source type | **Tag** |
| Source | `/^v(.+)$/` |
| Docker tag | `appeid-{\1}` |
| Dockerfile location | `Dockerfile.appeid` |
| Build context | `/` |
| Autobuild | ON |
| Build caching | ON |
| Build environment variables | `BUILD_ORDER=2` (forces this to build after Rule 1 so `FROM armyguy255a/nginx:alpine-…` exists) |

Result: pushing tag `v1.26.2.5` also builds `armyguy255a/nginx:appeid-1.26.2.5`. `hooks/post_push` adds `:appeid-latest` and `:appeid-1.26.2.5-<sha>`.

### Sanity check

After saving both rules, click **Trigger** on Rule 1 against the existing `1.26.2` tag (which we created during the branch consolidation). Watch the build log — you should see `[hooks/build] DOCKERFILE_PATH=Dockerfile.alpine VARIANT=base`. Then trigger Rule 2 the same way.

If the build succeeds, the tag list on the repo should now include:

```
alpine-1.26.2     <- Rule 1
appeid-1.26.2     <- Rule 2
latest            <- hooks/post_push
appeid-latest     <- hooks/post_push
1.26.2-<sha>      <- hooks/post_push (legacy short tag, can ignore)
appeid-1.26.2-<sha>
```

## 3. ACA pull cadence — no webhook needed

GitHub Actions polls Docker Hub once a day (`.github/workflows/deploy-aca.yml`, cron `7 4 * * *` — 04:07 UTC) and rolls the ACA Container App **only if** the `appeid-latest` digest on Docker Hub differs from what's currently running. No webhook, no PAT in a URL, no Cloudflare Worker.

The poll uses Docker Hub's public JSON API (`/v2/repositories/<repo>/tags/<tag>`) which doesn't require auth for public images, so there's nothing to configure on the Docker Hub side.

To force a roll between polls:

```sh
# pin a specific tag
gh workflow run deploy-aca.yml -f image_ref=armyguy255a/nginx:appeid-1.26.2.5

# or just nudge it to re-check appeid-latest now
gh workflow run deploy-aca.yml -f force=true
```

To change the cadence, edit the `cron:` value in `deploy-aca.yml`:

| Use case | Cron |
|---|---|
| Daily 04:07 UTC (default) | `7 4 * * *` |
| Every 6 hours | `7 */6 * * *` |
| Hourly | `7 * * * *` |

### Verify the end-to-end loop

1. Push a tag from GitHub: `git tag v1.26.2.999 main && git push origin v1.26.2.999`
2. Watch Docker Hub Builds tab — both Rules should fire and complete green.
3. Within the next day (or sooner if you `workflow_dispatch`), `deploy-aca.yml` picks up the new digest and rolls ACA.
4. ACA's new revision reaches `Healthy` within ~30s; the workflow runs a `/healthz` smoke test.
5. `curl -I https://appeid.app/healthz` → 200.

## 4. (Optional) Repository description sync

Docker Hub supports syncing the `README.md` from the linked GitHub repo as the repo description. Toggle this under repo Settings → **Description** → **Sync with source repository**. Keeps the Docker Hub page in lockstep with the GitHub README.

## What's automated end-to-end

```
                ┌─────────────────────────────────┐
                │ check-nginx-version.yml (daily) │
                │ nginx.org > nginx_version.txt?  │
                └──────────────────┬──────────────┘
                                   │ opens PR (auto-bump)
                                   ▼
              ┌──────────────────────────────────────┐
              │ Reviewer merges PR  →  push to main  │
              └──────────────────┬───────────────────┘
                                 │
                ┌────────────────┴────────────────────┐
                │ cut-release.yml                     │
                │ tags v<NGINX>.<BUILD> + GH Release  │
                └────────────────┬────────────────────┘
                                 │ tag push
                                 ▼
                ┌──────────────────────────────────────┐
                │ Docker Hub Builds (Rules 1 + 2)      │
                │ alpine-<v>, appeid-<v>, :latest, ... │
                └──────────────────┬───────────────────┘
                                   │ (no webhook)
                                   ▼
                ┌──────────────────────────────────────┐
                │ deploy-aca.yml (cron 7 * * * *)      │
                │ digest-compare → update if changed   │
                └──────────────────────────────────────┘

  Weekly security-rebuild.yml fires cut-release.yml directly with no code
  change, producing v<NGINX>.<NEXT> so DH rebuilds with current Alpine.
```

Touch points where you (the human) intervene:

- **Merge** the `auto-bump` PR when it appears (and the validate workflow is green). Everything else is hands-off.
- **Replace the PFX in Key Vault** annually (or whenever GoDaddy renews); `terraform apply` to re-bind.
