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

# Allow the role to access all OTel layer ARNs that are configured.
resource "aws_iam_role_policy" "lambda_layers" {
  name = "${var.name_prefix}-layer-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:GetLayerVersion"]
      Resource = [for arn in [
        var.java_agent_layer_arn,
        var.java_wrapper_layer_arn,
        var.python_agent_layer_arn,
        var.collector_layer_arn,
        var.lambda_insights_layer_arn,
      ] : arn if arn != null]
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
  layer_name               = "${var.name_prefix}-otel-collector-config"
  filename                 = data.archive_file.collector_config_layer.output_path
  source_code_hash         = data.archive_file.collector_config_layer.output_base64sha256
  compatible_runtimes      = ["java21", "python3.13"]
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
#   source_code_hash          = local.{java,python}_source_hash
#   lambda_insights_layer_arn = var.lambda_insights_layer_arn
#
# Collector-layer variants also share:
#   collector_layer_arn        = var.collector_layer_arn
#   collector_config_layer_arn = local.collector_config_layer_arn
#   otlp_endpoint              = var.otlp_endpoint
#   otlp_auth_string           = local.otlp_auth_string
#   otel_traces_exporter       = "otlp"
#   otel_metrics_exporter      = "otlp"
#   otel_logs_exporter         = "otlp"

# ════════════════════════════════════════════════════════════════════════════════
# JAVA CONFIGS  (c01–c15)  — gated on var.deploy_java
# ════════════════════════════════════════════════════════════════════════════════

# ── Config 1: True baseline ───────────────────────────────────────────────────

module "config_1_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix               = "${var.name_prefix}-c01-baseline-java"
  runtime                   = local.java_lang.runtime
  handler                   = local.java_lang.handler
  artifact_path             = local.java_lang.artifact_path
  source_code_hash          = local.java_source_hash
  execution_role_arn        = aws_iam_role.lambda.arn
  lambda_insights_layer_arn = var.lambda_insights_layer_arn

  tags = local.common_tags
}

# ── Config 2: OTel SDK loaded, all exporters disabled ────────────────────────

module "config_2_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix               = "${var.name_prefix}-c02-sdk-java"
  runtime                   = local.java_lang.runtime
  handler                   = local.java_lang.handler
  artifact_path             = local.java_lang.artifact_path
  source_code_hash          = local.java_source_hash
  execution_role_arn        = aws_iam_role.lambda.arn
  lambda_insights_layer_arn = var.lambda_insights_layer_arn
  agent_layer_arn           = var.java_agent_layer_arn
  otel_traces_exporter      = "none"
  otel_metrics_exporter     = "none"
  otel_logs_exporter        = "none"

  tags = local.common_tags
}

# ── Config 3: Direct export to external OTLP endpoint ────────────────────────

module "config_3_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c03-direct-java"
  runtime                     = local.java_lang.runtime
  handler                     = local.java_lang.handler
  artifact_path               = local.java_lang.artifact_path
  source_code_hash            = local.java_source_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  agent_layer_arn             = var.java_agent_layer_arn
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = var.otlp_endpoint
  otel_exporter_otlp_headers  = local.grafana_otlp_headers

  tags = local.common_tags
}

# ── Config 4: Collector Lambda Layer (full signals) ───────────────────────────

module "config_4_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c04-col-layer-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
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

module "config_5_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c05-ext-col-java"
  runtime                     = local.java_lang.runtime
  handler                     = local.java_lang.handler
  artifact_path               = local.java_lang.artifact_path
  source_code_hash            = local.java_source_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  agent_layer_arn             = var.java_agent_layer_arn
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = "http://${aws_lb.ecs_collector.dns_name}:4318"
  vpc_subnet_ids              = aws_subnet.private[*].id
  vpc_security_group_ids      = [aws_security_group.config_5_lambda.id]

  tags = local.common_tags
}

# ── Config 6: Collector Layer — metrics only ──────────────────────────────────

module "config_6_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c06-metrics-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "none"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "none"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# ── Config 7: Collector Layer — traces only ───────────────────────────────────

