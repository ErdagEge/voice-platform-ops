# Outputs are this module's "return values", consumed by other modules.

output "network_id" {
  description = "ID of the VPC."
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "ID of the GKE subnet."
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  description = "Name of the GKE subnet."
  value       = google_compute_subnetwork.subnet.name
}

output "pods_range_name" {
  description = "Name of the secondary range used for Pod IPs."
  value       = "pods"
}

output "services_range_name" {
  description = "Name of the secondary range used for Service IPs."
  value       = "services"
}
