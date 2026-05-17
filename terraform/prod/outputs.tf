output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "container_app_name" {
  description = "Use in `az containerapp update --name <this> --resource-group <rg> --image <new-tag>` from CI."
  value       = azurerm_container_app.edge.name
}

output "container_app_default_fqdn" {
  description = "Default *.azurecontainerapps.io FQDN. Useful for smoke testing before DNS delegates."
  value       = azurerm_container_app.edge.latest_revision_fqdn
}

output "container_app_url" {
  description = "Default URL for the edge proxy at its ACA hostname."
  value       = "https://${azurerm_container_app.edge.latest_revision_fqdn}"
}

output "dns_zone_name" {
  value = azurerm_dns_zone.apex.name
}

output "dns_zone_nameservers" {
  description = "Azure-assigned NS records. Paste these into GoDaddy to delegate the apex."
  value       = azurerm_dns_zone.apex.name_servers
}

output "apex_url" {
  description = "Public HTTPS URL once DNS + custom-domain binding complete."
  value       = "https://${var.apex_domain}"
}

###############################################################################
# Key Vault — used by terraform/bootstrap/upload-certs.ps1 to push the PFX
# and chain certs after a first-pass apply.
###############################################################################

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_id" {
  description = "Use for `az role assignment create --scope`."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "pfx_certificate_name" {
  description = "KV Certificate name that upload-certs.ps1 should target for the apex PFX."
  value       = var.pfx_certificate_name
}

###############################################################################
# Managed identity — exposed for diagnostics. The role assignment giving
# it `Key Vault Secrets User` is handled inside main.tf.
###############################################################################

output "container_app_uami_principal_id" {
  value = azurerm_user_assigned_identity.edge.principal_id
}

output "container_app_uami_client_id" {
  value = azurerm_user_assigned_identity.edge.client_id
}
