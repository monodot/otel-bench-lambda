# ── Permissions table ─────────────────────────────────────────────────────────
# Stores per-subject role assignments for the mock auth service.
# The handler looks up the JWT subject claim on every request, which produces
# a DynamoDB child span visible in traces when OTel instrumentation is active.

resource "aws_dynamodb_table" "permissions" {
  name         = "${var.name_prefix}-permissions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "subject"

  attribute {
    name = "subject"
    type = "S"
  }

  tags = local.common_tags
}

# ── Sample data ───────────────────────────────────────────────────────────────
# bench-user matches the default JWT sub claim used by the k6 test payload.

resource "aws_dynamodb_table_item" "bench_user" {
  table_name = aws_dynamodb_table.permissions.name
  hash_key   = aws_dynamodb_table.permissions.hash_key
  item = <<ITEM
{
  "subject":   {"S": "bench-user"},
  "roles":     {"SS": ["read", "write"]},
  "is_active": {"BOOL": true}
}
ITEM
}

resource "aws_dynamodb_table_item" "admin_user" {
  table_name = aws_dynamodb_table.permissions.name
  hash_key   = aws_dynamodb_table.permissions.hash_key
  item = <<ITEM
{
  "subject":   {"S": "admin-user"},
  "roles":     {"SS": ["read", "write", "admin"]},
  "is_active": {"BOOL": true}
}
ITEM
}

resource "aws_dynamodb_table_item" "readonly_user" {
  table_name = aws_dynamodb_table.permissions.name
  hash_key   = aws_dynamodb_table.permissions.hash_key
  item = <<ITEM
{
  "subject":   {"S": "readonly-user"},
  "roles":     {"SS": ["read"]},
  "is_active": {"BOOL": true}
}
ITEM
}

resource "aws_dynamodb_table_item" "suspended_user" {
  table_name = aws_dynamodb_table.permissions.name
  hash_key   = aws_dynamodb_table.permissions.hash_key
  item = <<ITEM
{
  "subject":   {"S": "suspended-user"},
  "roles":     {"SS": ["read", "write"]},
  "is_active": {"BOOL": false}
}
ITEM
}

# ── IAM ───────────────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.name_prefix}-dynamodb-read"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.permissions.arn
    }]
  })
}
