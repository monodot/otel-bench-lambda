data "aws_caller_identity" "current" {}

data "external" "whoami" {
  program = ["bash", "-c", "printf '{\"user\":\"%s\"}' \"$(whoami)\""]
}

# ── Shared locals ─────────────────────────────────────────────────────────────

locals {
  # ── Language configurations ──────────────────────────────────────────────────
  # Each entry defines the runtime, handler, and pre-built artifact path for a
  # supported language. Build the artifact before running `terraform apply`.
  # Add new languages here and extend the `language` variable validation list.
  language_configs = {
    java = {
      runtime       = "java21"
      handler       = "com.example.AuthzHandler"
      artifact_path = "${path.module}/../functions/java/target/authz-function-1.0-SNAPSHOT.jar"
    }
    # nodejs = {
    #   runtime       = "nodejs20.x"
    #   handler       = "index.handler"
    #   artifact_path = "${path.module}/../functions/nodejs/dist/function.zip"
    # }
  }

  lang = local.language_configs[var.language]

  # Kept as convenience aliases so the 11 module calls below stay readable.
  jar_path         = local.lang.artifact_path
  source_code_hash = filebase64sha256(local.lang.artifact_path)

  otlp_auth_string     = base64encode("${var.otlp_username}:${var.otlp_password}")
  grafana_otlp_headers = "Authorization=Basic ${local.otlp_auth_string}"

  collector_config_layer_arn = aws_lambda_layer_version.collector_config.arn

  # Owner is resolved at apply time from the local OS user running Terraform.
  # Merges with provider default_tags so all resources carry Project + Owner.
  common_tags = { Owner = data.external.whoami.result.user }
}

