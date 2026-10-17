# Inputs to this module. Each has a description (shows up in docs/errors) and,
# where useful, a validation block that fails `terraform plan` early on bad input.

variable "project_id" {
  description = "GCP project ID to create the network in."
  type        = string
}

variable "region" {
  description = "Region for the subnet, Cloud Router and Cloud NAT (e.g. europe-west1)."
  type        = string
}

variable "name" {
  description = "Name prefix for all network resources (e.g. voice-dev)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens (3-42 chars), starting with a letter."
  }
}

variable "subnet_cidr" {
  description = "Primary IPv4 range of the subnet. GKE nodes get their IPs from here."
  type        = string

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR, e.g. 10.10.0.0/20."
  }
}

variable "pods_cidr" {
  description = "Secondary range for Pod IPs (VPC-native / alias IPs). Size it generously: each node reserves a /24 by default."
  type        = string

  validation {
    condition     = can(cidrhost(var.pods_cidr, 0))
    error_message = "pods_cidr must be a valid CIDR, e.g. 10.20.0.0/16."
  }
}

variable "services_cidr" {
  description = "Secondary range for Kubernetes Service (ClusterIP) IPs."
  type        = string

  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "services_cidr must be a valid CIDR, e.g. 10.30.0.0/20."
  }
}

variable "flow_log_sampling" {
  description = "Fraction (0-1) of VPC flow logs to sample. Higher = more visibility, more cost."
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling >= 0 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling must be between 0 and 1."
  }
}
