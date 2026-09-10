# A rota de saúde é excluida da instrumentação na entrada: não há métrica,
# trace nem log de sucesso para ela. Verificação externa é a única forma de
# verificar se a rota pública está de pé".
resource "datadog_synthetics_test" "api_health" {
  name    = "[Oficina Mecânica] Disponibilidade externa · rota pública indisponível"
  type    = "api"
  subtype = "http"
  status  = var.environment_online ? "live" : "paused"
  message = local.synthetic_message
  tags    = local.api_tags

  request_definition {
    method = "GET"
    url    = "${local.api_endpoint}/api/health/ready"
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