module "config_7_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c07-traces-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "none"
  otel_logs_exporter         = "none"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# ── Config 8: Collector Layer — 128 MB ────────────────────────────────────────

module "config_8_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c08-128mb-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
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

# ── Config 9: Collector Layer — 1024 MB ───────────────────────────────────────

module "config_9_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c09-1024mb-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
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

# ── Config 10: Collector Layer + SnapStart ────────────────────────────────────

module "config_10_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c10-snapstart-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
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

# ── Config 11: Direct export + SnapStart ──────────────────────────────────────

module "config_11_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c11-direct-snap-java"
  runtime                     = local.java_lang.runtime
  handler                     = local.java_lang.handler
  artifact_path               = local.java_lang.artifact_path
  source_code_hash            = local.java_source_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  agent_layer_arn             = var.java_agent_layer_arn
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = var.otlp_endpoint
  otel_exporter_otlp_headers  = local.grafana_otlp_headers
  snapstart_enabled           = true

  tags = local.common_tags
}

# ── Config 12: Collector Layer + fast startup ─────────────────────────────────
# May improve startup times at the cost of overall performance

module "config_12_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c12-fast-startup-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
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

# ── Config 13: Java Wrapper layer (vs Java Agent in c04) ──────────────────────

module "config_13_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c13-java-wrapper-java"
  runtime                    = local.java_lang.runtime
  # The wrapper layer's TracingRequestWrapper requires explicit ClassName::methodName format.
  # The agent layer accepts the bare class name; the wrapper does not.
  handler                    = "com.example.AuthzHandler::handleRequest"
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  wrapper_layer_arn          = var.java_wrapper_layer_arn
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "otlp"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# ── Config 14: Fast startup + SnapStart ───────────────────────────────────────

module "config_14_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c14-fast-snap-java"
  runtime                    = local.java_lang.runtime
  handler                    = local.java_lang.handler
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.java_agent_layer_arn
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

# ── Config 15: Java Wrapper + SnapStart ───────────────────────────────────────

module "config_15_java" {
  count  = var.deploy_java ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c15-wrapper-snap-java"
  runtime                    = local.java_lang.runtime
  handler                    = "com.example.AuthzHandler::handleRequest"
  artifact_path              = local.java_lang.artifact_path
  source_code_hash           = local.java_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  wrapper_layer_arn          = var.java_wrapper_layer_arn
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


# ════════════════════════════════════════════════════════════════════════════════
# PYTHON CONFIGS  (c01–c09)  — gated on var.deploy_python
# ════════════════════════════════════════════════════════════════════════════════

# ── Config 1: True baseline ───────────────────────────────────────────────────

module "config_1_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix               = "${var.name_prefix}-c01-baseline-python"
  runtime                   = local.python_lang.runtime
  handler                   = local.python_lang.handler
  artifact_path             = local.python_lang.artifact_path
  source_code_hash          = local.python_source_hash
  execution_role_arn        = aws_iam_role.lambda.arn
  lambda_insights_layer_arn = var.lambda_insights_layer_arn

  tags = local.common_tags
}

# ── Config 2: OTel SDK loaded, all exporters disabled ────────────────────────

module "config_2_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix               = "${var.name_prefix}-c02-sdk-python"
  runtime                   = local.python_lang.runtime
  handler                   = local.python_lang.handler
  artifact_path             = local.python_lang.artifact_path
  source_code_hash          = local.python_source_hash
  execution_role_arn        = aws_iam_role.lambda.arn
  lambda_insights_layer_arn = var.lambda_insights_layer_arn
  agent_layer_arn           = var.python_agent_layer_arn
  agent_exec_wrapper        = "/opt/otel-instrument"
  otel_traces_exporter      = "none"
  otel_metrics_exporter     = "none"
  otel_logs_exporter        = "none"

  tags = local.common_tags
}

# ── Config 3: Direct export to external OTLP endpoint ────────────────────────

