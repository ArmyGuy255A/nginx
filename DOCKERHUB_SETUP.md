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

## 3. Webhook: Docker Hub → GitHub Actions

So a successful Docker Hub build automatically triggers `deploy-aca.yml`.

1. Create a **fine-grained PAT** in GitHub:
   - Settings → Developer settings → Personal access tokens → Fine-grained tokens → **Generate new token**.
   - Resource owner: `ArmyGuy255A`
   - Repository access: `Only select repositories` → `ArmyGuy255A/nginx`
   - Permissions: **Actions: Read and write**, **Contents: Read-only**.
   - Copy the token (starts with `github_pat_...`).

2. Docker Hub → `armyguy255a/nginx` → **Webhooks** → **New webhook**.

   - Webhook name: `gh-deploy-aca`
   - Webhook URL: `https://api.github.com/repos/ArmyGuy255A/nginx/dispatches`

3. Docker Hub doesn't let you set arbitrary headers on the basic webhook. **Two workarounds**:

   - **Option A (recommended)** — Use a small intermediary like Cloudflare Workers / Vercel function / Azure Function that listens on a public URL, validates the DH payload, then calls GH dispatches with the PAT in the Authorization header. The Worker code is 15 lines; sample below.
   - **Option B** — Use `https://X:<TOKEN>@api.github.com/repos/...` URL-embedded basic auth. GitHub's dispatches endpoint accepts this, but the token appears in logs. **Not recommended for long-lived use.**

### Cloudflare Worker (Option A) sample

```javascript
// Worker URL becomes the Docker Hub webhook target.
// Set DH_SHARED_SECRET (Docker Hub doesn't sign payloads, so we use a
// shared secret in the URL: ?s=<value>) and GH_PAT as Worker secrets.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.searchParams.get('s') !== env.DH_SHARED_SECRET) {
      return new Response('forbidden', { status: 403 });
    }
    const payload = await request.json();
    // Docker Hub push_data.tag is e.g. "appeid-1.26.2.5"
    const tag = payload?.push_data?.tag ?? 'latest';

    const resp = await fetch(
      'https://api.github.com/repos/ArmyGuy255A/nginx/dispatches',
      {
        method: 'POST',
        headers: {
          'Authorization': `token ${env.GH_PAT}`,
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'docker-hub-dispatcher',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          event_type: 'docker-hub-push',
          client_payload: { tag },
        }),
      }
    );
    return new Response(`gh status ${resp.status}`, { status: resp.status });
  },
};
```

Webhook URL in Docker Hub: `https://<worker-name>.<your-handle>.workers.dev/?s=<DH_SHARED_SECRET>`.

Filter the webhook so it only fires for `appeid-*` tags (Docker Hub webhooks don't filter, so the Worker can early-return if tag doesn't start with `appeid-`).

### Verify the end-to-end loop

After Webhook setup:

1. Push a tag from GitHub: `git tag v1.26.2.999 main && git push origin v1.26.2.999`
2. Watch Docker Hub Builds tab — both Rules should fire and complete green.
3. Watch the dispatched GitHub Actions run on the `nginx` repo — `deploy-aca.yml` runs.
4. ACA should show a new revision with the bumped image tag, `Healthy` within ~30s.
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
                                   │ webhook → CF Worker → GH dispatches
                                   ▼
                ┌──────────────────────────────────────┐
                │ deploy-aca.yml                       │
                │ az containerapp update --image       │
                └──────────────────────────────────────┘

  Weekly security-rebuild.yml fires cut-release.yml directly with no code
  change, producing v<NGINX>.<NEXT> so DH rebuilds with current Alpine.
```

Touch points where you (the human) intervene:

- **Merge** the `auto-bump` PR when it appears (and the validate workflow is green). Everything else is hands-off.
- **Replace the PFX in Key Vault** annually (or whenever GoDaddy renews); `terraform apply` to re-bind.
