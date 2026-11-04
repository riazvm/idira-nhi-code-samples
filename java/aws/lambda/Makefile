include config.env
export

JAR := $(CURDIR)/target/secrets-manager-lambda.jar
TF  := terraform -chdir=terraform
TF_VARS := -var aws_account_id=$(AWS_ACCOUNT_ID) -var region=$(AWS_REGION) \
	-var tenant_subdomain=$(TENANT_SUBDOMAIN) -var authn_service_id=$(SERVICE_ID) \
	-var policy_id=$(POLICY_ID) -var role_name=$(ROLE_NAME) \
	-var function_name=$(FUNCTION_NAME) -var jar_path=$(JAR)

.PHONY: build check-account deploy policy invoke destroy

build:
	mvn -q -DskipTests package

check-account:
	@test "$$(aws sts get-caller-identity --query Account --output text)" = "$(AWS_ACCOUNT_ID)" || \
		(echo "AWS_PROFILE=$(AWS_PROFILE) is not account $(AWS_ACCOUNT_ID)"; exit 1)

deploy: check-account build
	$(TF) init -input=false
	$(TF) apply -input=false -auto-approve $(TF_VARS)

policy:
	@mkdir -p .rendered
	@for f in workload authenticator-grant; do \
		envsubst '$$POLICY_ID $$AWS_ACCOUNT_ID $$ROLE_NAME $$SERVICE_ID' < policy/$$f.yml.tmpl > .rendered/$$f.yml; \
	done
	@echo "Rendered .rendered/workload.yml and .rendered/authenticator-grant.yml"

invoke: check-account
	@aws lambda invoke --function-name $(FUNCTION_NAME) --cli-binary-format raw-in-base64-out \
		--payload '{}' response.json --query '{status:StatusCode,error:FunctionError}' --output json
	@cat response.json; echo

destroy: check-account
	$(TF) destroy -input=false -auto-approve $(TF_VARS)
