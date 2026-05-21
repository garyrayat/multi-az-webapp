output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.api.arn
}

output "function_url" {
  description = "Public HTTPS function URL — open in browser to test"
  value       = aws_lambda_function_url.api.function_url
}

output "xray_sampling_rule" {
  description = "X-Ray sampling rule name"
  value       = aws_xray_sampling_rule.lambda_api.rule_name
}

output "log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}
