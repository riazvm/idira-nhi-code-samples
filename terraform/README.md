# Secrets Hub sync policies with Terraform

This project creates CyberArk Secrets Hub sync policies with Terraform. Each policy syncs one Privilege Cloud Safe to a target secret store and sends the password only, as plain text.

All policies are defined in a single map in `terraform.tfvars`. One entry creates one policy.

| File | Purpose |
|---|---|
| `main.tf` | Provider, the `cyberark_sync_policy` resource, output |
| `Variables.tf` | Input variables |
| `terraform.tfvars.example` | Template for your values |

## Before you start

Have the following ready. Every step below assumes they exist.

1. **Terraform 1.5 or later**, plus `curl` and `jq`.
2. **A service user** in CyberArk Identity that Terraform signs in as:
   1. In the Identity Administration portal, open **Manage → Users** and add a user, for example `svc-tf-secretshub`.
   2. Set a password. Terraform uses it as the client secret.
   3. Select **Is OAuth confidential client** and **Password never expires**.
   4. Open **Manage → Roles → Secrets Hub Admin** and add the user as a member.
3. **One Safe per policy** in Privilege Cloud. Add the built-in **SecretsHub** user to each Safe as a member, with these permissions:
   - List accounts
   - Retrieve accounts
   - View Safe members
   - Access Safe without confirmation, if the Safe uses dual control
4. **A target secret store** in Secrets Hub that supports plaintext passwords, such as **AWS Secrets Manager** or **Azure Key Vault**. HashiCorp Vault targets do not support plaintext passwords, and policy creation fails with `PLCY00036E`.

## Step 1: Find your tenant values

| Value | Where to find it | Example |
|---|---|---|
| Identity tenant ID | The host of your Identity URL `https://<tenant>.id.cyberark.cloud` | `abc1234` |
| Subdomain | The host of your Secrets Hub URL `https://<subdomain>.secretshub.cyberark.cloud` | `mycompany` |
| Client ID | Service user login name, with its suffix | `svc-tf-secretshub@cyberark.cloud.1234` |

Enter the tenant ID in lowercase, even if the portal shows it in uppercase.

## Step 2: Set the client secret

Set the secret as an environment variable in the shell you run Terraform from. Do not put it in any file.

```bash
export TF_VAR_cyberark_client_secret='<service user password>'
```

## Step 3: Look up the store IDs

Get a token, then list the secret stores. Replace `<tenant>`, `<subdomain>` and `<client id>`.

```bash
TOKEN=$(curl -s https://<tenant>.id.cyberark.cloud/oauth2/platformtoken -d grant_type=client_credentials --data-urlencode "client_id=<client id>" --data-urlencode "client_secret=$TF_VAR_cyberark_client_secret" | jq -r .access_token)
```

```bash
curl -s -H "Authorization: Bearer $TOKEN" https://<subdomain>.secretshub.cyberark.cloud/api/secret-stores | jq -r '.secretStores[] | "\(.id)  \(.type)  \(.name)"'
```

- The store of type `PAM_PCLOUD` is your **source_id**.
- Your AWS or Azure store is your **target_id**.

