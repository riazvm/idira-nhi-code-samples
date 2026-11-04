terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
}

resource "aws_iam_role" "lambda" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "secret_reader" {
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "java21"
  handler          = "com.idira.samples.lambda.SecretHandler::handleRequest"
  filename         = var.jar_path
  source_code_hash = filebase64sha256(var.jar_path)
  memory_size      = 1024
  timeout          = 30

  environment {
    variables = {
      CONJUR_APPLIANCE_URL        = "https://${var.tenant_subdomain}.secretsmgr.cyberark.cloud/api"
      CONJUR_ACCOUNT              = "conjur"
      CONJUR_AUTHN_IAM_SERVICE_ID = var.authn_service_id
      CONJUR_HOST_ID              = "host/data/${var.policy_id}/${var.aws_account_id}/${var.role_name}"
      SECRET_ID                   = "data/${var.policy_id}/db-password"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.logs, aws_cloudwatch_log_group.lambda]
}

output "function_name" {
  value = aws_lambda_function.secret_reader.function_name
}
