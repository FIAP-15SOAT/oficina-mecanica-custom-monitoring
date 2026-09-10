terraform {
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = ">= 4.20.0, < 5.0.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.46.0, < 7.0.0"
    }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}

provider "aws" {
  region = var.aws_region
}
