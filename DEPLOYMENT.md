# appeid.app edge proxy — deployment runbook

End-to-end guide for getting `https://appeid.app/` (and `/photogallery/`, `/foundryvtt/`) live on Azure Container Apps fronted by this nginx image.

## Architecture

```
Browser
   │ HTTPS (cert from Key Vault, terminated by ACA)
   ▼
ACA ingress  ──HTTP──►  edge-nginx (this image)  ──HTTPS──►  SWA (PhotoGallery)
                                                ──HTTP/WSS─►  Foundry VTT host
```

- **TLS termination**: Azure Container Apps platform, using a PFX stored in this stack's Key Vault and bound to the Container App's custom domains.
- **Cert rotation**: replace the PFX in Key Vault, then `terraform apply`. ACA picks up the new bytes on the next revision (no image rebuild).
- **Image rollouts**: `.github/workflows/deploy-aca.yml` runs `az containerapp update --image` — Terraform ignores `image` changes on the container resource (see `lifecycle.ignore_changes`).

## Image build pipeline

Two Docker Hub **Automated Build Rules** point at this repo, both targeting `armyguy255a/nginx`:

| Rule | Dockerfile | Source branch | Docker tag | Tags produced |
|---|---|---|---|---|
| 1 — base | `Dockerfile.alpine` | `1.26.2` | `alpine-{sourceref}` | `:latest`, `:alpine-1.26.2`, `:alpine-1.26.2-<sha>` |
| 2 — appeid edge | `Dockerfile.appeid` | `1.26.2` | `appeid-{sourceref}` | `:appeid-latest`, `:appeid-1.26.2`, `:appeid-1.26.2-<sha>` |

`hooks/build` reads `$DOCKERFILE_PATH` from Docker Hub and routes the build + tag set per variant. `hooks/post_push` pushes the family-scoped `:latest` and `:<ver>-<sha>` tags.

**Set up in Docker Hub UI**, once: Repository → Builds → Configure Automated Builds → add two Build Rules with the table above. No GitHub Actions credits used for builds.

## Cutover (first-time setup)

Prerequisites:

- `az login` against the target Azure subscription
- `terraform` ≥ 1.6
- `openssl` (for the PFX build inside `upload-certs.ps1`)
- The four cert files from GoDaddy:
  - `appeid.app-certificate.crt`
  - `appeid.app.key` (the private key you retrieved)
  - `appeid.app-intermediate.pem`
  - `appeid.app-root.pem` (optional)

### 1. Bootstrap Terraform state

```pwsh
cd terraform\bootstrap
.\bootstrap-state.ps1
```

Creates `appeid-tfstate` RG + `tfstateappeid<NNNN>` storage account + `tfstate` container, and writes `../prod/backend.prod.hcl` with the resulting account name.

### 2. First-pass apply (no custom-domain binding yet)

```pwsh
cd ..\prod
terraform init -backend-config=backend.prod.hcl
terraform apply `
  -var "dev_principal_object_id=$(az ad signed-in-user show --query id -o tsv)" `
  -var "swa_upstream=<the SWA *.azurestaticapps.net hostname>" `
  -var "bind_custom_domain=false"
```

This creates:

- `appeid-edge-prod` RG
- Key Vault (RBAC, you get Certificates Officer + Secrets Officer)
- UAMI for the container app + `Key Vault Secrets User` role on the KV
- ACA Environment + Container App (pulling `armyguy255a/nginx:appeid-latest`)
- DNS zone for `appeid.app`

**It does NOT yet bind `appeid.app` to the app** — that happens in step 5 once the KV has the cert.

### 3. Upload the PFX + chain certs to Key Vault

```pwsh
cd ..\bootstrap
.\upload-certs.ps1 `
  -KeyVaultName    $(terraform -chdir=..\prod output -raw key_vault_name) `
  -CertPath        D:\repos\appeid.app-certificate.crt `
  -KeyPath         D:\repos\appeid.app.key `
  -IntermediatePath D:\repos\appeid.app-intermediate.pem `
  -RootPath        D:\repos\appeid.app-root.pem
```

