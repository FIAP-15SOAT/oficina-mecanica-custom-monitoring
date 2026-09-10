resource "datadog_monitor" "work_order_failures" {
  name = "[Oficina Mecânica] Ordens de Serviço · Falhas no processamento"
  type = "query alert"

  query = "sum(last_10m):count:http.server.request.duration{${local.api_scope_and} AND http.response.status_code:5* AND ${local.work_order_routes}} by {http.route}.as_count() > ${var.work_order_5xx_critical_count}"

  monitor_thresholds {
    warning  = var.work_order_5xx_warning_count
    critical = var.work_order_5xx_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Falhas no fluxo de ordens de serviço"
    warning_symptom = "Falhas no fluxo de ordens de serviço subindo"
    group_suffix    = " — rota `{{http.route.name}}`"
    service         = var.api_service
    environment     = var.env
    unit            = "respostas 5xx em rotas de ordem de serviço ou orçamento"
    window          = "10 min"
    dashboard_url   = datadog_dashboard.work_orders.url
    logs_url        = local.logs_url_work_orders
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  tags = local.api_tags
}
