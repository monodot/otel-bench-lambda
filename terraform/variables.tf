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

variable "java_agent_layer_arn" {
  description = "ARN of the OTel Java agent Lambda layer (opentelemetry-javaagent-*)"
  type        = string
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
