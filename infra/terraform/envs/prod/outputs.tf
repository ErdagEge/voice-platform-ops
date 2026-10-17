output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "GKE cluster location."
  value       = module.gke.location
}

output "get_credentials_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --location ${module.gke.location} --project ${var.project_id}"
}

output "image_repository" {
  description = "Where CI pushes the call_router image."
  value       = "${module.artifact_registry.repository_url}/call_router"
}

output "workload_identity_pool" {
  description = "Workload Identity pool for binding Kubernetes ServiceAccounts."
  value       = module.gke.workload_identity_pool
}
