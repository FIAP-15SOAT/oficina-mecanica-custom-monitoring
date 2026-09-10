locals {
  api_scope = "env:${var.env},service:${var.api_service}"

  # O destino recusa `AND`/`OR` misturados com `,` no mesmo escopo. Onde a
  # consulta precisa de `OR`, a vírgula tem de virar `AND` na expressão inteira.
  api_scope_and = "env:${var.env} AND service:${var.api_service}"

  k8s_scope    = "kube_deployment:${var.api_kube_deployment}"
  lambda_scope = "functionname:${var.lambda_function_name}"
  log_scope    = "service:${var.api_service} env:${var.env}"

  work_order_routes = "(http.route:/api/work-orders* OR http.route:/api/quotes*)"

  api_endpoint = data.terraform_remote_state.gateway.outputs.api_endpoint

  common_tags = [
    "project:${var.project_name}",
    "managed-by:terraform",
    "env:${var.env}",
  ]

  api_tags = concat(local.common_tags, ["service:${var.api_service}"])

  # Dashboard só aceita as chaves `team` e `ai` -- qualquer outra volta
  # 400 "Invalid tag format". A restrição é do destino e vale só para
  # dashboards: monitor e teste sintético aceitam tag arbitrária.
  dashboard_tags = ["team:${var.project_name}"]

  # `datadog_dashboard.url` devolve CAMINHO (`/dashboard/<id>/<slug>`), não
  # endereço absoluto. Num resumo de execução do GitHub ou num e-mail de
  # alerta, esse caminho resolve contra o domínio errado e o link chega
  # quebrado.
  datadog_app_base = trimsuffix(var.datadog_app_url, "/")

  dashboard_url_overview    = "${local.datadog_app_base}${datadog_dashboard.overview.url}"
  dashboard_url_api         = "${local.datadog_app_base}${datadog_dashboard.api.url}"
  dashboard_url_work_orders = "${local.datadog_app_base}${datadog_dashboard.work_orders.url}"
  dashboard_url_kubernetes  = "${local.datadog_app_base}${datadog_dashboard.kubernetes.url}"
  lambda_tags               = concat(local.common_tags, ["service:oficina-mecanica-lambda-customer-auth"])


  logs_url_api_errors  = "${var.datadog_app_url}logs?query=${urlencode("${local.log_scope} status:error")}"
  logs_url_work_orders = "${var.datadog_app_url}logs?query=${urlencode("${local.log_scope} @oficina.event.name:work_order.status.updated")}"
  logs_url_mail        = "${var.datadog_app_url}logs?query=${urlencode("${local.log_scope} @oficina.event.name:mail.send.failed")}"
  logs_url_health      = "${var.datadog_app_url}logs?query=${urlencode("${local.log_scope} @oficina.event.name:health.degraded")}"
  logs_url_lambda      = "${var.datadog_app_url}logs?query=${urlencode("service:oficina-mecanica-lambda-customer-auth status:error")}"
  logs_url_pods        = "${var.datadog_app_url}logs?query=${urlencode("${local.log_scope}")}"

  alert_footer = join(" ", [for e in split(",", var.alert_emails) : "@${trimspace(e)}"])

  monitor_message = <<-EOT
    {{#is_alert}}🔴 **$${alert_symptom}**$${group_suffix}{{/is_alert}}
    {{#is_warning}}🟡 **$${warning_symptom}**$${group_suffix}{{/is_warning}}

    Serviço: `$${service}` · Ambiente: `$${environment}`
    Observado: **{{value}}** $${unit} (limite: {{threshold}}) na janela de $${window}
    Desde: {{first_triggered_at}}

    [Dashboard]($${dashboard_url}) · [Logs]($${logs_url})

    {{#is_recovery}}✅ Recuperado após {{triggered_duration_sec}}s.{{/is_recovery}}

    ${local.alert_footer}
  EOT

  synthetic_message = <<-EOT
    {{#is_alert}}🔴 **Rota pública indisponível** — a verificação externa falhou em ao menos ${var.synthetic_min_location_failed} das ${length(var.synthetic_locations)} localidades por mais de ${var.synthetic_min_failure_duration_seconds / 60} minutos{{/is_alert}}

    Serviço: `${var.api_service}` · Ambiente: `${var.env}`
    Verificação: `GET ${local.api_endpoint}/api/health/ready` — esperado `200` em menos de ${var.synthetic_response_time_ms} ms
    Desde: {{first_triggered_at}}

    [Dashboard](${local.dashboard_url_api}) · [Logs](${local.logs_url_api_errors})

    {{#is_recovery}}✅ Recuperado após {{triggered_duration_sec}}s.{{/is_recovery}}

    ${local.alert_footer}
  EOT
}
