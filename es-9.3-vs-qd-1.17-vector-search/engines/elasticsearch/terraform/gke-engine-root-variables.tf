# Root variables for engines/*/terraform (GKE benchmark inputs from variables/terraform.tfvars).
# Copied to each engine terraform/gke-engine-root-variables.tf by `make <stack> terraform-init`.
# Source lives here (not as .tf) so Terraform does not merge this file into the gke-benchmark module.

variable "location" {
  type = string
}

variable "deletion_protection" {
  type = bool
}

variable "main_pool_disk_type" {
  type = string
}

variable "jingra_pool_name" {
  type = string
}

variable "jingra_pool_disk_size_gb" {
  type = number
}

variable "jingra_pool_machine_type" {
  type = string
}

variable "jingra_pool_node_count" {
  type = number
}

variable "main_pool_disk_size_gb" {
  type = number
}

variable "main_pool_machine_type" {
  type = string
}

variable "main_pool_node_count" {
  type = number
}

variable "ui_pool_disk_size_gb" {
  type = number
}

variable "ui_pool_machine_type" {
  type = string
}

variable "ui_pool_node_count" {
  type = number
}
