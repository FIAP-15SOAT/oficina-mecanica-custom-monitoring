resource "datadog_monitor" "mail_send_failed" {
  name = "[Oficina Mecânica] Integrações · Falha de envio de e-mail"
  type = "log alert"

  query = "logs(\"${local.log_scope} @oficina.event.name:mail.send.failed\").index(\"*\").rollup(\"count\").by(\"@oficina.mail.error.category\").last(\"15m\") > ${var.mail_failure_critical_count}"

  monitor_thresholds {
    warning  = var.mail_failure_warning_count
    critical = var.mail_failure_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Falha de envio de e-mail"
    warning_symptom = "Falhas de envio de e-mail subindo"
    group_suffix    = " — categoria `{{@oficina.mail.error.category.name}}`"
    service         = var.api_service
    environment     = var.env
    unit            = "falhas de envio"
    window          = "15 min"
    dashboard_url   = local.dashboard_url_api
    logs_url        = local.logs_url_mail
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "4"

  tags = local.api_tags
}

# O evento `health.degraded` é emitido pela própria verificação de saúde interna
# quando uma dependência responde fora do esperado. É o único sinal que nomeia
# **qual** dependência falhou -- a rota de saúde é excluída da instrumentação na
# entrada, então não há métrica nem trace dela.
resource "datadog_monitor" "dependency_degraded" {
  name = "[Oficina Mecânica] Dependência · Health check degradado"
  type = "log alert"

  query = "logs(\"${local.log_scope} @oficina.event.name:health.degraded\").index(\"*\").rollup(\"count\").by(\"@oficina.health.failure.category\").last(\"10m\") > ${var.health_degraded_critical_count}"

  monitor_thresholds {
    critical = var.health_degraded_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Dependência degradada"
    warning_symptom = "Dependência degradada"
    group_suffix    = " — categoria `{{@oficina.health.failure.category.name}}`"
    service         = var.api_service
    environment     = var.env
    unit            = "ocorrências de degradação"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_api
    logs_url        = local.logs_url_health
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "3"

  tags = local.api_tags
}
