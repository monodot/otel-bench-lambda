data "aws_caller_identity" "current" {}

data "external" "whoami" {
  program = ["bash", "-c", "printf '{\"user\":\"%s\"}' \"$(whoami)\""]
}

# ── Shared locals ─────────────────────────────────────────────────────────────

locals {
  # ── Language configurations ──────────────────────────────────────────────────
  # Each entry defines the runtime, handler, and pre-built artifact path for a
  # supported language. Build the artifact before running `terraform apply`.
  language_configs = {
    java = {
      runtime       = "java21"
      handler       = "com.example.AuthzHandler"
      artifact_path = "${path.module}/../functions/java/target/authz-function-1.0-SNAPSHOT.jar"
    }
    python = {
      runtime       = "python3.13"
      handler       = "lambda_function.lambda_handler"
      artifact_path = "${path.module}/../functions/python/dist/function.zip"
    }
  }

  java_lang   = local.language_configs.java
  python_lang = local.language_configs.python

  # Only evaluate the file hash when the language is being deployed, so
  # Terraform does not fail if the artifact has not been built yet.
  java_source_hash   = var.deploy_java   ? filebase64sha256(local.java_lang.artifact_path)   : ""
  python_source_hash = var.deploy_python ? filebase64sha256(local.python_lang.artifact_path) : ""

  otlp_auth_string     = base64encode("${var.otlp_username}:${var.otlp_password}")
  grafana_otlp_headers = "Authorization=Basic ${local.otlp_auth_string}"

  collector_config_layer_arn = aws_lambda_layer_version.collector_config.arn

  # Owner is resolved at apply time from the local OS user running Terraform.
  # Merges with provider default_tags so all resources carry Project + Owner.
  common_tags = { Owner = data.external.whoami.result.user }
}
