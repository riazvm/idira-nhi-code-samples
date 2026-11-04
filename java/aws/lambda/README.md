# Retrieve secrets in an AWS Lambda function using Java

This sample shows a Java AWS Lambda function that retrieves a secret from Secrets Manager SaaS. The function authenticates with its IAM role, so you don't need to store an API key or any other credential with it.

## How it works

1. The function signs an AWS STS `GetCallerIdentity` request with its IAM role credentials.
2. It sends the signed request to the Secrets Manager AWS IAM authenticator.
3. Secrets Manager asks AWS to verify the request, then matches the AWS account and role to a workload.
4. Secrets Manager returns a short-lived access token.
5. The function uses the token to retrieve the secret.

The sample uses `AWSIAMAuthenticator` from the [Secrets Manager Java client](https://github.com/cyberark/conjur-api-java), version 3.3.0 or later. The function must include this library. You can package it with your function, as this sample does, or provide it in a Lambda layer.

## Before you begin

You need:

- Your Secrets Manager SaaS subdomain
- A Secrets Manager user who can load policy and enable authenticators
- An AWS account where you can create IAM roles and Lambda functions
- Java 21 or later, Maven, Terraform 1.5 or later, the AWS CLI, `envsubst`, `make` and the Secrets Manager CLI

## Step 1: Configure the sample

From this directory, copy the example configuration:

```bash
cp config.env.example config.env
```

Edit `config.env`:

| Setting | Value |
|---|---|
| `AWS_PROFILE` | AWS CLI profile to deploy with |
| `AWS_ACCOUNT_ID` | Account to deploy to. The deployment stops if the profile uses a different account. |
| `AWS_REGION` | Region to deploy to |
| `TENANT_SUBDOMAIN` | Your subdomain, for example `acme` for `acme.secretsmgr.cyberark.cloud` |
| `SERVICE_ID` | Authenticator service ID. `default` is the predefined authenticator. |
| `POLICY_ID` | Policy branch to create under `data` |
| `ROLE_NAME` | IAM role to create for the function |
| `FUNCTION_NAME` | Lambda function to create |

The remaining steps assume you kept the example values for `SERVICE_ID` and `POLICY_ID`. If you changed them, change the commands to match.

## Step 2: Set up Secrets Manager

1. Log in to your tenant:

   ```bash
   conjur init saas -u https://<subdomain>.secretsmgr.cyberark.cloud/api
   conjur login
   ```

2. Enable the AWS IAM authenticator, if it isn't already enabled:

   ```bash
   conjur authenticator enable --id authn-iam/default
   ```

3. Generate the policy files from your configuration:

   ```bash
   make policy
   ```

   This creates two files in `.rendered/`:
   - `workload.yml` defines the secret, and a workload named after your AWS account and IAM role.
   - `authenticator-grant.yml` allows the workload to use the authenticator.

4. Load both files:

   ```bash
   conjur policy load -b data -f .rendered/workload.yml
   conjur policy load -b conjur/authn-iam/default -f .rendered/authenticator-grant.yml
   ```

5. Give the secret a test value:

   ```bash
   conjur variable set -i data/java-lambda-sample/db-password -v 'test-value'
   ```

   Use a test value only, because this command can save the value in your shell history.

## Step 3: Deploy the function

```bash
make deploy
```

This builds the function and uses Terraform to create the following in your AWS account:

- The IAM role, with permission to write logs
- The Lambda function
- A CloudWatch log group that keeps logs for 7 days

The role doesn't need any added permission to authenticate, because `GetCallerIdentity` doesn't require one.

## Step 4: Test the function

Invoke the function twice:

```bash
make invoke
make invoke
```

A successful response looks like this:

```json
{
  "secretId": "data/java-lambda-sample/db-password",
  "secretLength": 10,
  "tokenReused": true,
  "tokenExpires": "2026-11-05T00:01:35.000Z"
}
```

- `secretLength` shows that the secret was retrieved. The sample never returns or logs the value.
- `tokenReused` is `false` on a cold start. It's usually `true` on the next call, when the same execution environment handles it.

In our test with 1,024 MB of memory, the first invocation took about 3.7 seconds, and later invocations took about 100 ms.

## Step 5: Clean up

1. Remove the AWS resources:

   ```bash
   make destroy
   ```

2. Remove the workload and secret from Secrets Manager. `make destroy` doesn't change your tenant.

## Use this in your own function

1. Add `conjur-api` and the AWS SDK `auth` and `sts` modules to your build. The AWS modules are optional in `conjur-api`, so you must declare them. See [pom.xml](pom.xml).
2. If you build a shaded JAR, merge the `META-INF/services` files. The Java client's HTTP library needs them at runtime.
3. Create a workload named `<aws-account-id>/<iam-role-name>`, and grant it access to the authenticator and your secrets.
4. Set the environment variables below.
5. Adapt [SecretHandler.java](src/main/java/com/idira/samples/lambda/SecretHandler.java).

| Environment variable | Value |
|---|---|
| `CONJUR_APPLIANCE_URL` | `https://<subdomain>.secretsmgr.cyberark.cloud/api` |
| `CONJUR_ACCOUNT` | `conjur` |
| `CONJUR_HOST_ID` | `host/data/<policy>/<aws-account-id>/<iam-role-name>` |
| `CONJUR_AUTHN_IAM_SERVICE_ID` | Authenticator service ID, such as `default` |
| `SECRET_ID` | Secret path, such as `data/<policy>/db-password` |

Lambda sets `AWS_REGION` and the role credentials for you.

Keep these points in mind:

- **Set the authenticator and region explicitly.** The 3-argument `AWSIAMAuthenticator` constructor always uses `authn-iam/prod` and `us-east-1`. Use the 6-argument constructor, as the sample does.
- **Reuse the access token.** Tokens last about 8 minutes, and `authenticate(true)` doesn't use a cached token. Cache the token yourself to avoid logging in on every invocation, as the sample does.
- **Retrieve secrets as bytes.** `retrieveSecret` is deprecated. Use `retrieveSecretBytes`, and clear the array when you finish with it. Avoid converting the value to a `String`, because you can't clear a `String` from memory.
- **Allow outbound access.** The function must be able to reach your tenant over HTTPS. If you attach it to a VPC, make sure the VPC provides that route.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `401` when authenticating | The authenticator is enabled. The workload is a member of the authenticator's `apps` group. The workload name exactly matches the AWS account ID and role name. `CONJUR_HOST_ID` starts with `host/`. |
| `403` when retrieving the secret | The workload has `execute` permission on the secret. |
| `404` when retrieving the secret | `SECRET_ID` is correct, and the secret has a value. |
| `404` when authenticating | The service ID is correct. |
| Timeout | The function has outbound HTTPS access to your tenant. |
| `ClassNotFoundException` for a Jersey class | Your shaded JAR merges the `META-INF/services` files. |
| `AWS_PROFILE ... is not account ...` during deployment | `AWS_PROFILE` and `AWS_ACCOUNT_ID` in `config.env` refer to the same account. |
