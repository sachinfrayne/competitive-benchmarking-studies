variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
}

variable "main_pool_name" {
  type        = string
  description = "Primary workload node pool name"
}

variable "location" {
  type        = string
  description = "Cluster zone or region"
  default     = "us-central1-a"
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "main_pool_node_count" {
  type    = number
  default = 6
}

variable "main_pool_machine_type" {
  type    = string
  default = "n2d-standard-16"
}

variable "main_pool_disk_type" {
  type    = string
  default = "pd-balanced"
}

variable "main_pool_disk_size_gb" {
  type    = number
  default = 100
}

variable "jingra_pool_name" {
  type    = string
  default = "jingra-nodepool"
}

variable "jingra_pool_node_count" {
  type    = number
  default = 1
}

variable "jingra_pool_machine_type" {
  type    = string
  default = "e2-standard-8"
}

variable "jingra_pool_disk_size_gb" {
  type    = number
  default = 50
}

variable "enable_ui_node_pool" {
  type        = bool
  description = "If true, create a small pool for UI workloads (e.g. Kibana on Elasticsearch). Qdrant stacks should set false."
  default     = false
}

variable "ui_pool_name" {
  type        = string
  description = "Node pool name when enable_ui_node_pool is true"
}

variable "ui_pool_node_count" {
  type    = number
  default = 1
}

variable "ui_pool_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "ui_pool_disk_size_gb" {
  type    = number
  default = 50
}
