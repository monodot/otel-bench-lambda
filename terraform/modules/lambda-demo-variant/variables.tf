variable "name_prefix" {
  description = "Unique name for this Lambda variant. Used as the function name and resource prefix."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime identifier, e.g. java21, python3.13"
  type        = string
  default     = "java21"
}

variable "handler" {
  description = "Lambda handler entry point, e.g. com.example.AuthzHandler or lambda_function.lambda_handler"
  type        = string
  default     = "com.example.AuthzHandler"
}

variable "artifact_path" {
  description = "Local path to the built deployment artifact (JAR or ZIP). Must exist before running terraform apply."
  type        = string
}

variable "source_code_hash" {
  description = "Hash of the built artifact, used to trigger redeployment. Pass filebase64sha256(artifact_path) from the root module."
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for the Lambda execution role"
  type        = string
}

variable "memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "snapstart_enabled" {
  description = "Enable SnapStart. Requires java21 runtime. Creates a published version and a 'live' alias."
  type        = bool
  default     = false
}

# ── Layers ────────────────────────────────────────────────────────────────────

variable "agent_layer_arn" {
  description = "ARN of the OTel agent layer (Java agent or Python ADOT layer). Null = no instrumentation."
  type        = string
  default     = null
}

variable "wrapper_layer_arn" {
  description = "ARN of the OTel wrapper layer (Java only). Alternative to agent_layer_arn — set one or the other, not both."
  type        = string
  default     = null
}

variable "collector_layer_arn" {
  description = "ARN of the OTel Collector Lambda layer. Null = no sidecar collector."
  type        = string
  default     = null
}

variable "collector_config_layer_arn" {
  description = "ARN of the layer containing /opt/collector-config/config.yaml. Required when collector_layer_arn is set."
  type        = string
  default     = null
}

variable "lambda_insights_layer_arn" {
  description = "ARN of the CloudWatch Lambda Insights extension layer"
  type        = string
}

# ── Agent exec wrapper ────────────────────────────────────────────────────────
# The path injected into AWS_LAMBDA_EXEC_WRAPPER differs by language:
#   Java agent:   /opt/otel-handler
#   Python ADOT:  /opt/otel-instrument

variable "agent_exec_wrapper" {
  description = "AWS_LAMBDA_EXEC_WRAPPER path provided by the OTel agent layer. Java: /opt/otel-handler, Python: /opt/otel-instrument."
  type        = string
  default     = "/opt/otel-handler"
}

# ── Export routing ────────────────────────────────────────────────────────────
#
# Exactly one export mode should be active per variant:
#   A) collector_layer_arn set   → agent sends to localhost:4318; collector forwards
#   B) otel_exporter_otlp_endpoint set → agent sends directly to that endpoint
#   C) neither                   → agent runs but drops all signals (SDK-overhead-only)

variable "otel_exporter_otlp_endpoint" {
  description = "Direct OTLP endpoint for the OTel agent (e.g. your observability platform or external collector URL). Ignored when collector_layer_arn is set."
  type        = string
  default     = ""
}

variable "otel_exporter_otlp_headers" {
  description = "OTLP request headers for direct export, e.g. 'Authorization=Basic xxx'. Ignored when collector_layer_arn is set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "otel_traces_exporter" {
  description = "'otlp' or 'none'. Controls whether the OTel agent exports traces."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["otlp", "none"], var.otel_traces_exporter)
    error_message = "Must be 'otlp' or 'none'."
  }
}

variable "otel_metrics_exporter" {
  description = "'otlp' or 'none'. Controls whether the OTel agent exports metrics."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["otlp", "none"], var.otel_metrics_exporter)
    error_message = "Must be 'otlp' or 'none'."
  }
}

variable "otel_logs_exporter" {
  description = "'otlp' or 'none'. Controls whether the OTel agent exports logs."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["otlp", "none"], var.otel_logs_exporter)
    error_message = "Must be 'otlp' or 'none'."
  }
}

# Used only when collector_layer_arn is set — passed to the sidecar collector as env vars.
variable "otlp_endpoint" {
  description = "OTLP endpoint for the sidecar collector to forward to"
  type        = string
  default     = ""
}

variable "otlp_auth_string" {
  description = "base64(instanceId:token) for OTLP endpoint's basic auth, consumed by the sidecar collector"
  type        = string
  default     = ""
  sensitive   = true
}

variable "fast_startup_enabled" {
  description = "Set OTEL_JAVA_AGENT_FAST_STARTUP_ENABLED=true. Skips some SDK init work to reduce cold-start overhead at the cost of completeness. Java agent only."
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "Private subnet IDs to attach the Lambda to. Null = Lambda runs outside VPC."
  type        = list(string)
  default     = null
}

variable "vpc_security_group_ids" {
  description = "Security group IDs for the Lambda VPC config. Required when vpc_subnet_ids is set."
  type        = list(string)
  default     = null
}

variable "permissions_table_name" {
  description = "Name of the DynamoDB permissions table. Passed as PERMISSIONS_TABLE_NAME env var when non-empty."
  type        = string
  default     = ""
}

variable "extra_env_vars" {
  description = "Additional environment variables merged into the Lambda function's environment. Applied last, so these override any computed values."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
