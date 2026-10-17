variable "project_id" {
  description = "GCP project ID for the cluster."
  type        = string
}

variable "name" {
  description = "Cluster name (also used as prefix for the node pool and node service account)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.name))
    error_message = "name must be 3-24 chars of lowercase letters, digits and hyphens (service account IDs are limited to 30 chars)."
  }
}

variable "location" {
  description = "A zone (e.g. europe-west1-b) gives a cheaper zonal cluster; a region (e.g. europe-west1) gives a regional cluster with a control plane + nodes in 3 zones."
  type        = string
}

variable "network_id" {
  description = "VPC ID (from the network module)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID (from the network module)."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the subnet secondary range for Pods."
  type        = string
}

variable "services_range_name" {
  description = "Name of the subnet secondary range for Services."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "/28 range for the Google-managed control plane's private endpoint. Must not overlap any other range."
  type        = string

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a /28, e.g. 172.16.0.0/28."
  }
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the Kubernetes API (kubectl / CI runners). Keep this list short."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0)) && n.cidr_block != "0.0.0.0/0"])
    error_message = "Each cidr_block must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR or STABLE. Google upgrades the cluster automatically within the channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "machine_type" {
  description = "Compute Engine machine type for the app node pool."
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Boot disk size per node, in GB."
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size_gb >= 20
    error_message = "disk_size_gb must be at least 20."
  }
}

variable "min_nodes" {
  description = "Minimum nodes PER ZONE for the autoscaler (regional clusters multiply by the number of zones)."
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum nodes PER ZONE for the autoscaler."
  type        = number
  default     = 3

  validation {
    condition     = var.max_nodes >= 1
    error_message = "max_nodes must be at least 1."
  }
}

variable "spot" {
  description = "Use Spot VMs (60-91% cheaper, but Google can reclaim them with 30s notice). Fine for dev, risky for prod."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "If true, Terraform refuses to destroy the cluster. Set true for prod."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels for the cluster and nodes (cost reporting, ownership)."
  type        = map(string)
  default     = {}
}
