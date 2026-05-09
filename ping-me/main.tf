# ──────────────────────────────────────────────
# Ping-Me: API Gateway HTTP API v2 → Lambda → SNS
# ──────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ──── Variables ────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

variable "lambda_zip_path" {
  description = "Path to the Lambda deployment zip"
  type        = string
  default     = "lambda.zip"
}

# ──── Provider ────

provider "aws" {
  region = var.aws_region
}

# ──── KMS Key for Lambda env var encryption ────

resource "aws_kms_key" "lambda_env" {
  description         = "Encrypts Lambda environment variables at rest"
  enable_key_rotation = true
}

resource "aws_kms_alias" "lambda_env" {
  name          = "alias/ping-me-lambda-env"
  target_key_id = aws_kms_key.lambda_env.key_id
}

# ──── SNS Topic (encrypted) ────

resource "aws_sns_topic" "ping_me" {
  name              = "ping-me-topic"
  kms_master_key_id = "alias/aws/sns"
}

# ──── IAM Role & Policy for Lambda ────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "ping-me-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "sns_publish" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.ping_me.arn]
  }
}

resource "aws_iam_role_policy" "lambda_sns_publish" {
  name   = "ping-me-sns-publish"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.sns_publish.json
}

# ──── Lambda Function ────

resource "aws_lambda_function" "ping_me" {
  function_name                  = "ping-me"
  role                           = aws_iam_role.lambda_exec.arn
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.13"
  filename                       = var.lambda_zip_path
  timeout                        = 10
  reserved_concurrent_executions = 2
  kms_key_arn                    = aws_kms_key.lambda_env.arn

  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.ping_me.arn
    }
  }
}

# ──── API Gateway HTTP API (v2) ────

resource "aws_apigatewayv2_api" "ping_me" {
  name          = "ping-me-api"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/ping-me-api"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "ping_me" {
  api_id      = aws_apigatewayv2_api.ping_me.id
  name        = var.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.ping_me.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ping_me.invoke_arn
  payload_format_version = "2.0"
}

# authorization_type explicitly set to NONE — this is an intentionally public endpoint.
# If you want to lock it down later, switch to AWS_IAM or add a JWT authorizer.
resource "aws_apigatewayv2_route" "get_ping" {
  api_id             = aws_apigatewayv2_api.ping_me.id
  route_key          = "GET /ping-me"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

# ──── Lambda Permission for API Gateway ────

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ping_me.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ping_me.execution_arn}/*/*"
}

# ──── Outputs ────

output "api_endpoint" {
  description = "Public URL for the ping-me endpoint"
  value       = "${aws_apigatewayv2_stage.ping_me.invoke_url}/ping-me"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.ping_me.arn
}
