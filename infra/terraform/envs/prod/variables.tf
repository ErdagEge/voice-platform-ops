variable "project_id" {
  description = "GCP project ID for the prod environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase, digits, hyphens)."
  }
}

variable "region" {
  description = "Region for the network, registry and (for prod) the cluster."
  type        = string
  default     = "europe-west1"
}

variable "cluster_location" {
  description = "Zone or region for the GKE cluster. prod default: regional (3 zones) for high availability."
  type        = string
  default     = "europe-west1"
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to call the Kubernetes API (your IP, CI runner egress IPs)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}
