variable "subscription_id" {
  description = "Target Azure subscription ID. Defaults to the appeid edge subscription (same one PhotoGallery uses)."
  type        = string
  default     = "4fc243fa-5de2-48cb-9c98-793701d13152"
}

variable "resource_group_name" {
  description = "Resource group holding the nginx edge proxy. Per convention starts with 'appeid'."
  type        = string
  default     = "appeid-edge-prod"

  validation {
    condition     = startswith(var.resource_group_name, "appeid")
    error_message = "resource_group_name must start with 'appeid' (project convention)."
  }
}

variable "location" {
  description = "Azure region for the edge footprint."
  type        = string
  default     = "eastus2"
}

variable "owner_tag" {
  description = "Free-form owner tag for cost tracking."
  type        = string
  default     = "appeid-edge"
}

variable "apex_domain" {
  description = "Apex domain bound to the edge proxy, e.g. 'appeid.app'."
  type        = string
  default     = "appeid.app"
}

variable "image_repository" {
  description = <<-EOT
    Container image repository (registry + name, without tag). Defaults to
    the appeid-baked variant on Docker Hub, which is what hooks/build +
    hooks/post_push publish from the Rule 2 Build Rule when Dockerfile.appeid
    is the configured Dockerfile.
  EOT
  type        = string
  default     = "docker.io/armyguy255a/nginx"
}

variable "image_tag" {
  description = <<-EOT
    Initial image tag pulled at first deploy. Defaults to the appeid family
    of tags emitted by hooks/build. After bootstrap, the
    .github/workflows/deploy-aca.yml workflow bumps the tag via
    `az containerapp update --image` and Terraform stops managing it.
  EOT
  type        = string
  default     = "appeid-latest"
}

variable "dev_principal_object_id" {
  description = <<-EOT
    AAD object ID of the human/group running `terraform/bootstrap/upload-certs.ps1`
    against this footprint. Granted Key Vault Certificates Officer + Secrets
    Officer on the KV so they can upload the PFX and chain certs. Leave
    empty when running TF in CI; you can grant manually later with:

      az role assignment create --assignee <oid> \
        --role "Key Vault Certificates Officer" \
        --scope $(terraform output -raw key_vault_id)
  EOT
  type        = string
  default     = ""
}

variable "pfx_certificate_name" {
  description = <<-EOT
    Name of the KV Certificate object that holds the apex PFX (server cert
    + private key + intermediate chain). Created by upload-certs.ps1.
    Read by Terraform via data.azurerm_key_vault_certificate when
    bind_custom_domain = true.
  EOT
  type        = string
  default     = "appeid-tls"
}

variable "max_replicas" {
  description = "ACA HTTP scale rule upper bound."
  type        = number
  default     = 3
}

variable "swa_upstream" {
  description = <<-EOT
    Azure Static Web Apps default hostname (no scheme, no trailing slash)
    that the /photogallery/ location proxies to, e.g.
    "agreeable-tree-043fa290f.7.azurestaticapps.net". Get from
    PhotoGallery's terraform output `static_web_app_default_host_name`.
  EOT
  type        = string
}

variable "foundry_upstream" {
  description = <<-EOT
    FoundryVTT host[:port] the /foundryvtt/ location proxies to. Leave
    empty to disable the route (nginx returns 503 for /foundryvtt/*).
  EOT
  type        = string
  default     = ""
}

variable "bind_custom_domain" {
  description = <<-EOT
    Bind appeid.app + www.appeid.app to the container app and issue Azure-
    managed certs. Set to false on the first apply (zone-only) so NS
    delegation at the registrar can be completed before the validator
    runs. Flip to true on the second apply.
  EOT
  type        = bool
  default     = false
}

variable "github_actions_principal_id" {
  description = <<-EOT
    Object ID of an existing AAD service principal (typically the one
    PhotoGallery's terraform/dev provisions via module.github_oidc) to
    grant Contributor on this RG. The GitHub Actions deploy workflow
    federates to this principal and uses it to run
    `az containerapp update --image`. Leave empty to skip the role
    assignment (you can run `az` deployments locally with your own login
    until CI is wired up).
  EOT
  type        = string
  default     = ""
}