The script:

1. Checks the private key matches the cert.
2. Builds a password-less PFX bundling **cert + key + intermediate chain** (root excluded — clients have it pinned).
3. Imports the PFX into KV as a Certificate named `appeid-tls`.
4. Imports the intermediate + root as standalone KV Certificates (`appeid-ca-intermediate`, `appeid-ca-root`) for future mTLS / audit consumers.

### 4. Delegate DNS at GoDaddy

```pwsh
terraform -chdir=..\prod output dns_zone_nameservers
```

Paste the 4 NS hostnames into GoDaddy → your domain → "Nameservers" → "Enter my own nameservers". Save. Wait 15 min – 1 hr (`nslookup -type=NS appeid.app 8.8.8.8` to verify).

### 5. Second-pass apply (bind custom domains, ACA pulls the cert from KV)

```pwsh
cd ..\prod
terraform apply `
  -var "dev_principal_object_id=$(az ad signed-in-user show --query id -o tsv)" `
  -var "swa_upstream=<the SWA *.azurestaticapps.net hostname>" `
  -var "bind_custom_domain=true"
```

Now Terraform:

- Reads the PFX from KV via the `azurerm_key_vault_certificate` data source.
- Creates `azurerm_container_app_environment_certificate.appeid` holding the PFX bytes.
- Binds `appeid.app` + `www.appeid.app` to the container app, each referencing the env cert.

ACA propagates the binding within ~5 min. After that:

```sh
curl -I https://appeid.app/healthz   # 200 ok
curl -I https://appeid.app/          # 301 -> /photogallery/
```

### 6. Configure GitHub Actions for image rollouts

In the Docker Hub repo → Webhooks, add a webhook on push events that hits:

```
POST https://api.github.com/repos/ArmyGuy255A/nginx/dispatches
Headers: Authorization: token <PAT with repo scope>
         Accept: application/vnd.github+json
Body: {"event_type":"docker-hub-push","client_payload":{"tag":"appeid-latest"}}
```

The `deploy-aca.yml` workflow listens for that dispatch and runs `az containerapp update --image`. You can also trigger it manually via `gh workflow run deploy-aca.yml -f image_tag=appeid-1.26.2-abc1234`.

The workflow uses **OIDC federation** to the AAD service principal whose object ID you pass as `var.github_actions_principal_id` in Terraform. Reuse the SP that PhotoGallery's `module.github_oidc` provisions, or create a fresh one — either works.

## Cert rotation

When you get a new cert (annual renewal):

```pwsh
cd terraform\bootstrap
.\upload-certs.ps1 -KeyVaultName <existing> -CertPath ... -KeyPath ...

cd ..\prod
terraform apply -var "bind_custom_domain=true" -var "swa_upstream=..."
```

The KV Certificate gets a new version automatically; TF re-reads the current version on apply and re-binds. No downtime — ACA hot-swaps the cert on the existing revision.

## Disaster recovery

State is in the bootstrap storage account; PFX is in Key Vault (soft-delete on, 7-day retention). To rebuild from scratch:

1. `terraform/bootstrap/bootstrap-state.ps1` (re-creates state account)
2. Recover the soft-deleted Key Vault if needed: `az keyvault recover --name <kv>`
3. `terraform apply` — re-creates everything else around the existing KV.

## Future: Foundry, ESP32 telemetry, etc.

- **Foundry VTT**: deploy as a separate Container App (or VM). Set `var.foundry_upstream` to its host:port. Update Foundry's `options.json` with `routePrefix=foundryvtt`.
- **ESP32 telemetry over MQTT**: stand up a Mosquitto Container App on a separate TCP ingress. Doesn't touch this edge proxy.
- **ESP32 over UDP**: needs ACI or a VM (ACA can't do UDP ingress). Bind a separate hostname like `telemetry.appeid.app` via another DNS A-record in the existing zone.
