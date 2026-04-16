resource "google_container_node_pool" "jingra_node" {
  name       = "jingra-nodepool"
  cluster    = google_container_cluster.es_context_engineering_benchmark.id
  node_count = 1

  node_config {
    machine_type = "e2-standard-8"
    disk_size_gb = 50
  }
}
