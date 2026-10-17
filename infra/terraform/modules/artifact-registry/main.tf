# -----------------------------------------------------------------------------
# Artifact Registry: a private Docker registry for the call_router image.
# CI pushes images here; GKE nodes pull them.
# Image path: <location>-docker.pkg.dev/<project>/<repository_id>/call_router:<tag>
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "docker" {
  # Accepted finding: data is encrypted at rest with Google-managed keys by
  # default. Customer-managed keys (KMS) add cost and key-ops work and are only
  # needed for specific compliance requirements - revisit for regulated customers.
  # checkov:skip=CKV_GCP_84: Google-managed encryption is sufficient here (see above).
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  description   = "Docker images for the voice platform"
  format        = "DOCKER"
  labels        = var.labels

  docker_config {
    immutable_tags = var.immutable_tags
  }

  # Cleanup policies stop old images piling up (storage costs money).
  # Rule 1: delete untagged images (left over when a tag moves) after 7 days.
  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }

  # Rule 2: but always keep the N most recent versions (safe rollbacks).
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_recent_versions
    }
  }
}

# Least privilege: grant *read* (pull) on this one repository only, instead
# of a project-wide role. `for_each` creates one binding per member.
resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = toset(var.reader_members)

  project    = var.project_id
  location   = google_artifact_registry_repository.docker.location
  repository = google_artifact_registry_repository.docker.name
  role       = "roles/artifactregistry.reader"
  member     = each.value
}
