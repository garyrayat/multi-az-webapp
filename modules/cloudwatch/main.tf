# =============================================================================
# CLOUDWATCH MODULE — Observability layer
# Log groups: stores EC2 app logs with retention policy
# Alarms: CPU spike, unhealthy ALB targets, RDS CPU — all fire SNS email
# Dashboard: single pane of glass in AWS console
# =============================================================================

# -----------------------------------------------------------------------------
# SNS Topic for operational alarms (separate from budget alerts)
# Budget alerts = finance concern. Alarms = ops concern. Keep them separate.
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-${var.environment}-alarms"
}

resource "aws_sns_topic_subscription" "alarm_emails" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# -----------------------------------------------------------------------------
# Log Groups — stores logs from EC2 instances via CloudWatch Agent
# CloudWatch Agent (installed via user_data) ships logs to these groups
# retention_in_days prevents unbounded log storage costs
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/${var.environment}/app"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-app-logs"
  }
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/${var.project_name}/${var.environment}/nginx"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-nginx-logs"
  }
}

# -----------------------------------------------------------------------------
# ALARM 1 — EC2 ASG CPU High
# Fires when average CPU across all ASG instances > 80% for 10 minutes
# Indicates app is overloaded — scale up or investigate
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  count = var.lab_running ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2        # Must breach 2 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300      # 5 minute windows
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ASG CPU > 80% for 10 minutes — investigate or scale"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]  # Also notify when recovered

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cpu-alarm"
  }
}

# -----------------------------------------------------------------------------
# ALARM 2 — ALB Unhealthy Hosts
# Fires the instant any target fails its health check
# Most critical alarm — means your app is down for real users
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.lab_running && var.alb_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1        # Fire immediately — don't wait
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0        # Any unhealthy host = alarm
  alarm_description   = "ALB has unhealthy targets — app may be down"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-unhealthy-hosts-alarm"
  }
}

# -----------------------------------------------------------------------------
# ALARM 3 — RDS CPU High
# Fires when DB CPU > 80% — indicates slow queries or missing indexes
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.lab_running && var.db_instance_id != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU > 80% — check for slow queries or missing indexes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-cpu-alarm"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Dashboard — single pane of glass
# Shows EC2 CPU, ALB traffic, healthy host count, RDS metrics side by side
# Access: AWS Console → CloudWatch → Dashboards
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  count = var.lab_running ? 1 : 0

  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 ASG CPU Utilization"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]]
          period = 300
          stat   = "Average"
          region = var.aws_region
          view   = "timeSeries"
          annotations = {
            horizontal = [{ value = 80, label = "Alarm threshold", color = "#ff0000" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB Healthy vs Unhealthy Hosts"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix]
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU Utilization"
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id]]
          period = 300
          stat   = "Average"
          region = var.aws_region
          view   = "timeSeries"
        }
      }
    ]
  })
}
