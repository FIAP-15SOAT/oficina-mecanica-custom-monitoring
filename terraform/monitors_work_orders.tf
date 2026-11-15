locals {
  # Work orders are served by work-order; quotes moved to billing, which also
  # answers the quote routes nested under `/api/work-orders`.
  work_order_flow_scope    = "env:${var.env} AND http.response.status_code:5* AND ((service:${local.services["work-order"].service} AND http.route:/api/work-orders*) OR (service:${local.services["billing"].service} AND (http.route:/api/quotes* OR http.route:/api/work-orders*)))"
  logs_url_work_order_flow = "${var.datadog_app_url}logs?query=${urlencode("(service:${local.services["work-order"].service} OR service:${local.services["billing"].service}) env:${var.env} status:error")}"
}

resource "datadog_monitor" "work_order_failures" {
  name = "[Oficina Mecânica] Ordens de Serviço · Falhas no processamento"
  type = "query alert"

  query = "sum(last_10m):count:http.server.request.duration{${local.work_order_flow_scope}} by {service,http.route}.as_count() > ${var.work_order_5xx_critical_count}"

  monitor_thresholds {
    warning  = var.work_order_5xx_warning_count
    critical = var.work_order_5xx_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Falhas no fluxo de ordens de serviço"
    warning_symptom = "Falhas no fluxo de ordens de serviço subindo"
    group_suffix    = " — serviço `{{service.name}}`, rota `{{[http.route].name}}`"
    service         = "{{service.name}}"
    environment     = var.env
    unit            = "respostas 5xx em rotas de ordem de serviço ou orçamento"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_work_orders
    logs_url        = local.logs_url_work_order_flow
    runbook_url     = "${local.runbook_url}#falhas-no-processamento-de-ordens-de-serviço"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  # Quotes are answered by billing, so the monitor belongs to both services.
  tags = distinct(concat(local.service_tags["work-order"], local.service_tags["billing"]))
}
