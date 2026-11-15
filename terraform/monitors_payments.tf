locals {
  logs_url_webhook_invalid_signature = "${var.datadog_app_url}logs?query=${urlencode("${local.service_log_scope["billing"]} @oficina.event.name:payment.webhook.invalid_signature")}"
}

resource "datadog_monitor" "webhook_invalid_signature" {
  name = "[Oficina Mecânica] Pagamentos · Webhook com assinatura inválida"
  type = "log alert"

  query = "logs(\"${local.service_log_scope["billing"]} @oficina.event.name:payment.webhook.invalid_signature\").index(\"*\").rollup(\"count\").last(\"15m\") > ${var.webhook_invalid_signature_critical_count}"

  monitor_thresholds {
    critical = var.webhook_invalid_signature_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Notificações do Mercado Pago recusadas por assinatura inválida"
    warning_symptom = "Notificações do Mercado Pago recusadas por assinatura inválida"
    group_suffix    = ""
    service         = local.services["billing"].service
    environment     = var.env
    unit            = "notificações recusadas"
    window          = "15 min"
    dashboard_url   = local.dashboard_url_payments
    logs_url        = local.logs_url_webhook_invalid_signature
    runbook_url     = "${local.runbook_url}#webhook-com-assinatura-inválida"
  })

  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "2"

  tags = local.service_tags["billing"]
}
