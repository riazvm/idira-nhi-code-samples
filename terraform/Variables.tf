variable "cyberark_tenant" {
  description = "CyberArk Identity (Shared Services) tenant ID, e.g. abc1234."
  type        = string
}

variable "cyberark_domain" {
  description = "Privilege Cloud subdomain, e.g. mycompany for mycompany.privilegecloud.cyberark.cloud."
  type        = string
}

variable "cyberark_client_id" {
  description = "Service user, formatted as username@cyberark.cloud.<tenant>."
  type        = string
}

variable "cyberark_client_secret" {
  description = "Service user password. Pass via TF_VAR_cyberark_client_secret, never commit it."
  type        = string
  sensitive   = true
}

variable "sync_policies" {
  description = "Sync policies to create. The map key becomes the policy name."
  type = map(object({
    description = optional(string)
    source_id   = string # Privilege Cloud secret store ID (store-...)
    target_id   = string # Target store ID (AWS Secrets Manager or Azure Key Vault)
    safe_name   = string
  }))
}