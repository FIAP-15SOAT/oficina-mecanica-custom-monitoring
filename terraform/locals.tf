locals {
  # The key is the bounded context, which is also the Kubernetes namespace and
  # the segment of the public health route `/health/<key>`.
  services = {
    "work-order" = { service = "oficina-mecanica-work-order-service", kube_deployment = "work-order-service" }
    identity     = { service = "oficina-mecanica-identity-service", kube_deployment = "identity-service" }
    billing      = { service = "oficina-mecanica-billing-service", kube_deployment = "billing-service" }
    inventory    = { service = "oficina-mecanica-inventory-service", kube_deployment = "inventory-service" }
  }

  lambdas = {
    "customer-auth" = { function_name = "lbd-oficina-mecanica-customer-auth", service = "oficina-mecanica-lambda-customer-auth" }
    notification    = { function_name = "lbd-oficina-mecanica-notification", service = "oficina-mecanica-lambda-notification" }
  }

  service_scope     = { for k, v in local.services : k => "env:${var.env},service:${v.service}" }
  service_log_scope = { for k, v in local.services : k => "service:${v.service} env:${var.env}" }
  service_k8s_scope = { for k, v in local.services : k => "kube_namespace:${k},kube_deployment:${v.kube_deployment}" }
  lambda_scope      = { for k, v in local.lambdas : k => "functionname:${v.function_name}" }

  # O destino recusa `AND`/`OR` misturados com `,` no mesmo escopo. Onde a
  # consulta precisa de `OR`, a vírgula tem de virar `AND` na expressão inteira.
  services_scope = "env:${var.env} AND (${join(" OR ", [for v in values(local.services) : "service:${v.service}"])})"

  kube_namespaces = toset(concat(keys(local.services), ["platform"]))

  api_endpoint = data.terraform_remote_state.gateway.outputs.api_endpoint

  common_tags = [
    "project:${var.project_name}",
    "managed-by:terraform",
    "env:${var.env}",
  ]

  service_tags = { for k, v in local.services : k => concat(local.common_tags, ["service:${v.service}"]) }
  lambda_tags  = { for k, v in local.lambdas : k => concat(local.common_tags, ["service:${v.service}"]) }

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
  dashboard_url_service     = { for k, d in datadog_dashboard.service : k => "${local.datadog_app_base}${d.url}" }
  dashboard_url_work_orders = "${local.datadog_app_base}${datadog_dashboard.work_orders.url}"
  dashboard_url_kubernetes  = "${local.datadog_app_base}${datadog_dashboard.kubernetes.url}"

  logs_url_service_errors = { for k, s in local.service_log_scope : k => "${var.datadog_app_url}logs?query=${urlencode("${s} status:error")}" }
  logs_url_health         = { for k, s in local.service_log_scope : k => "${var.datadog_app_url}logs?query=${urlencode("${s} @oficina.event.name:health.degraded")}" }
  logs_url_pods           = { for k, s in local.service_log_scope : k => "${var.datadog_app_url}logs?query=${urlencode(s)}" }
  logs_url_lambda         = { for k, v in local.lambdas : k => "${var.datadog_app_url}logs?query=${urlencode("service:${v.service} status:error")}" }

  runbook_url = "https://github.com/FIAP-15SOAT/oficina-mecanica-custom-monitoring/blob/main/docs/runbook.md"

  alert_footer = join(" ", [for e in split(",", var.alert_emails) : "@${trimspace(e)}"])

  monitor_message = <<-EOT
    {{#is_alert}}🔴 **$${alert_symptom}**$${group_suffix}{{/is_alert}}
    {{#is_warning}}🟡 **$${warning_symptom}**$${group_suffix}{{/is_warning}}

    Serviço: `$${service}` · Ambiente: `$${environment}`
    Observado: **{{value}}** $${unit} (limite: {{threshold}}) na janela de $${window}
    Desde: {{first_triggered_at}}

    [Dashboard]($${dashboard_url}) · [Logs]($${logs_url}) · [Runbook]($${runbook_url})

    {{#is_recovery}}✅ Recuperado após {{triggered_duration_sec}}s.{{/is_recovery}}

    ${local.alert_footer}
  EOT

  synthetic_message = <<-EOT
    {{#is_alert}}🔴 **Rota pública indisponível** — a verificação externa falhou em ao menos ${var.synthetic_min_location_failed} das ${length(var.synthetic_locations)} localidades por mais de ${var.synthetic_min_failure_duration_seconds / 60} minutos{{/is_alert}}

    Serviço: `$${service}` · Ambiente: `${var.env}`
    Verificação: `GET $${url}` — esperado `200` em menos de ${var.synthetic_response_time_ms} ms
    Desde: {{first_triggered_at}}

    [Dashboard]($${dashboard_url}) · [Logs]($${logs_url}) · [Runbook]($${runbook_url})

    {{#is_recovery}}✅ Recuperado após {{triggered_duration_sec}}s.{{/is_recovery}}

    ${local.alert_footer}
  EOT
}
