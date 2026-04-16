resource "google_container_cluster" "qdrant_context_engineering_benchmark" {
  name                = "qdrant-context-engineering-benchmark"
  location            = "us-central1-a"
  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "qdrant_context_engineering_nodes" {
  name       = "qdrant-context-engineering-nodepool"
  cluster    = google_container_cluster.qdrant_context_engineering_benchmark.id
  node_count = 6

  node_config {
    machine_type = "n2d-standard-16"
    disk_type    = "pd-balanced"
    disk_size_gb = 100
  }
}
