# A rota de saúde é excluida da instrumentação na entrada: não há métrica,
# trace nem log de sucesso para ela. Verificação externa é a única forma de
# verificar se a rota pública está de pé".
resource "datadog_synthetics_test" "service_health" {
  for_each = local.services

  name    = "[Oficina Mecânica] Disponibilidade externa ${each.key} · rota pública indisponível"
  type    = "api"
  subtype = "http"
  status  = var.environment_online ? "live" : "paused"
  tags    = local.service_tags[each.key]

  message = templatestring(local.synthetic_message, {
    service       = each.value.service
    url           = "${local.api_endpoint}/health/${each.key}"
    dashboard_url = local.dashboard_url_service[each.key]
    logs_url      = local.logs_url_service_errors[each.key]
    runbook_url   = "${local.runbook_url}#disponibilidade-externa"
  })

  request_definition {
    method = "GET"
    url    = "${local.api_endpoint}/health/${each.key}"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = var.synthetic_response_time_ms
  }

  locations = var.synthetic_locations

  options_list {
    tick_every           = var.synthetic_tick_every_seconds
    min_location_failed  = var.synthetic_min_location_failed
    min_failure_duration = var.synthetic_min_failure_duration_seconds

    monitor_options {
      renotify_interval = 0
    }
  }
}
