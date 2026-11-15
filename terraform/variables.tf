# ---------------------------------------------------------------------------
# Identity of the observed solution
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Base project name used in resource names and tags"
  type        = string
  default     = "oficina-mecanica"
}

variable "env" {
  description = "`env` tag emitted by the services and Lambdas"
  type        = string
  default     = "production"
}

variable "kube_cluster_name" {
  description = "Value of the `kube_cluster_name` tag, used to scope node-level metrics that carry no service dimension"
  type        = string
  default     = "oficina-mecanica"
}

# ---------------------------------------------------------------------------
# Datadog credentials and endpoint
# ---------------------------------------------------------------------------

variable "datadog_api_key" {
  description = "Datadog API key. Never persisted in state: used only in the provider block"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key of the dedicated service account"
  type        = string
  sensitive   = true
}

variable "datadog_api_url" {
  description = "Datadog API endpoint of the destination site"
  type        = string
  default     = "https://api.us5.datadoghq.com/"
}

variable "datadog_app_url" {
  description = "Datadog web interface of the destination site. Every link inside an alert message points here"
  type        = string
  default     = "https://app.us5.datadoghq.com/"
}

# ---------------------------------------------------------------------------
# Alerting and environment state
# ---------------------------------------------------------------------------

variable "alert_emails" {
  description = "Comma-separated notification recipients."
  type        = string

  validation {
    condition     = length(compact([for e in split(",", var.alert_emails) : trimspace(e)])) > 0
    error_message = "alert_emails precisa conter ao menos um endereco."
  }
}

variable "environment_online" {
  description = "Whether the cloud environment is up. Drives the synthetic test between `live` and `paused`"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Remote state inputs
# ---------------------------------------------------------------------------

variable "gateway_state_bucket" {
  description = "S3 bucket name that stores the gateway Terraform state"
  type        = string
}

variable "gateway_state_key" {
  description = "S3 object key for the gateway Terraform state (source of api_endpoint)"
  type        = string
  default     = "infra/prod-simulated/api-gateway/terraform.tfstate"
}

variable "gateway_state_region" {
  description = "AWS region where the gateway Terraform state bucket is hosted"
  type        = string
  default     = "us-east-1"
}

variable "aws_region" {
  description = "AWS region used by the provider that reads the remote state"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Monitor thresholds
#
# Counts, not rates: with sporadic traffic a rate fires on "1 error in 3
# requests". Latency thresholds are user-perception values, not observed
# percentiles -- the calibration procedure lives in docs/runbook.md.
#
# The zeroed thresholds -- container restart, Lambda platform error, degraded
# dependency -- are not a disabled monitor: the operator is `>`, so zero means
# "any occurrence is an incident". They stay as variables for uniformity, and
# because raising one is how a known-noisy signal gets tolerated.
# ---------------------------------------------------------------------------

variable "api_5xx_warning_count" {
  description = "5xx responses per route in 10 minutes that raise a warning"
  type        = number
  default     = 5
}

variable "api_5xx_critical_count" {
  description = "5xx responses per route in 10 minutes that raise an alert"
  type        = number
  default     = 20
}

variable "api_latency_p95_warning_seconds" {
  description = "P95 of http.server.request.duration, in seconds, that raises a warning"
  type        = number
  default     = 1
}

variable "api_latency_p95_critical_seconds" {
  description = "P95 of http.server.request.duration, in seconds, that raises an alert"
  type        = number
  default     = 2
}

variable "work_order_5xx_warning_count" {
  description = "5xx responses on work-order and quote routes in 10 minutes that raise a warning"
  type        = number
  default     = 2
}

variable "work_order_5xx_critical_count" {
  description = "5xx responses on work-order and quote routes in 10 minutes that raise an alert"
  type        = number
  default     = 5
}

variable "pod_memory_warning_percent" {
  description = "Working set over memory limit, in percent, that raises a warning"
  type        = number
  default     = 80
}

variable "pod_memory_critical_percent" {
  description = "Working set over memory limit, in percent, that raises an alert"
  type        = number
  default     = 90
}

variable "pod_restart_critical_count" {
  description = "Container restarts in 10 minutes that raise an alert"
  type        = number
  default     = 0
}

variable "lambda_error_critical_count" {
  description = "Lambda platform errors in 10 minutes that raise an alert"
  type        = number
  default     = 0
}

variable "notification_failure_warning_count" {
  description = "Notification.failed events per failure reason and purpose in 15 minutes that raise a warning"
  type        = number
  default     = 2
}

variable "notification_failure_critical_count" {
  description = "Notification.failed events per failure reason and purpose in 15 minutes that raise an alert"
  type        = number
  default     = 5
}

variable "health_degraded_critical_count" {
  description = "Health.degraded events per failure category in 10 minutes that raise an alert"
  type        = number
  default     = 0
}

variable "dead_letter_critical_count" {
  description = "Messaging.message.dead_lettered events per service, queue and message type in 10 minutes that raise an alert. Zero: each one leaves a work order stuck until the redrive"
  type        = number
  default     = 0
}

variable "outbox_publish_failure_critical_count" {
  description = "Messaging.outbox.publish_failed events per service in 5 minutes that raise an alert. Provisional: the relay retries every 0.5 s plus up to 2 s of timeout, so a persistent failure logs over 120 events in 5 minutes and an isolated one logs 1"
  type        = number
  default     = 10
}

variable "webhook_invalid_signature_critical_count" {
  description = "Payment.webhook.invalid_signature events in 15 minutes that raise an alert. Provisional: a wrong secret rejects every notification and Mercado Pago resends them, while an isolated probe stays below"
  type        = number
  default     = 3
}

variable "saga_compensation_critical_count" {
  description = "QUOTE_APPROVAL sagas finished compensated in 1 hour that raise an alert. Provisional: one compensation is a business outcome, two in a row call for a look at the stock"
  type        = number
  default     = 1
}

variable "cache_invalidation_critical_count" {
  description = "Cache.invalidation_failed events per service in 10 minutes that raise an alert. Zero: the stale value stays until the 12 h TTL"
  type        = number
  default     = 0
}

variable "synthetic_response_time_ms" {
  description = "Upper bound, in milliseconds, asserted on the public health route"
  type        = number
  default     = 5000
}

# ---------------------------------------------------------------------------
# External availability check
#
# The locations are where Datadog runs the check FROM, not where the API runs.
# More than one exists so that a regional network fault is not read as the
# application being down: `min_location_failed` is the quorum that decides.
# ---------------------------------------------------------------------------

variable "synthetic_locations" {
  description = "Managed Datadog locations the health route is checked from"
  type        = list(string)
  default     = ["aws:us-east-1", "aws:sa-east-1", "aws:eu-west-1"]

  validation {
    condition     = length(var.synthetic_locations) >= 2
    error_message = "Ao menos duas localidades: com uma so, uma falha de rede da propria localidade vira alerta."
  }
}

variable "synthetic_tick_every_seconds" {
  description = "How often the health route is checked"
  type        = number
  default     = 300
}

variable "synthetic_min_location_failed" {
  description = "How many locations must agree on a failure before it becomes an alert"
  type        = number
  default     = 2
}

variable "synthetic_min_failure_duration_seconds" {
  description = "How long the failure must persist before it becomes an alert"
  type        = number
  default     = 120
}
