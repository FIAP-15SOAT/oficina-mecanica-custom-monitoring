# M5 -- memoria do pod proxima do limite.
#
# `working_set` sobre `limits`, e nao `usage`, porque `working_set` e o que o
# encerramento por falta de memoria observa. Nao ha monitor de CPU: com
# autoescalonamento mirando 70% de CPU, "CPU alta" e o mecanismo funcionando.
# O sinal acionavel seria estrangulamento sustentado, que fica no dashboard e
# so vira monitor se M3 provar correlacao.
resource "datadog_monitor" "pod_memory" {
  name = "[Oficina Mecânica] Pod · Memória próxima do limite"
  type = "query alert"

  query = "avg(last_10m):(avg:kubernetes.memory.working_set{${local.k8s_scope}} by {pod_name} / avg:kubernetes.memory.limits{${local.k8s_scope}} by {pod_name}) * 100 > ${var.pod_memory_critical_percent}"

  monitor_thresholds {
    warning  = var.pod_memory_warning_percent
    critical = var.pod_memory_critical_percent
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Memória do pod próxima do limite"
    warning_symptom = "Memória do pod subindo"
    group_suffix    = " — pod `{{pod_name.name}}`"
    service         = var.api_service
    environment     = var.env
    unit            = "% do limite de memória"
    window          = "10 min"
    dashboard_url   = datadog_dashboard.kubernetes.url
    logs_url        = local.logs_url_pods
  })

  new_group_delay     = 300
  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  tags = local.api_tags
}

resource "datadog_monitor" "pod_restarts" {
  name = "[Oficina Mecânica] Pod · Reinícios de contêiner"
  type = "query alert"

  query = "change(sum(last_10m),last_10m):sum:kubernetes.containers.restarts{${local.k8s_scope}} by {pod_name} > ${var.pod_restart_critical_count}"

  monitor_thresholds {
    critical = var.pod_restart_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Contêiner reiniciou"
    warning_symptom = "Contêiner reiniciou"
    group_suffix    = " — pod `{{pod_name.name}}`"
    service         = var.api_service
    environment     = var.env
    unit            = "reinícios na janela"
    window          = "10 min"
    dashboard_url   = datadog_dashboard.kubernetes.url
    logs_url        = local.logs_url_pods
  })

  new_group_delay     = 600
  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "3"

  tags = local.api_tags
}
