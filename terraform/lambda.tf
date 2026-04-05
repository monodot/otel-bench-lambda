# ── IAM — shared Lambda execution role ───────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-exec"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_insights" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Allow the role to use the OTel layer ARNs.
resource "aws_iam_role_policy" "lambda_layers" {
  name = "${var.name_prefix}-layer-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:GetLayerVersion"]
      Resource = [
        "${var.java_agent_layer_arn}",
        "${var.collector_layer_arn}",
        "${var.lambda_insights_layer_arn}",
      ]
    }]
  })
}

# ── Collector config Lambda layer ─────────────────────────────────────────────
# Packages collector-config/lambda-layer.yaml into a layer at the path the ADOT
# collector extension expects: /opt/collector-config/config.yaml

data "archive_file" "collector_config_layer" {
  type        = "zip"
  output_path = "${path.module}/collector-config-layer.zip"

  source {
    content  = file("${path.module}/../collector-config/lambda-layer.yaml")
    filename = "collector-config/config.yaml"
  }
}

resource "aws_lambda_layer_version" "collector_config" {
  layer_name = "${var.name_prefix}-otel-collector-config"
  # tags                     = local.common_tags
  filename                 = data.archive_file.collector_config_layer.output_path
  source_code_hash         = data.archive_file.collector_config_layer.output_base64sha256
  compatible_runtimes      = ["java21"]
  compatible_architectures = ["x86_64"]
}

# ── VPC networking for config 5 ───────────────────────────────────────────────

resource "aws_security_group" "config_5_lambda" {
  name        = "${var.name_prefix}-c05-lambda"
  description = "config_5 Lambda - egress only; ingress from collector SG on 4317/4318"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


# ── Shared module arguments ───────────────────────────────────────────────────
# These are repeated per module call below; Terraform doesn't support passing
# a map of arguments to a module, so each call is explicit for clarity.
#
# Common args for every variant:
#   execution_role_arn        = aws_iam_role.lambda.arn
#   jar_path                  = local.jar_path
#   source_code_hash          = local.source_code_hash
#   lambda_insights_layer_arn = var.lambda_insights_layer_arn
#
# Collector-layer variants also share:
#   collector_layer_arn        = var.collector_layer_arn
#   collector_config_layer_arn = local.collector_config_layer_arn
#   otlp_endpoint = var.otlp_endpoint
#   otlp_auth_string           = local.otlp_auth_string
#   otel_traces_exporter       = "otlp"
#   otel_metrics_exporter      = "otlp"
#   otel_logs_exporter         = "otlp"

# ── Config 1: True baseline ───────────────────────────────────────────────────

module "config_1" {
  source = "./modules/lambda-demo-variant"

  name_prefix               = "${var.name_prefix}-c01-baseline"
  runtime                   = local.lang.runtime
  handler                   = local.lang.handler
  jar_path                  = local.jar_path
  source_code_hash          = local.source_code_hash
  execution_role_arn        = aws_iam_role.lambda.arn
  lambda_insights_layer_arn = var.lambda_insights_layer_arn

  tags = local.common_tags
}

# ── Config 2: OTel SDK loaded, all exporters disabled ────────────────────────

module "config_2" {
  source = "./modules/lambda-demo-variant"

  name_prefix               = "${var.name_prefix}-c02-sdk"
  runtime                   = local.lang.runtime
  handler                   = local.lang.handler
  jar_path                  = local.jar_path
  source_code_hash          = local.source_code_hash
  execution_role_arn        = aws_iam_role.lambda.arn
  lambda_insights_layer_arn = var.lambda_insights_layer_arn
  java_agent_layer_arn      = var.java_agent_layer_arn
  otel_traces_exporter      = "none"
  otel_metrics_exporter     = "none"
  otel_logs_exporter        = "none"

  tags = local.common_tags
}

# ── Config 3: Direct export to external OTLP endpoint ─────────────────────────────────

module "config_3" {
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c03-direct"
  runtime                     = local.lang.runtime
  handler                     = local.lang.handler
  jar_path                    = local.jar_path
  source_code_hash            = local.source_code_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  java_agent_layer_arn        = var.java_agent_layer_arn
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = var.otlp_endpoint
  otel_exporter_otlp_headers  = local.grafana_otlp_headers

  tags = local.common_tags
}

# ── Config 4: Collector Lambda Layer (full signals) ───────────────────────────

module "config_4" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c04-col-layer"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# ── Config 5: External ECS Fargate collector ──────────────────────────────────

module "config_5" {
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c05-ext-col"
  runtime                     = local.lang.runtime
  handler                     = local.lang.handler
  jar_path                    = local.jar_path
  source_code_hash            = local.source_code_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  java_agent_layer_arn        = var.java_agent_layer_arn
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = "http://${aws_lb.ecs_collector.dns_name}:4318"
  vpc_subnet_ids              = aws_subnet.private[*].id
  vpc_security_group_ids      = [aws_security_group.config_5_lambda.id]

  tags = local.common_tags
}

# # ── Config 6: Collector Layer — metrics only ──────────────────────────────────

module "config_6" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c06-metrics"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "none"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "none"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# # ── Config 7: Collector Layer — traces only ───────────────────────────────────

module "config_7" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c07-traces"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "none"
  otel_logs_exporter         = "none"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# # ── Config 8: Collector Layer — 128 MB ────────────────────────────────────────

module "config_8" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c08-128mb"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string
  memory_size                = 128

  tags = local.common_tags
}

