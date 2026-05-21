# =============================================================================
# LAMBDA MODULE
# Deploys a Python Lambda function with:
#   - Function URL (public HTTPS endpoint — satisfies AWS credit activity)
#   - X-Ray active tracing (every invocation sampled and traced)
#   - CloudWatch log group with configurable retention
#
# Trace flow: function URL → Lambda → X-Ray service map
# =============================================================================

locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  function_name = "${local.name_prefix}-api"
}

# ─── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-lambda-role" }
}

# Basic execution — write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray — write traces and segments
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ─── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name_prefix}-lambda-logs" }
}

# ─── Function Package ──────────────────────────────────────────────────────────
# Zips handler.py on every plan — source_code_hash triggers redeploy only when
# file content actually changes (avoids unnecessary Lambda updates)
data "archive_file" "handler" {
  type        = "zip"
  output_path = "${path.module}/handler.zip"

  source {
    content  = file("${path.module}/src/handler.py")
    filename = "handler.py"
  }
}

# ─── Lambda Function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "api" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME = local.function_name
      LOG_LEVEL               = "INFO"
    }
  }

  # Active tracing: X-Ray samples every invocation and auto-traces
  # cold starts, invocation metadata, and any patched HTTP clients
  tracing_config {
    mode = "Active"
  }

  # Log group must exist before function so first invocation doesn't race
  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = { Name = local.function_name }
}

# ─── Function URL ──────────────────────────────────────────────────────────────
# Public HTTPS endpoint — no API Gateway needed.
# This is what satisfies the "Create a web app using AWS Lambda" credit activity.
resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE" # Public for lab — use AWS_IAM in prod

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["content-type", "x-amzn-trace-id"]
    max_age           = 300
  }
}

# ─── X-Ray Sampling Rule ───────────────────────────────────────────────────────
# Sample 100% of requests to this function in the lab so every invocation
# shows up in the X-Ray service map. Lower to 5% in production.
resource "aws_xray_sampling_rule" "lambda_api" {
  rule_name      = "${local.name_prefix}-lambda-api"
  priority       = 1000
  reservoir_size = 5     # Guaranteed traces per second regardless of rate
  fixed_rate     = 1.0   # 100% sampling — dial down to 0.05 for prod
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = local.function_name
  resource_arn   = "*"
  version        = 1
}