module "config_3_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c03-direct-python"
  runtime                     = local.python_lang.runtime
  handler                     = local.python_lang.handler
  artifact_path               = local.python_lang.artifact_path
  source_code_hash            = local.python_source_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  agent_layer_arn             = var.python_agent_layer_arn
  agent_exec_wrapper          = "/opt/otel-instrument"
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = var.otlp_endpoint
  otel_exporter_otlp_headers  = local.grafana_otlp_headers

  tags = local.common_tags
}

# ── Config 4: Collector Lambda Layer (full signals) ───────────────────────────

module "config_4_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c04-col-layer-python"
  runtime                    = local.python_lang.runtime
  handler                    = local.python_lang.handler
  artifact_path              = local.python_lang.artifact_path
  source_code_hash           = local.python_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.python_agent_layer_arn
  agent_exec_wrapper         = "/opt/otel-instrument"
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

module "config_5_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                 = "${var.name_prefix}-c05-ext-col-python"
  runtime                     = local.python_lang.runtime
  handler                     = local.python_lang.handler
  artifact_path               = local.python_lang.artifact_path
  source_code_hash            = local.python_source_hash
  execution_role_arn          = aws_iam_role.lambda.arn
  lambda_insights_layer_arn   = var.lambda_insights_layer_arn
  agent_layer_arn             = var.python_agent_layer_arn
  agent_exec_wrapper          = "/opt/otel-instrument"
  otel_traces_exporter        = "otlp"
  otel_metrics_exporter       = "otlp"
  otel_logs_exporter          = "otlp"
  otel_exporter_otlp_endpoint = "http://${aws_lb.ecs_collector.dns_name}:4318"
  vpc_subnet_ids              = aws_subnet.private[*].id
  vpc_security_group_ids      = [aws_security_group.config_5_lambda.id]

  tags = local.common_tags
}

# ── Config 6: Collector Layer — metrics only ──────────────────────────────────

module "config_6_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c06-metrics-python"
  runtime                    = local.python_lang.runtime
  handler                    = local.python_lang.handler
  artifact_path              = local.python_lang.artifact_path
  source_code_hash           = local.python_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.python_agent_layer_arn
  agent_exec_wrapper         = "/opt/otel-instrument"
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "none"
  otel_metrics_exporter      = "otlp"
  otel_logs_exporter         = "none"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# ── Config 7: Collector Layer — traces only ───────────────────────────────────

module "config_7_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c07-traces-python"
  runtime                    = local.python_lang.runtime
  handler                    = local.python_lang.handler
  artifact_path              = local.python_lang.artifact_path
  source_code_hash           = local.python_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.python_agent_layer_arn
  agent_exec_wrapper         = "/opt/otel-instrument"
  collector_layer_arn        = var.collector_layer_arn
  collector_config_layer_arn = local.collector_config_layer_arn
  otel_traces_exporter       = "otlp"
  otel_metrics_exporter      = "none"
  otel_logs_exporter         = "none"
  otlp_endpoint              = var.otlp_endpoint
  otlp_auth_string           = local.otlp_auth_string

  tags = local.common_tags
}

# ── Config 8: Collector Layer — 128 MB ────────────────────────────────────────

module "config_8_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c08-128mb-python"
  runtime                    = local.python_lang.runtime
  handler                    = local.python_lang.handler
  artifact_path              = local.python_lang.artifact_path
  source_code_hash           = local.python_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.python_agent_layer_arn
  agent_exec_wrapper         = "/opt/otel-instrument"
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

# ── Config 9: Collector Layer — 1024 MB ───────────────────────────────────────

module "config_9_python" {
  count  = var.deploy_python ? 1 : 0
  source = "./modules/lambda-demo-variant"

  name_prefix                = "${var.name_prefix}-c09-1024mb-python"
  runtime                    = local.python_lang.runtime
  handler                    = local.python_lang.handler
  artifact_path              = local.python_lang.artifact_path
  source_code_hash           = local.python_source_hash
  execution_role_arn         = aws_iam_role.lambda.arn
  lambda_insights_layer_arn  = var.lambda_insights_layer_arn
  agent_layer_arn            = var.python_agent_layer_arn
  agent_exec_wrapper         = "/opt/otel-instrument"
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
