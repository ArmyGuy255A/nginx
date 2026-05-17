###############################################################################
# appeid-edge / nginx — production environment
#
# Provisions the Azure footprint that fronts appeid.app with the
# armyguy255a/nginx:appeid-* image (built and pushed by Docker Hub
# Automated Builds):
#
#   * Resource group `appeid-edge-prod`
#   * Azure Key Vault (RBAC, purge-protection on) — holds the TLS PFX and
#     the chain certs as KV Certificates
#   * User-assigned managed identity for the container app, with
#     `Key Vault Secrets User` on the KV so ACA can read the PFX at start
#   * Container Apps Environment (Consumption plan)
#   * Container App `edge-nginx`, single revision, HTTP-only inside the
#     container — ACA terminates TLS at the platform edge using the KV-
#     sourced cert. UAMI attached for runtime KV access.
#   * Azure DNS zone for `appeid.app` (delegate NS at GoDaddy)
#   * Apex + www custom-domain bindings against the KV-sourced cert
#
# Cost (East US 2, list prices):
#   ACA Consumption, 1 replica 0.25vCPU/0.5GiB always-on   ~$11/mo
#   Key Vault (standard, RBAC, < 10k ops/mo)               ~$0.05/mo
#   Azure DNS zone                                          ~$0.50/mo
#   Custom-domain bound to KV cert (no extra Azure fee)     $0
#   ──────────────────────────────────────────────────────────────
#   TOTAL                                                  ~$12/mo
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # Soft-delete is always on for new vaults. Disabling purge protection
      # here so dev recreate cycles aren't blocked; flip to false (i.e. ON)
      # before you put a long-lived cert in here.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

locals {
  common_tags = {
    project = "appeid-edge"
    env     = "prod"
    owner   = var.owner_tag
    managed = "terraform"
  }
}

###############################################################################
# Resource group
###############################################################################

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

###############################################################################
# Key Vault — holds the TLS PFX (cert + key + chain) and the standalone
# chain certs. RBAC-only (no access policies) so role assignments are the
# single source of truth.
###############################################################################

resource "azurerm_key_vault" "this" {
  name                = "kv-appeid-edge-${substr(md5(azurerm_resource_group.this.id), 0, 6)}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = local.common_tags
}

# Operator (the human running `az keyvault certificate import`) needs
# Certificates Officer to upload the PFX + chain. Use the AAD object ID of
# the operating user/group; defaults to "" so CI doesn't accidentally
# self-grant.
resource "azurerm_role_assignment" "kv_operator_certs" {
  count                = var.dev_principal_object_id == "" ? 0 : 1
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = var.dev_principal_object_id
}

resource "azurerm_role_assignment" "kv_operator_secrets" {
  count                = var.dev_principal_object_id == "" ? 0 : 1
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.dev_principal_object_id
}

###############################################################################
# User-assigned MI for the container app + RBAC for KV reads.
#
# Granting `Key Vault Secrets User` (NOT Certificates User) is intentional —
# when you import a PFX via `az keyvault certificate import`, it lands as
# both a certificate AND a backing secret. ACA reads the PFX via the
# secret URI, which requires Secrets User.
###############################################################################

resource "azurerm_user_assigned_identity" "edge" {
  name                = "uami-edge-nginx"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "uami_kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.edge.principal_id
}

###############################################################################
# Container Apps environment + app
###############################################################################

