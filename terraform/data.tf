data "terraform_remote_state" "gateway" {
  backend = "s3"

  config = {
    bucket = var.gateway_state_bucket
    key    = var.gateway_state_key
    region = var.gateway_state_region
  }
}
