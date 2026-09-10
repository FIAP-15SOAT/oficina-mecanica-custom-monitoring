project_name = "oficina-mecanica"
env          = "production"
api_service  = "oficina-mecanica-api"

api_kube_deployment  = "oficina-api"
kube_cluster_name    = "oficina-mecanica"
lambda_function_name = "lbd-oficina-mecanica-customer-auth"

aws_region           = "us-east-1"
gateway_state_bucket = "bkt-oficina-mecanica"
gateway_state_key    = "infra/prod-simulated/gateway/terraform.tfstate"
gateway_state_region = "us-east-1"

datadog_api_url = "https://api.us5.datadoghq.com/"
datadog_app_url = "https://app.us5.datadoghq.com/"

api_5xx_warning_count            = 5
api_5xx_critical_count           = 20
api_latency_p95_warning_seconds  = 1
api_latency_p95_critical_seconds = 2

work_order_5xx_warning_count  = 2
work_order_5xx_critical_count = 5

pod_memory_warning_percent  = 80
pod_memory_critical_percent = 90
pod_restart_critical_count  = 0
lambda_error_critical_count = 0

mail_failure_warning_count     = 2
mail_failure_critical_count    = 5
health_degraded_critical_count = 0

synthetic_response_time_ms             = 5000
synthetic_tick_every_seconds           = 300
synthetic_min_location_failed          = 2
synthetic_min_failure_duration_seconds = 120
synthetic_locations                    = ["aws:us-east-1", "aws:sa-east-1", "aws:eu-west-1"]
