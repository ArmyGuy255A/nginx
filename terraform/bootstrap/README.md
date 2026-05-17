# State bootstrap

One-time setup to create the Azure Storage account that holds Terraform state for `terraform/prod`. Run from a shell where you're logged in via `az login` against the target subscription.

```pwsh
.\bootstrap-state.ps1 -SubscriptionId 4fc243fa-5de2-48cb-9c98-793701d13152
```

The script:

1. Creates resource group `appeid-tfstate` (idempotent).
2. Creates a globally unique storage account `tfstateappeid<NNNN>` (idempotent — re-uses if you supply `-StateAccount`).
3. Creates a `tfstate` container with versioning enabled.
4. Writes `../prod/backend.prod.hcl` populated with the storage account name.

After bootstrap:

```pwsh
cd ..\prod
terraform init -backend-config=backend.prod.hcl
terraform apply -var "swa_upstream=<the SWA default hostname>"
```
