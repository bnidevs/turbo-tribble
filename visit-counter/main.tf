####################################################################
# Visit Counter - API Gateway (REST) -> DynamoDB direct integration
# Terraform
####################################################################

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "INSERT DEFAULT TABLE NAME HERE"
}

variable "allowed_origin" {
  description = "CORS allowed origin"
  type        = string
  default     = "INSERT DEFAULT URL HERE"
}

provider "aws" {
  region = var.region
}

# ---------- DynamoDB Table ----------

resource "aws_dynamodb_table" "visit_tracker" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "metric"

  attribute {
    name = "metric"
    type = "S"
  }
}

# Seed the counter item so the UpdateExpression doesn't fail on a
# missing attribute.  Terraform's aws_dynamodb_table_item is
# idempotent on the key so re-applies are safe.
resource "aws_dynamodb_table_item" "seed" {
  table_name = aws_dynamodb_table.visit_tracker.name
  hash_key   = aws_dynamodb_table.visit_tracker.hash_key

  item = <<ITEM
{
  "metric": {"S": "visits"},
  "amount": {"N": "0"}
}
ITEM

  lifecycle {
    ignore_changes = [item]
  }
}

# ---------- IAM Role for API Gateway → DynamoDB ----------

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "apigw_dynamo" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.visit_tracker.arn]
  }
}

resource "aws_iam_role" "apigw_dynamo" {
  name               = "visit-counter-apigw-dynamo"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy" "apigw_dynamo" {
  name   = "dynamo-update"
  role   = aws_iam_role.apigw_dynamo.id
  policy = data.aws_iam_policy_document.apigw_dynamo.json
}

# ---------- API Gateway REST API ----------

resource "aws_api_gateway_rest_api" "visit" {
  name        = "visit-counter-api"
  description = "Hit counter for ${var.allowed_origin}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "visit" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  parent_id   = aws_api_gateway_rest_api.visit.root_resource_id
  path_part   = "visit"
}

# ----- GET /visit -----

resource "aws_api_gateway_method" "get_visit" {
  rest_api_id   = aws_api_gateway_rest_api.visit.id
  resource_id   = aws_api_gateway_resource.visit.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_visit" {
  rest_api_id             = aws_api_gateway_rest_api.visit.id
  resource_id             = aws_api_gateway_resource.visit.id
  http_method             = aws_api_gateway_method.get_visit.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:dynamodb:action/UpdateItem"
  credentials             = aws_iam_role.apigw_dynamo.arn

  request_templates = {
    "application/json" = jsonencode({
      TableName                 = var.table_name
      Key                       = { metric = { S = "visits" } }
      UpdateExpression          = "SET amount = amount + :num"
      ExpressionAttributeValues = { ":num" = { N = "1" } }
      ReturnValues              = "NONE"
    })
  }
}

resource "aws_api_gateway_method_response" "get_visit_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.visit.id
  http_method = aws_api_gateway_method.get_visit.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "get_visit_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.visit.id
  http_method = aws_api_gateway_method.get_visit.http_method
  status_code = aws_api_gateway_method_response.get_visit_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin}'"
  }

  depends_on = [aws_api_gateway_integration.get_visit]
}

# ----- OPTIONS /visit (CORS preflight) -----

resource "aws_api_gateway_method" "options_visit" {
  rest_api_id   = aws_api_gateway_rest_api.visit.id
  resource_id   = aws_api_gateway_resource.visit.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_visit" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.visit.id
  http_method = aws_api_gateway_method.options_visit.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options_visit_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.visit.id
  http_method = aws_api_gateway_method.options_visit.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_visit_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.visit.id
  http_method = aws_api_gateway_method.options_visit.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.allowed_origin}'"
  }

  depends_on = [aws_api_gateway_integration.options_visit]
}

# =====================================================================
# /count – GET current visit count (DynamoDB GetItem)
# =====================================================================

resource "aws_api_gateway_resource" "count" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  parent_id   = aws_api_gateway_rest_api.visit.root_resource_id
  path_part   = "count"
}

# ----- GET /count -----

resource "aws_api_gateway_method" "get_count" {
  rest_api_id   = aws_api_gateway_rest_api.visit.id
  resource_id   = aws_api_gateway_resource.count.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_count" {
  rest_api_id             = aws_api_gateway_rest_api.visit.id
  resource_id             = aws_api_gateway_resource.count.id
  http_method             = aws_api_gateway_method.get_count.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:dynamodb:action/GetItem"
  credentials             = aws_iam_role.apigw_dynamo.arn

  request_templates = {
    "application/json" = jsonencode({
      TableName            = var.table_name
      Key                  = { metric = { S = "visits" } }
      ProjectionExpression = "amount"
    })
  }
}

resource "aws_api_gateway_method_response" "get_count_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.count.id
  http_method = aws_api_gateway_method.get_count.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "get_count_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.count.id
  http_method = aws_api_gateway_method.get_count.http_method
  status_code = aws_api_gateway_method_response.get_count_200.status_code

  response_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
$inputRoot.Item.amount.N
EOF
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin}'"
  }

  depends_on = [aws_api_gateway_integration.get_count]
}

# ----- OPTIONS /count (CORS preflight) -----

resource "aws_api_gateway_method" "options_count" {
  rest_api_id   = aws_api_gateway_rest_api.visit.id
  resource_id   = aws_api_gateway_resource.count.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_count" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.count.id
  http_method = aws_api_gateway_method.options_count.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options_count_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.count.id
  http_method = aws_api_gateway_method.options_count.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_count_200" {
  rest_api_id = aws_api_gateway_rest_api.visit.id
  resource_id = aws_api_gateway_resource.count.id
  http_method = aws_api_gateway_method.options_count.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.allowed_origin}'"
  }

  depends_on = [aws_api_gateway_integration.options_count]
}

# ---------- Deployment & Stage ----------

resource "aws_api_gateway_deployment" "visit" {
  rest_api_id = aws_api_gateway_rest_api.visit.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.visit,
      aws_api_gateway_method.get_visit,
      aws_api_gateway_integration.get_visit,
      aws_api_gateway_method.options_visit,
      aws_api_gateway_integration.options_visit,
      aws_api_gateway_resource.count,
      aws_api_gateway_method.get_count,
      aws_api_gateway_integration.get_count,
      aws_api_gateway_method.options_count,
      aws_api_gateway_integration.options_count,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.get_visit,
    aws_api_gateway_integration.options_visit,
    aws_api_gateway_integration.get_count,
    aws_api_gateway_integration.options_count,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.visit.id
  deployment_id = aws_api_gateway_deployment.visit.id
  stage_name    = "prod"
}

# ---------- Outputs ----------

output "invoke_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/visit"
}

output "count_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/count"
}