If `TOKEN` is empty or `null`, the sign-in failed. See [Troubleshooting](#troubleshooting).

## Step 4: Configure the policies

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
cyberark_tenant    = "abc1234"
cyberark_domain    = "mycompany"
cyberark_client_id = "svc-tf-secretshub@cyberark.cloud.1234"

sync_policies = {
  finance_aws = {
    description = "Finance Safe to AWS"
    source_id   = "store-<PAM_PCLOUD store id>"
    target_id   = "store-<target store id>"
    safe_name   = "FINANCE_SAFE"
  }
}
```

The map key (`finance_aws`) becomes the policy name in Secrets Hub. Each key must be unique. Renaming a key deletes that policy and creates a new one with the new name.

`terraform.tfvars` is excluded from Git. Do not commit it.

## Step 5: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Check each result before you continue:

| Command | Expected result |
|---|---|
| `terraform plan` | `N to add, 0 to change, 0 to destroy` |
| `terraform apply` | `Apply complete! Resources: N added` |
| `terraform plan`, run again | `No changes.` |

The policy IDs are printed in the `sync_policy_ids` output.

## Step 6: Verify

For each policy ID, confirm that the transformation is set:

```bash
curl -s -H "Authorization: Bearer $TOKEN" "https://<subdomain>.secretshub.cyberark.cloud/api/policies/<policy id>?projection=REGULAR" | jq '{name, transformation}'
```

Expected: `"transformation": { "predefined": "password_only_plain_text" }`.

You can also open the policy in the Secrets Hub UI and check that the transformation is **Password only, plain text**.

## Managing policies

| To | Do this |
|---|---|
| **Add** a policy | Add an entry to `sync_policies`, then run `terraform apply`. Only the new policy is created. |
| **Remove** a policy | Delete its entry, then run `terraform apply`. Only that policy is deleted. |
| **Change** a policy | Follow [Changing a policy](#changing-a-policy). |
| **Remove all** policies | Run `terraform destroy`. |

### Changing a policy

The provider cannot update a policy in place. To change a policy, replace it: Terraform deletes the policy and creates it again with the new values.

1. Edit the policy's entry in `terraform.tfvars`, for example `safe_name` or `description`. Keep the same key.
2. Run the apply with `-replace`, using the policy's key:

   ```bash
   terraform apply -replace='cyberark_sync_policy.this["finance_aws"]'
   ```

3. Check the plan before you type `yes`. It must show `-/+ ... must be replaced` and `1 to add, 0 to change, 1 to destroy`, for that policy only.
4. Run `terraform plan`. Expected: `No changes.`

Do not run a plain `terraform apply` after editing an entry. Terraform plans an in-place update, and the apply fails with `Updating the sync policy is not supported through terraform`.

Syncing for that Safe stops for a few seconds between the delete and the create. Secrets already in the target store are not removed.

To replace several policies, repeat `-replace` once per policy in the same command.

### Adopting a policy that is already in Terraform state

If a policy was created earlier under a different resource address (check with `terraform state list`), move it into the map instead of recreating it:

1. In `main.tf`, uncomment the `moved` block and set `from` to the old address and `to` to the new map key.
2. Run `terraform plan`. The plan must say `has moved to` and must not show any destroy or replace.
3. Run `terraform apply`, then delete the `moved` block.

## Provider version and known issues

This project pins `cyberark/cyberark` to **0.3.10**. Do not use 0.3.9: it crashes when it reads a new policy.

0.3.10 has two known issues. This project works around both. Do not remove the workarounds until a provider release fixes the issues.

| Issue | Workaround in this project |
|---|---|
| The provider does not read the transformation back from Secrets Hub. Without the workaround, every plan after creation shows `~ transformation = null -> "password_only_plain_text"`, and the apply fails with `Updating the sync policy is not supported through terraform`. | `lifecycle { ignore_changes = [transformation] }` in `main.tf` |
| The provider rejects a transformation value that comes from a variable inside `for_each`, with `Invalid Transformation Value ... got:` and an empty value. | `transformation = "password_only_plain_text"` is set as a literal in `main.tf`, not per policy |

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| `access_denied: invalid client creds or client not allowed` | Wrong secret, or the service user is not an OAuth confidential client | Re-export `TF_VAR_cyberark_client_secret`. Confirm **Is OAuth confidential client** is selected for the user. |
| `GNRL0003E Unauthorized` / `Token is not valid` | The token is missing or expired | Rerun the `TOKEN=` command from Step 3. |
| `HTTP 403` from Secrets Hub | The service user is not in the Secrets Hub Admin role | Add the user to the role (see Before you start, item 2). |
| `PLCY00036E ... does not support plaintext passwords` | The target store type does not support plaintext passwords | Use an AWS Secrets Manager or Azure Key Vault target. |
| `Sync policy filter not ready` | Secrets Hub has not finished creating the policy | Wait one minute and run the command again. |
| `Updating the sync policy is not supported through terraform` | An existing entry was edited and applied without `-replace`, or the `ignore_changes` workaround was removed | Rerun the apply with `-replace` (see [Changing a policy](#changing-a-policy)). Restore `ignore_changes` if it was removed. |
| `Invalid Transformation Value` | `transformation` was changed to use `each.value` | Restore the literal `"password_only_plain_text"` in `main.tf`. |
| Terraform prompts `var.cyberark_client_secret` | The secret is not exported in this shell | Press Ctrl+C, run Step 2, then rerun the command. |
| Terraform prompts for `cyberark_tenant` or another value | `terraform.tfvars` is missing, or you are in the wrong directory | Run Terraform from this directory and complete Step 4. |
| A policy is created but nothing syncs | The SecretsHub user is not a member of the Safe | Add the SecretsHub user to the Safe (see Before you start, item 3). |
