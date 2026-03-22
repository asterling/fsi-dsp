terraform {
  required_version = ">= 1.5"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }

  # AWS S3 backend with DynamoDB state locking
  backend "s3" {
    bucket         = "fsi-terraform-state"       # .env: TF_BACKEND_S3_BUCKET
    key            = "kafka-platform/prod/terraform.tfstate"
    region         = "us-east-1"                 # .env: TF_BACKEND_S3_REGION
    encrypt        = true
    dynamodb_table = "fsi-terraform-locks"       # .env: TF_BACKEND_DYNAMODB_TABLE
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

variable "confluent_cloud_api_key" {
  type      = string
  sensitive = true
}

variable "confluent_cloud_api_secret" {
  type      = string
  sensitive = true
}

variable "kafka_api_key" {
  type      = string
  sensitive = true
}

variable "kafka_api_secret" {
  type      = string
  sensitive = true
}

variable "sr_api_key" {
  type      = string
  sensitive = true
}

variable "sr_api_secret" {
  type      = string
  sensitive = true
}

variable "dr_kafka_api_key" {
  type      = string
  sensitive = true
}

variable "dr_kafka_api_secret" {
  type      = string
  sensitive = true
}

locals {
  # Cluster metadata loaded from variables (populated by clusters.auto.tfvars)
  infra = {
    kafka_cluster_id       = var.kafka_cluster_id
    kafka_rest_endpoint    = var.kafka_rest_endpoint
    kafka_cluster_crn      = var.kafka_cluster_crn
    sr_cluster_id          = var.sr_cluster_id
    sr_rest_endpoint       = var.sr_rest_endpoint
    sr_cluster_crn         = var.sr_cluster_crn
    cluster_link_name      = var.cluster_link_name
    dr_kafka_cluster_id    = var.dr_kafka_cluster_id
    dr_kafka_rest_endpoint = var.dr_kafka_rest_endpoint
  }
}
