# ── IAM — Grafana Cloud CloudWatch data source ────────────────────────────────
# Optional: only created when create_grafana_iam_user = true.
# Needed if you want to use the included Grafana dashboard to visualise
# CloudWatch metrics alongside k6 test results.

resource "aws_iam_policy" "grafana_cloudwatch" {
  count = var.create_grafana_iam_user ? 1 : 0
  name  = "${var.name_prefix}-grafana-cloudwatch-read"
  tags  = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:DescribeAlarms",
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:GetQueryResults",
        "logs:GetLogEvents",
        "tag:GetResources",
        "ec2:DescribeRegions",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_user" "grafana_cloudwatch" {
  count = var.create_grafana_iam_user ? 1 : 0
  name  = "${var.name_prefix}-grafana-cloudwatch"
  tags  = local.common_tags
}

resource "aws_iam_user_policy_attachment" "grafana_cloudwatch" {
  count      = var.create_grafana_iam_user ? 1 : 0
  user       = aws_iam_user.grafana_cloudwatch[0].name
  policy_arn = aws_iam_policy.grafana_cloudwatch[0].arn
}

resource "aws_iam_access_key" "grafana_cloudwatch" {
  count = var.create_grafana_iam_user ? 1 : 0
  user  = aws_iam_user.grafana_cloudwatch[0].name
}

# ── Outputs ───────────────────────────────────────────────────────────────────
# Secret is marked sensitive; retrieve with: terraform output -raw grafana_cloudwatch_secret

output "grafana_cloudwatch_access_key_id" {
  value = var.create_grafana_iam_user ? aws_iam_access_key.grafana_cloudwatch[0].id : ""
}

output "grafana_cloudwatch_secret" {
  value     = var.create_grafana_iam_user ? aws_iam_access_key.grafana_cloudwatch[0].secret : ""
  sensitive = true
}
