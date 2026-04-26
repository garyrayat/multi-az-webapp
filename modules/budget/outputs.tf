output "sns_topic_arn" {
  description = "SNS topic ARN for budget alerts — can wire to other alerting systems"
  value       = aws_sns_topic.budget_alerts.arn
}

output "budget_name" {
  description = "Budget name — for reference in runbooks"
  value       = aws_budgets_budget.monthly.name
}
