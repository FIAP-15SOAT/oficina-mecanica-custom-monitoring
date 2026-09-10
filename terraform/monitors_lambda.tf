resource "datadog_monitor" "lambda_errors" {
  name = "[Oficina Mecânica] Lambda customer-auth · Erros de execução"
  type = "query alert"

  query = "sum(last_10m):sum:aws.lambda.enhanced.errors{${local.lambda_scope}}.as_count() > ${var.lambda_error_critical_count}"

  monitor_thresholds {
    critical = var.lambda_error_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Erro de execução na Lambda de autenticação"
    warning_symptom = "Erro de execução na Lambda de autenticação"
    group_suffix    = " — `${var.lambda_function_name}`"
    service         = "oficina-mecanica-lambda-customer-auth"
    environment     = var.env
    unit            = "erros de plataforma"
    window          = "10 min"
    dashboard_url   = datadog_dashboard.overview.url
    logs_url        = local.logs_url_lambda
  })

  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  tags = local.lambda_tags
}
