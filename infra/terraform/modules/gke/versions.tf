# Modules declare which providers they need, but NOT provider configuration
# (project/region/credentials). The calling root module (envs/*) does that.
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 9.0"
    }
  }
}
