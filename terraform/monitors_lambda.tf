resource "datadog_monitor" "lambda_errors" {
  for_each = local.lambdas

  name = "[Oficina Mecânica] Lambda ${each.key} · Erros de execução"
  type = "query alert"

  query = "sum(last_10m):sum:aws.lambda.enhanced.errors{${local.lambda_scope[each.key]}}.as_count() > ${var.lambda_error_critical_count}"

  monitor_thresholds {
    critical = var.lambda_error_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Erro de execução na Lambda ${each.key}"
    warning_symptom = "Erro de execução na Lambda ${each.key}"
    group_suffix    = " — `${each.value.function_name}`"
    service         = each.value.service
    environment     = var.env
    unit            = "erros de plataforma"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_overview
    logs_url        = local.logs_url_lambda[each.key]
    runbook_url     = "${local.runbook_url}#erros-de-execução-da-lambda"
  })

  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  tags = local.lambda_tags[each.key]
}
