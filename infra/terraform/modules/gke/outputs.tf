output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Cluster location (zone or region)."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Kubernetes API endpoint (sensitive: don't print in CI logs)."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "node_service_account" {
  description = "Email of the node service account (grant it image pull rights)."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool to bind Kubernetes ServiceAccounts to."
  value       = "${var.project_id}.svc.id.goog"
}
