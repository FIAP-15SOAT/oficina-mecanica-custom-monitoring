output "dashboard_overview_url" {
  description = "Endereço do dashboard Visão Geral."
  value       = local.dashboard_url_overview
}

output "dashboard_service_urls" {
  description = "Endereço do dashboard de cada serviço, por contexto."
  value       = local.dashboard_url_service
}

output "dashboard_work_orders_url" {
  description = "Endereço do dashboard de Ordens de Serviço."
  value       = local.dashboard_url_work_orders
}

output "dashboard_kubernetes_url" {
  description = "Endereço do dashboard de Kubernetes."
  value       = local.dashboard_url_kubernetes
}

output "dashboard_sagas_url" {
  description = "Endereço do dashboard de Sagas."
  value       = local.dashboard_url_sagas
}

output "dashboard_payments_url" {
  description = "Endereço do dashboard de Pagamentos."
  value       = local.dashboard_url_payments
}

output "dashboard_messaging_url" {
  description = "Endereço do dashboard de Mensageria."
  value       = local.dashboard_url_messaging
}

output "monitor_ids" {
  description = "Identificadores dos monitores: mapas por serviço ou por Lambda e os monitores únicos."
  value = {
    disponibilidade_externa = { for k, t in datadog_synthetics_test.service_health : k => t.monitor_id }
    servico_5xx             = { for k, m in datadog_monitor.service_5xx : k => m.id }
    servico_latencia_p95    = { for k, m in datadog_monitor.service_latency_p95 : k => m.id }
    pod_memoria             = { for k, m in datadog_monitor.pod_memory : k => m.id }
    pod_reinicios           = { for k, m in datadog_monitor.pod_restarts : k => m.id }
    health_check_degradado  = { for k, m in datadog_monitor.health_degraded : k => m.id }
    lambda_erros            = { for k, m in datadog_monitor.lambda_errors : k => m.id }
    ordens_de_servico       = datadog_monitor.work_order_failures.id
    email_falha_envio       = datadog_monitor.mail_send_failed.id
  }
}

output "synthetic_test_ids" {
  description = "Identificador público do teste sintético da rota de saúde de cada serviço."
  value       = { for k, t in datadog_synthetics_test.service_health : k => t.id }
}

output "synthetic_test_statuses" {
  description = "Estado de cada teste sintético: `live` com o laboratório no ar, `paused` fora dele."
  value       = { for k, t in datadog_synthetics_test.service_health : k => t.status }
}
