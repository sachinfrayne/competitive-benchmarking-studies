terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

variable "project_id" {
  type = string
}

provider "google" {
  project     = var.project_id
  region      = "us-central1"
  credentials = file(abspath("${path.root}/../../../secrets/credentials.json"))
}

module "gke_benchmark" {
  source = "../../../infra/terraform/modules/gke-benchmark"

  cluster_name        = "elasticsearch-benchmark"
  main_pool_name      = "elasticsearch-nodepool"
  enable_ui_node_pool = true
  ui_pool_name        = "kibana-nodepool"
}
