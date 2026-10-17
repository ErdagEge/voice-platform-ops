# Root module for the "prod" environment. A root module is the folder you run
# `terraform init/plan/apply` in. It configures providers + backend and wires
# the reusable modules together.

terraform {
  # Pin Terraform itself and the provider to known-good major versions so a
  # new release can't silently change behaviour. Exact versions are recorded
  # in .terraform.lock.hcl (commit it).
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # Remote state in a GCS bucket (see backend.hcl.example). It's a *partial*
  # config: bucket/prefix are passed at init time:
  #   terraform init -backend-config=backend.hcl
  # For offline checks use: terraform init -backend=false
  backend "gcs" {}
}

# Provider configuration. Credentials come from the environment
# (`gcloud auth application-default login` or CI Workload Identity) - never
# put keys in code.
provider "google" {
  project = var.project_id
  region  = var.region

  # Applied to every resource that supports labels.
  default_labels = {
    env        = "prod"
    app        = "voice-platform"
    managed-by = "terraform"
  }
}
