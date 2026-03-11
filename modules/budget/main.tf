# =============================================================================
# AWS BUDGETS MODULE — Cost guardrail for lab/dev accounts
# Creates a monthly cost budget with SNS email alerts at threshold amounts.
# AWS Budgets evaluates actual spend (not forecasted) against thresholds.
# =============================================================================

# -----------------------------------------------------------------------------
# SNS Topic — the notification bus for budget alerts
# Budget service publishes to this topic when thresholds are breached.
# Email subscriptions require manual confirmation click from inbox.
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "budget_alerts" {
  name = "${var.project_name}-${var.environment}-budget-alerts"
}

# Budget service must have permission to publish to our SNS topic.
# Without this policy, alerts are silently dropped.
resource "aws_sns_topic_policy" "budget_alerts" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAWSBudgetsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.budget_alerts.arn
      }
    ]
  })
}

# Email subscriptions — each email gets a confirmation link from AWS.
# Alerts don't fire until the email is confirmed.
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# -----------------------------------------------------------------------------
# AWS Monthly Budget
# AWS evaluates spend against limit at the start of each calendar month.
# ACTUAL threshold = alert when real charges cross amount (not forecast).
# ABSOLUTE_VALUE threshold type = dollar amount (not percentage).
# -----------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # ⚠️ WARNING alert at 50% of budget — time to investigate
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.warning_threshold
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  # 🚨 CRITICAL alert at 80% of budget — time to destroy lab resources
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.critical_threshold
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}