resource "azurerm_container_app_environment" "this" {
  name                = "cae-${var.resource_group_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_container_app" "edge" {
  name                         = "edge-nginx"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.edge.id]
  }

  template {
    min_replicas = 1
    max_replicas = var.max_replicas

    container {
      name   = "nginx"
      image  = "${var.image_repository}:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "PORT"
        value = "8080"
      }

      env {
        name  = "SWA_UPSTREAM"
        value = var.swa_upstream
      }

      env {
        name  = "FOUNDRY_UPSTREAM"
        value = var.foundry_upstream
      }

      liveness_probe {
        path             = "/healthz"
        port             = 8080
        transport        = "HTTP"
        initial_delay    = 5
        interval_seconds = 30
        timeout          = 3
      }

      readiness_probe {
        path             = "/healthz"
        port             = 8080
        transport        = "HTTP"
        interval_seconds = 10
        timeout          = 3
      }
    }

    http_scale_rule {
      name                = "http-rps"
      concurrent_requests = 50
    }
  }

  ingress {
    external_enabled           = true
    target_port                = 8080
    transport                  = "http"
    allow_insecure_connections = false
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # Image tag rollouts happen via `az containerapp update` from CI, not via
  # terraform. Ignoring the container image keeps `terraform apply` and CI
  # from fighting each other.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
    ]
  }
}

###############################################################################
# DNS — Azure DNS zone for appeid.app, A-alias to the container app.
###############################################################################

resource "azurerm_dns_zone" "apex" {
  name                = var.apex_domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_dns_a_record" "apex_alias" {
  name                = "@"
  zone_name           = azurerm_dns_zone.apex.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  target_resource_id  = azurerm_container_app.edge.id
}

resource "azurerm_dns_cname_record" "www" {
  name                = "www"
  zone_name           = azurerm_dns_zone.apex.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  record              = azurerm_container_app.edge.latest_revision_fqdn
}

###############################################################################
# TLS — KV-sourced PFX bound to the ACA environment, then mapped to the
# apex + www custom domains.
#
# Two-step apply on first creation:
#   1. terraform apply -var "bind_custom_domain=false"
#      (creates RG, KV, UAMI, ACA env+app, DNS zone — but NOT the cert
#      resource or the custom-domain bindings)
#   2. Run terraform/bootstrap/upload-certs.ps1 to push the PFX + chain
#      certs into the KV that step 1 created.
#   3. Delegate the zone's NS records at GoDaddy, wait for propagation.
#   4. terraform apply -var "bind_custom_domain=true"
#      (reads the PFX from KV, creates the env certificate, binds apex+www)
###############################################################################

data "azurerm_key_vault_certificate" "pfx" {
  count        = var.bind_custom_domain ? 1 : 0
  name         = var.pfx_certificate_name
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_container_app_environment_certificate" "appeid" {
  count                        = var.bind_custom_domain ? 1 : 0
  name                         = "cert-${replace(var.apex_domain, ".", "-")}"
  container_app_environment_id = azurerm_container_app_environment.this.id

  # The KV certificate data source resolves a `secret_id` that points at
  # the backing PFX secret. We pull it through TF (with the operator's
  # identity, not the UAMI) and hand the bytes to ACA. Rotation =
  # re-upload PFX in KV + `terraform apply` (which re-reads + re-binds).
  # The PFX created by upload-certs.ps1 has an empty password.
  certificate_blob_base64 = data.azurerm_key_vault_certificate.pfx[0].certificate_data_base64
  certificate_password    = ""

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.uami_kv_secrets_user,
  ]
}

resource "azurerm_container_app_custom_domain" "apex" {
  count            = var.bind_custom_domain ? 1 : 0
  name             = var.apex_domain
  container_app_id = azurerm_container_app.edge.id

  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.appeid[0].id
  certificate_binding_type                 = "SniEnabled"

  depends_on = [
    azurerm_dns_a_record.apex_alias,
  ]
}

resource "azurerm_container_app_custom_domain" "www" {
  count            = var.bind_custom_domain ? 1 : 0
  name             = "www.${var.apex_domain}"
  container_app_id = azurerm_container_app.edge.id

  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.appeid[0].id
  certificate_binding_type                 = "SniEnabled"

  depends_on = [
    azurerm_dns_cname_record.www,
  ]
}

###############################################################################
# GitHub Actions deploy role — grants the existing GH Actions OIDC service
# principal Contributor on this RG so it can `az containerapp update --image`
# from CI. Leave empty when running locally.
###############################################################################

resource "azurerm_role_assignment" "github_actions_contributor" {
  count                = var.github_actions_principal_id == "" ? 0 : 1
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = var.github_actions_principal_id
}
