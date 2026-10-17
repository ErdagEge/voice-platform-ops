output "repository_id" {
  description = "Repository ID."
  value       = google_artifact_registry_repository.docker.repository_id
}

output "repository_url" {
  description = "Docker registry URL to tag/push images to."
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
