terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Variables ---

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "sns_topic_arn" {
  type        = string
  description = "ARN of the SNS topic for price notifications"
}

variable "fmp_api_key" {
  type        = string
  sensitive   = true
  description = "Financial Modeling Prep API key"
}

variable "stock_symbol" {
  type    = string
  default = "AMZN"
}

variable "target_price" {
  type    = number
  default = 300
}

# --- KMS Key for Lambda env var encryption ---

resource "aws_kms_key" "lambda_env" {
  description         = "Encrypts Lambda environment variables at rest"
  enable_key_rotation = true
}

resource "aws_kms_alias" "lambda_env" {
  name          = "alias/daily-stock-checker-lambda-env"
  target_key_id = aws_kms_key.lambda_env.key_id
}

# --- DLQ ---

resource "aws_sqs_queue" "lambda_dlq" {
  name                    = "daily-stock-checker-dlq"
  sqs_managed_sse_enabled = true
}

# --- IAM ---

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_dlq.arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "daily-stock-checker-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda" {
  name   = "daily-stock-checker-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# --- Lambda ---

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "stock_checker" {
  function_name                  = "daily-stock-checker"
  role                           = aws_iam_role.lambda.arn
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.12"
  timeout                        = 30
  memory_size                    = 128
  reserved_concurrent_executions = 1
  kms_key_arn                    = aws_kms_key.lambda_env.arn
  filename                       = data.archive_file.lambda_zip.output_path
  source_code_hash               = data.archive_file.lambda_zip.output_base64sha256

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      API_KEY       = var.fmp_api_key
      STOCK         = var.stock_symbol
      TARGET        = tostring(var.target_price)
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
  }
}

# --- EventBridge Schedule ---

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "daily-stock-checker-schedule"
  description         = "Triggers stock checker Lambda Mon-Fri at 5 PM UTC"
  schedule_expression = "cron(0 17 ? * MON-FRI *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.daily_schedule.name
  arn  = aws_lambda_function.stock_checker.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stock_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}
