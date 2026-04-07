output "name_prefix" {
  description = "Name prefix applied to all resources. Pass as NAME_PREFIX to k6 to correlate config tags with Lambda function/service names."
  value       = var.name_prefix
}

# ── Java outputs (c01–c15) ────────────────────────────────────────────────────

output "config_01_java_url" { value = var.deploy_java ? module.config_1_java[0].function_url  : "" }
output "config_02_java_url" { value = var.deploy_java ? module.config_2_java[0].function_url  : "" }
output "config_03_java_url" { value = var.deploy_java ? module.config_3_java[0].function_url  : "" }
output "config_04_java_url" { value = var.deploy_java ? module.config_4_java[0].function_url  : "" }
output "config_05_java_url" { value = var.deploy_java ? module.config_5_java[0].function_url  : "" }
output "config_06_java_url" { value = var.deploy_java ? module.config_6_java[0].function_url  : "" }
output "config_07_java_url" { value = var.deploy_java ? module.config_7_java[0].function_url  : "" }
output "config_08_java_url" { value = var.deploy_java ? module.config_8_java[0].function_url  : "" }
output "config_09_java_url" { value = var.deploy_java ? module.config_9_java[0].function_url  : "" }
output "config_10_java_url" { value = var.deploy_java ? module.config_10_java[0].function_url : "" }
output "config_11_java_url" { value = var.deploy_java ? module.config_11_java[0].function_url : "" }
output "config_12_java_url" { value = var.deploy_java ? module.config_12_java[0].function_url : "" }
output "config_13_java_url" { value = var.deploy_java ? module.config_13_java[0].function_url : "" }
output "config_14_java_url" { value = var.deploy_java ? module.config_14_java[0].function_url : "" }
output "config_15_java_url" { value = var.deploy_java ? module.config_15_java[0].function_url : "" }
output "config_16_java_url" { value = var.deploy_java ? module.config_16_java[0].function_url : "" }
output "config_17_java_url" { value = var.deploy_java ? module.config_17_java[0].function_url : "" }
output "config_18_java_url" { value = var.deploy_java && var.adot_java_wrapper_layer_arn != null ? module.config_18_java[0].function_url : "" }
output "config_19_java_url" { value = var.deploy_java ? module.config_19_java[0].function_url : "" }

# ── Python outputs (c01–c09) ──────────────────────────────────────────────────

output "config_01_python_url" { value = var.deploy_python ? module.config_1_python[0].function_url : "" }
output "config_02_python_url" { value = var.deploy_python ? module.config_2_python[0].function_url : "" }
output "config_03_python_url" { value = var.deploy_python ? module.config_3_python[0].function_url : "" }
output "config_04_python_url" { value = var.deploy_python ? module.config_4_python[0].function_url : "" }
output "config_05_python_url" { value = var.deploy_python ? module.config_5_python[0].function_url : "" }
output "config_06_python_url" { value = var.deploy_python ? module.config_6_python[0].function_url : "" }
output "config_07_python_url" { value = var.deploy_python ? module.config_7_python[0].function_url : "" }
output "config_08_python_url" { value = var.deploy_python ? module.config_8_python[0].function_url : "" }
output "config_09_python_url" { value = var.deploy_python ? module.config_9_python[0].function_url : "" }

output "ecs_collector_endpoint" {
  description = "NLB DNS name for the external OTel Collector (config 5)"
  value       = aws_lb.ecs_collector.dns_name
}
