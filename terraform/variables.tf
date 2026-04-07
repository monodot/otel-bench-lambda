variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "otel-bench"
}

variable "otlp_endpoint" {
  description = "External OTLP endpoint, e.g. https://otlp-gateway-prod-us-east-0.grafana.net/otlp"
  type        = string
}

variable "otlp_username" {
  description = "External OTLP username (used as the Basic-auth username)"
  type        = string
}

variable "otlp_password" {
  description = "External OTLP password with metrics+traces+logs write permissions"
  type        = string
  sensitive   = true
}

# ── Optional features ────────────────────────────────────────────────────────

variable "create_grafana_iam_user" {
  description = "Create an IAM user and access key for the Grafana Cloud CloudWatch data source. Only needed if you want to use the included Grafana dashboard."
  type        = bool
  default     = false
}

# ── Language deployment flags ─────────────────────────────────────────────────

variable "deploy_java" {
  description = "Deploy Java Lambda variants (c01–c15)"
  type        = bool
  default     = true
}

variable "deploy_python" {
  description = "Deploy Python Lambda variants (c01–c09)"
  type        = bool
  default     = false
}

# ── Lambda layer ARNs ─────────────────────────────────────────────────────────

variable "java_agent_layer_arn" {
  description = "ARN of the OTel Java agent Lambda layer (opentelemetry-javaagent-*). Required when deploy_java = true."
  type        = string
  default     = null
}

variable "java_wrapper_layer_arn" {
  description = "ARN of the OTel Java wrapper Lambda layer (opentelemetry-javawrapper-*). Required for c13/c15 Java wrapper configs."
  type        = string
  default     = null
}

variable "adot_java_wrapper_layer_arn" {
  description = "ARN of the AWS ADOT Java wrapper Lambda layer (aws-otel-java-wrapper-amd64-ver-*). Bundles the OTel wrapper and collector in a single layer. Required for c18."
  type        = string
  default     = null
}

variable "python_agent_layer_arn" {
  description = "ARN of the ADOT Python Lambda layer (aws-otel-python-amd64-ver-*). Required when deploy_python = true."
  type        = string
  default     = null
}

variable "collector_layer_arn" {
  description = "ARN of the OTel Collector Lambda layer (opentelemetry-collector-amd64-*)"
  type        = string
}

variable "lambda_insights_layer_arn" {
  description = "ARN of the CloudWatch Lambda Insights extension layer for the target region (x86_64)"
  type        = string
  default     = "arn:aws:lambda:us-east-1:580247275435:layer:LambdaInsightsExtension:53"
}