# # ── Config 9: Collector Layer — 1024 MB ───────────────────────────────────────

module "config_9" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c09-1024mb"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string
  memory_size                = 1024

  tags = local.common_tags
}

# # ── Config 10: Collector Layer + SnapStart ────────────────────────────────────

module "config_10" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c10-snapstart"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string
  snapstart_enabled          = true

  tags = local.common_tags
}

# # ── Config 11: Direct export + SnapStart ──────────────────────────────────────

module "config_11" {
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c11-direct-snap"
  runtime                     = local.lang.runtime
  handler                     = local.lang.handler
  jar_path                    = local.jar_path
  source_code_hash            = local.source_code_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  java_agent_layer_arn        = var.java_agent_layer_arn
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = var.otlp_endpoint
  otel_exporter_otlp_headers  = local.grafana_otlp_headers
  snapstart_enabled           = true

  tags = local.common_tags
}


# # ── Config 12: Collector Layer + fast startup ─────────────────────────────────
# May improve startup times at the cost of overall performance

module "config_12" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c12-fast-startup"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string
  fast_startup_enabled       = true

  tags = local.common_tags
}

# # ── Config 13: Java Wrapper layer (vs Java Agent in c04) ──────────────────────

module "config_13" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c13-java-wrapper"
  runtime                    = local.lang.runtime
  # The wrapper layer's TracingRequestWrapper requires explicit ClassName::methodName format.
  # The agent layer accepts the bare class name; the wrapper does not.
  handler                    = "com.example.AuthzHandler::handleRequest"
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_wrapper_layer_arn     = var.java_wrapper_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# # ── Config 14: Fast startup + SnapStart ───────────────────────────────────────

module "config_14" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c14-fast-snap"
  runtime                    = local.lang.runtime
  handler                    = local.lang.handler
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_agent_layer_arn       = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string
  fast_startup_enabled       = true
  snapstart_enabled          = true

  tags = local.common_tags
}

# # ── Config 15: Java Wrapper + SnapStart ───────────────────────────────────────

module "config_15" {
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c15-wrapper-snap"
  runtime                    = local.lang.runtime
  handler                    = "com.example.AuthzHandler::handleRequest"
  jar_path                   = local.jar_path
  source_code_hash           = local.source_code_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  java_wrapper_layer_arn     = var.java_wrapper_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string
  snapstart_enabled          = true

  tags = local.common_tags
}

