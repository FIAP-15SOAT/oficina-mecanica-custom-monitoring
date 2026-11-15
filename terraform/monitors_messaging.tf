# One monitor grouped by service covers every service, so it carries no
# `service` tag: the tag would light every service row of the overview.
locals {
  logs_url_dead_lettered         = "${var.datadog_app_url}logs?query=${urlencode("${local.services_scope} @oficina.event.name:messaging.message.dead_lettered")}"
  logs_url_outbox_publish_failed = "${var.datadog_app_url}logs?query=${urlencode("${local.services_scope} @oficina.event.name:messaging.outbox.publish_failed")}"
}

# Without the AWS integration there is no queue depth; the consumer logs the
# message it gives up on, with queue and type, right before it reaches the DLQ.
resource "datadog_monitor" "dead_lettered" {
  name = "[Oficina Mecânica] Mensageria · Mensagem na DLQ"
  type = "log alert"

  query = "logs(\"${local.services_scope} @oficina.event.name:messaging.message.dead_lettered\").index(\"*\").rollup(\"count\").by(\"service,@messaging.destination.name,@oficina.messaging.message.type\").last(\"10m\") > ${var.dead_letter_critical_count}"

  monitor_thresholds {
    critical = var.dead_letter_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Mensagem enviada à DLQ"
    warning_symptom = "Mensagem enviada à DLQ"
    group_suffix    = " — serviço `{{service.name}}`, fila `{{[@messaging.destination.name].name}}`, tipo `{{[@oficina.messaging.message.type].name}}`"
    service         = "{{service.name}}"
    environment     = var.env
    unit            = "mensagens na DLQ"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_messaging
    logs_url        = local.logs_url_dead_lettered
    runbook_url     = "${local.runbook_url}#mensagem-na-dlq"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "2"

  tags = local.common_tags
}

# The relay stops the batch at the first failed publish to keep the order, so a
# persistent failure logs one event per cycle and holds every later message.
resource "datadog_monitor" "outbox_publish_failed" {
  name = "[Oficina Mecânica] Mensageria · Relay do outbox parado"
  type = "log alert"

  query = "logs(\"${local.services_scope} @oficina.event.name:messaging.outbox.publish_failed\").index(\"*\").rollup(\"count\").by(\"service\").last(\"5m\") > ${var.outbox_publish_failure_critical_count}"

  monitor_thresholds {
    critical = var.outbox_publish_failure_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Relay do outbox parado"
    warning_symptom = "Relay do outbox parado"
    group_suffix    = " — serviço `{{service.name}}`"
    service         = "{{service.name}}"
    environment     = var.env
    unit            = "falhas de publicação"
    window          = "5 min"
    dashboard_url   = local.dashboard_url_messaging
    logs_url        = local.logs_url_outbox_publish_failed
    runbook_url     = "${local.runbook_url}#relay-do-outbox-parado"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "2"

  tags = local.common_tags
}
