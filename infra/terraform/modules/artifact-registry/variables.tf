variable "project_id" {
  description = "GCP project ID that owns the repository."
  type        = string
}

variable "location" {
  description = "Region (or multi-region such as \"europe\") for the repository. Same region as the cluster avoids egress cost."
  type        = string
}

variable "repository_id" {
  description = "Repository name, e.g. voice-platform."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.repository_id))
    error_message = "repository_id must be lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "immutable_tags" {
  description = "If true, an existing tag (e.g. v1.2.3) can never be overwritten - recommended for prod."
  type        = bool
  default     = false
}

variable "keep_recent_versions" {
  description = "Cleanup policy: always keep at least this many most recent image versions."
  type        = number
  default     = 20

  validation {
    condition     = var.keep_recent_versions >= 1
    error_message = "keep_recent_versions must be at least 1."
  }
}

variable "reader_members" {
  description = "IAM members allowed to pull images, e.g. [\"serviceAccount:nodes@proj.iam.gserviceaccount.com\"]."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the repository (useful for cost reporting)."
  type        = map(string)
  default     = {}
}
