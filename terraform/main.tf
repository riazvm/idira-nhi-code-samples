###############################################################################
# CyberArk Secrets Hub - sync policies (single state, no modules)
#
# Provider 0.3.10 fixes the nil-pointer panic in sync_policy Read (0.3.9).
# The ignore_changes on `transformation` works around a bug that is still in
# 0.3.10: Read never writes `transformation` back to state, so every plan after
# creation would try an in-place update, and the provider does not support
# updates ("Updating the sync policy is not supported through terraform").
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cyberark = {
      source  = "cyberark/cyberark"
      version = "0.3.10" # one exact version: a comma in a constraint means AND
    }
  }
}

provider "cyberark" {
  tenant        = var.cyberark_tenant
  domain        = var.cyberark_domain
  client_id     = var.cyberark_client_id
  client_secret = var.cyberark_client_secret
}

# One resource block, one entry per policy in var.sync_policies.
# To add a policy, add an entry to the map in terraform.tfvars and re-apply.
resource "cyberark_sync_policy" "this" {
  for_each = var.sync_policies

  name        = each.key
  description = each.value.description
  source_id   = each.value.source_id
  target_id   = each.value.target_id
  safe_name   = each.value.safe_name
  # A literal, not each.value: 0.3.10 rejects an unknown value in ValidateConfig,
  # and for_each attributes are unknown when Terraform validates the block.
  transformation = "password_only_plain_text"

  lifecycle {
    # Workaround for the provider Read bug described above. Remove it once the
    # provider reads `transformation` back from the API.
    ignore_changes = [transformation]
  }
}

# ---------------------------------------------------------------------------
# Existing policies already in state under other addresses
# ---------------------------------------------------------------------------
# If policy #1 was created earlier as, e.g., cyberark_sync_policy.policy_1,
# uncomment and adapt so Terraform moves it to the new address instead of
# destroying and recreating it. Remove the block after a successful apply.
#
# moved {
#   from = cyberark_sync_policy.policy_1
#   to   = cyberark_sync_policy.this["policy_1"]
# }

output "sync_policy_ids" {
  description = "Secrets Hub sync policy IDs, keyed by policy name."
  value       = { for k, p in cyberark_sync_policy.this : k => p.id }
}