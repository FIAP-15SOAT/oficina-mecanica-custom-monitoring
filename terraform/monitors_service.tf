resource "datadog_monitor" "service_5xx" {
  for_each = local.services

  name = "[Oficina Mecânica] Serviço ${each.key} · Erros 5xx acima do limite"
  type = "query alert"

  query = "sum(last_10m):count:http.server.request.duration{${local.service_scope[each.key]},http.response.status_code:5*} by {http.route}.as_count() > ${var.api_5xx_critical_count}"

  monitor_thresholds {
    warning  = var.api_5xx_warning_count
    critical = var.api_5xx_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Erros 5xx acima do limite"
    warning_symptom = "Erros 5xx subindo"
    group_suffix    = " — rota `{{http.route.name}}`"
    service         = each.value.service
    environment     = var.env
    unit            = "respostas 5xx"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_service[each.key]
    logs_url        = local.logs_url_service_errors[each.key]
    runbook_url     = "${local.runbook_url}#erros-5xx-acima-do-limite"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  tags = local.service_tags[each.key]
}

resource "datadog_monitor" "service_latency_p95" {
  for_each = local.services

  name = "[Oficina Mecânica] Serviço ${each.key} · Latência p95 acima do alvo"
  type = "query alert"

  query = "percentile(last_15m):p95:http.server.request.duration{${local.service_scope[each.key]}} > ${var.api_latency_p95_critical_seconds}"

  monitor_thresholds {
    warning  = var.api_latency_p95_warning_seconds
    critical = var.api_latency_p95_critical_seconds
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Latência p95 acima do alvo"
    warning_symptom = "Latência p95 subindo"
    group_suffix    = ""
    service         = each.value.service
    environment     = var.env
    unit            = "segundos no p95"
    window          = "15 min"
    dashboard_url   = local.dashboard_url_service[each.key]
    logs_url        = local.logs_url_service_errors[each.key]
    runbook_url     = "${local.runbook_url}#latência-p95-acima-do-alvo"
  })

  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "3"

  tags = local.service_tags[each.key]

  depends_on = [datadog_metric_tag_configuration.http_server_request_duration]
}
