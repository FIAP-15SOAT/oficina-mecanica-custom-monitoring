locals {
  logs_url_quote_approval_compensated = "${var.datadog_app_url}logs?query=${urlencode("${local.service_log_scope["work-order"]} @oficina.event.name:saga.compensated @oficina.saga.type:QUOTE_APPROVAL")}"
}

# PAYMENT sagas end compensated when the charge is rejected, expires or is
# cancelled, which are normal payment outcomes, so only QUOTE_APPROVAL counts.
# Metric tag values arrive lowercased, unlike the log attribute in the link above.
resource "datadog_monitor" "saga_compensations" {
  name = "[Oficina Mecânica] Sagas · Compensações da aprovação de orçamento"
  type = "query alert"

  query = "sum(last_1h):sum:oficina.saga.finished{${local.service_scope["work-order"]},oficina.saga.outcome:compensated,oficina.saga.type:quote_approval}.as_count() > ${var.saga_compensation_critical_count}"

  monitor_thresholds {
    critical = var.saga_compensation_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Aprovações de orçamento compensadas acima do esperado"
    warning_symptom = "Aprovações de orçamento compensadas acima do esperado"
    group_suffix    = ""
    service         = local.services["work-order"].service
    environment     = var.env
    unit            = "Sagas compensadas"
    window          = "1 h"
    dashboard_url   = local.dashboard_url_sagas
    logs_url        = local.logs_url_quote_approval_compensated
    runbook_url     = "${local.runbook_url}#compensações-de-saga"
  })

  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "3"

  tags = local.service_tags["work-order"]
}
