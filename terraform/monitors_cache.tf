locals {
  logs_url_cache_invalidation_failed = "${var.datadog_app_url}logs?query=${urlencode("${local.services_scope} @oficina.event.name:cache.invalidation_failed")}"
}

# One monitor grouped by service covers every service, so it carries no
# `service` tag: the tag would light every service row of the overview.
resource "datadog_monitor" "cache_invalidation_failed" {
  name = "[Oficina Mecânica] Cache · Falha na limpeza do cache"
  type = "log alert"

  query = "logs(\"${local.services_scope} @oficina.event.name:cache.invalidation_failed\").index(\"*\").rollup(\"count\").by(\"service\").last(\"10m\") > ${var.cache_invalidation_critical_count}"

  monitor_thresholds {
    critical = var.cache_invalidation_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Chave de cache não apagada depois de uma escrita"
    warning_symptom = "Chave de cache não apagada depois de uma escrita"
    group_suffix    = " — serviço `{{service.name}}`"
    service         = "{{service.name}}"
    environment     = var.env
    unit            = "falhas de limpeza"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_overview
    logs_url        = local.logs_url_cache_invalidation_failed
    runbook_url     = "${local.runbook_url}#falha-na-limpeza-do-cache"
  })

  new_group_delay     = 300
  require_full_window = true

  notify_no_data     = false
  renotify_interval  = 0
  notify_audit       = false
  include_tags       = true
  enable_logs_sample = true
  priority           = "3"

  tags = local.common_tags
}
