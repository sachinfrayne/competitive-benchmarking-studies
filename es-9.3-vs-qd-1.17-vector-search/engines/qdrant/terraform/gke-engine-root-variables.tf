# Canonical root variables for engines/*/terraform (pool sizing).
# Copied to each engine terraform/ by `make <stack> terraform-init`. Edit here only, then re-run init to refresh copies.

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
