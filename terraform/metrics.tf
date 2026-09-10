resource "datadog_metric_tag_configuration" "http_server_request_duration" {
  metric_name         = "http.server.request.duration"
  metric_type         = "distribution"
  include_percentiles = true

  tags = [
    "env",
    "service",
    "http.route",
    "http.response.status_code",
  ]
}
