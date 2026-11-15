locals {
  logs_url_notification_failed = "${var.datadog_app_url}logs?query=${urlencode("service:${local.lambdas["notification"].service} env:${var.env} @oficina.event.name:notification.failed")}"
}

resource "datadog_monitor" "mail_send_failed" {
  name = "[Oficina Mecânica] Lambda notification · Falha de envio de e-mail"
  type = "log alert"

  query = "logs(\"service:${local.lambdas["notification"].service} env:${var.env} @oficina.event.name:notification.failed\").index(\"*\").rollup(\"count\").by(\"@oficina.notification.failure.reason,@oficina.notification.purpose\").last(\"15m\") > ${var.notification_failure_critical_count}"

  monitor_thresholds {
    warning  = var.notification_failure_warning_count
    critical = var.notification_failure_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Falha de envio de e-mail"
    warning_symptom = "Falhas de envio de e-mail subindo"
    group_suffix    = " — motivo `{{@oficina.notification.failure.reason.name}}`, e-mail `{{@oficina.notification.purpose.name}}`"
    service         = local.lambdas["notification"].service
    environment     = var.env
    unit            = "falhas de envio"
    window          = "15 min"
    dashboard_url   = local.dashboard_url_overview
    logs_url        = local.logs_url_notification_failed
    runbook_url     = "${local.runbook_url}#falha-de-envio-de-e-mail"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "4"

  tags = local.lambda_tags["notification"]
}

# `health.degraded` is logged by the readiness check itself, with the dependency
# name and the failure type. The health route is excluded from instrumentation,
# so no metric or trace says which dependency failed.
resource "datadog_monitor" "health_degraded" {
  for_each = local.services

  name = "[Oficina Mecânica] Serviço ${each.key} · Health check degradado"
  type = "log alert"

  query = "logs(\"${local.service_log_scope[each.key]} @oficina.event.name:health.degraded\").index(\"*\").rollup(\"count\").by(\"@oficina.dependency.name,@oficina.health.failure.category\").last(\"10m\") > ${var.health_degraded_critical_count}"

  monitor_thresholds {
    critical = var.health_degraded_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Health check degradado"
    warning_symptom = "Health check degradado"
    group_suffix    = " — dependência `{{@oficina.dependency.name.name}}`, falha `{{@oficina.health.failure.category.name}}`"
    service         = each.value.service
    environment     = var.env
    unit            = "ocorrências de degradação"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_service[each.key]
    logs_url        = local.logs_url_health[each.key]
    runbook_url     = "${local.runbook_url}#health-check-degradado"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "3"

  tags = local.service_tags[each.key]
}
