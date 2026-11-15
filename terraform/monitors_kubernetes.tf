# Pod memory close to the limit.
#
# `working_set` over `limits`, not `usage`, because `working_set` is what the
# out-of-memory kill watches. There is no CPU monitor: with autoscaling aimed
# at 70% CPU, "high CPU" is the mechanism working. The actionable signal would
# be sustained throttling, which stays on the dashboard and becomes a monitor
# only if service latency proves a correlation.
resource "datadog_monitor" "pod_memory" {
  for_each = local.services

  name = "[Oficina Mecânica] Pod ${each.key} · Memória próxima do limite"
  type = "query alert"

  query = "avg(last_10m):(avg:kubernetes.memory.working_set{${local.service_k8s_scope[each.key]}} by {pod_name} / avg:kubernetes.memory.limits{${local.service_k8s_scope[each.key]}} by {pod_name}) * 100 > ${var.pod_memory_critical_percent}"

  monitor_thresholds {
    warning  = var.pod_memory_warning_percent
    critical = var.pod_memory_critical_percent
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Memória do pod próxima do limite"
    warning_symptom = "Memória do pod subindo"
    group_suffix    = " — pod `{{pod_name.name}}`"
    service         = each.value.service
    environment     = var.env
    unit            = "% do limite de memória"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_kubernetes
    logs_url        = local.logs_url_pods[each.key]
    runbook_url     = "${local.runbook_url}#memória-do-pod-próxima-do-limite"
  })

  new_group_delay     = 300
  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "2"

  tags = local.service_tags[each.key]
}

# `kubernetes.containers.restarts` is a cumulative counter: what matters is the
# change in the window, not the absolute value. `diff()` returns the increment
# between consecutive points, and its `max(last_10m)` answers "was there a
# restart in the window?".
#
# Do not swap it for `change()`: that family does not fire in this case, even
# with a positive counter change.
resource "datadog_monitor" "pod_restarts" {
  for_each = local.services

  name = "[Oficina Mecânica] Pod ${each.key} · Reinícios de contêiner"
  type = "query alert"

  query = "max(last_10m):diff(max:kubernetes.containers.restarts{${local.service_k8s_scope[each.key]}} by {pod_name}) > ${var.pod_restart_critical_count}"

  monitor_thresholds {
    critical = var.pod_restart_critical_count
  }

  message = templatestring(local.monitor_message, {
    alert_symptom   = "Contêiner reiniciou"
    warning_symptom = "Contêiner reiniciou"
    group_suffix    = " — pod `{{pod_name.name}}`"
    service         = each.value.service
    environment     = var.env
    unit            = "de aumento no contador de reinícios"
    window          = "10 min"
    dashboard_url   = local.dashboard_url_kubernetes
    logs_url        = local.logs_url_pods[each.key]
    runbook_url     = "${local.runbook_url}#reinícios-de-contêiner"
  })

  new_group_delay     = 600
  require_full_window = false

  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  include_tags      = true
  priority          = "3"

  tags = local.service_tags[each.key]
}
