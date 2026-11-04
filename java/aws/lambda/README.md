# Java Lambda: fetch a secret with the AWS IAM authenticator

An AWS Lambda function (Java 21) that uses its IAM role to authenticate to Secrets Manager SaaS, then fetches one secret. There is no API key or other stored credential.

The function uses `AWSIAMAuthenticator` from [`conjur-api-java`](https://github.com/cyberark/conjur-api-java) 3.3.0 or later. The class signs an STS `GetCallerIdentity` request with the role's credentials and exchanges the signed headers for an access token. The response reports only the secret's length, never its value.

## Test status

| Check | Result |
|---|---|
| Build the shaded JAR | Passed |
| Terraform `validate` and `plan` | Passed (4 resources to add) |
| Library's signed request accepted by AWS STS, using session credentials on a workstation | Passed |
| Tenant rejects an unmapped host ID | Passed (`401`) |
| Deployed on Lambda | **Not run** |
| Token issued and secret fetched | **Not run** |

## Prerequisites

- Java 21 or later, Maven, Terraform, the AWS CLI, `envsubst` and the Secrets Manager CLI
- Permission to load policy in your tenant

## Run it

1. Configure the sample:

   ```bash
   cp config.env.example config.env   # then fill in your values
   ```

2. Enable the authenticator, if it isn't already:

   ```bash
   conjur authenticator enable --id authn-iam/default
   ```

3. Create the workload and the secret. These commands assume the defaults in `config.env.example`.

   ```bash
   make policy
   conjur policy load -b data -f .rendered/workload.yml
   conjur policy load -b conjur/authn-iam/default -f .rendered/authenticator-grant.yml
   conjur variable set -i data/java-lambda-sample/db-password -v '<test value>'
   ```

4. Deploy and invoke:

   ```bash
   make deploy
   make invoke
   ```

   Call `make invoke` a second time within a few minutes. `tokenReused` should be `true` if the same execution environment handles the call.

5. Remove the AWS resources:

   ```bash
   make destroy
   ```

   This doesn't touch the tenant, so remove the policy entries separately.

## Implementation notes

- **Constructor:** the 3-argument constructor hardcodes `authn-iam/prod` and `us-east-1`, so the sample uses the 6-argument one.
- **Dependencies:** the AWS SDK `auth` and `sts` modules are optional in `conjur-api`, so `pom.xml` declares them.
- **Token caching:** `authenticate(true)` ignores its cache flag and logs in again, so the handler caches the token itself.
- **Packaging:** Jersey loads its providers through `META-INF/services`, so the shade plugin merges those files.
- **Workload ID:** the host ID must end in `<aws-account-id>/<iam-role-name>`.
- **Networking:** the function needs outbound access to your tenant. This matters if you attach it to a VPC.
