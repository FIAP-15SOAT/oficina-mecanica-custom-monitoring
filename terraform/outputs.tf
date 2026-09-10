output "dashboard_overview_url" {
  description = "Endereço do dashboard Visão Geral."
  value       = datadog_dashboard.overview.url
}

output "dashboard_api_url" {
  description = "Endereço do dashboard de API."
  value       = datadog_dashboard.api.url
}

output "dashboard_work_orders_url" {
  description = "Endereço do dashboard de Ordens de Serviço."
  value       = datadog_dashboard.work_orders.url
}

output "dashboard_kubernetes_url" {
  description = "Endereço do dashboard de Kubernetes."
  value       = datadog_dashboard.kubernetes.url
}

output "monitor_ids" {
  description = "Identificadores dos nove monitores."
  value = {
    disponibilidade_externa = datadog_synthetics_test.api_health.monitor_id
    api_5xx                 = datadog_monitor.api_5xx.id
    api_latencia_p95        = datadog_monitor.api_latency_p95.id
    ordens_de_servico       = datadog_monitor.work_order_failures.id
    pod_memoria             = datadog_monitor.pod_memory.id
    pod_reinicios           = datadog_monitor.pod_restarts.id
    lambda_erros            = datadog_monitor.lambda_errors.id
    email_falha_envio       = datadog_monitor.mail_send_failed.id
    dependencia_degradada   = datadog_monitor.dependency_degraded.id
  }
}

output "synthetic_test_id" {
  description = "Identificador publico do teste sintetico da rota de saude."
  value       = datadog_synthetics_test.api_health.id
}

output "synthetic_test_status" {
  description = "Estado do teste sintetico: `live` com o laboratorio no ar, `paused` fora dele."
  value       = datadog_synthetics_test.api_health.status
}
