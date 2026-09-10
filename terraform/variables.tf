# ---------------------------------------------------------------------------
# Identity of the observed solution
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Base project name used in resource names and tags"
  type        = string
  default     = "oficina-mecanica"
}

variable "env" {
  description = "`env` tag emitted by the API."
  type        = string
  default     = "production"
}

variable "api_service" {
  description = "`service` tag of the API"
  type        = string
  default     = "oficina-mecanica-api"
}

variable "api_kube_deployment" {
  description = "Value of the `kube_deployment` tag that carries the API pods"
  type        = string
  default     = "oficina-api"
}

variable "kube_cluster_name" {
  description = "Value of the `kube_cluster_name` tag, used to scope node-level metrics that carry no service dimension"
  type        = string
  default     = "oficina-mecanica"
}

variable "lambda_function_name" {
  description = "Value of the `functionname` tag of the customer-auth Lambda"
  type        = string
  default     = "lbd-oficina-mecanica-customer-auth"
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
  default     = "bkt-oficina-mecanica"
}

variable "gateway_state_key" {
  description = "S3 object key for the gateway Terraform state (source of api_endpoint)"
  type        = string
  default     = "infra/prod-simulated/gateway/terraform.tfstate"
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

variable "mail_failure_warning_count" {
  description = "Mail.send.failed events per error category in 15 minutes that raise a warning"
  type        = number
  default     = 2
}

variable "mail_failure_critical_count" {
  description = "Mail.send.failed events per error category in 15 minutes that raise an alert"
  type        = number
  default     = 5
}

variable "health_degraded_critical_count" {
  description = "Health.degraded events per failure category in 10 minutes that raise an alert"
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
