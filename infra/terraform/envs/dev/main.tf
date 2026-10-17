# -----------------------------------------------------------------------------
# dev environment: network -> GKE cluster -> Artifact Registry.
# Differences between dev and prod live in the `locals` below.
# -----------------------------------------------------------------------------

locals {
  name = "voice-dev"

  # Environment sizing / safety knobs.
  machine_type        = "e2-standard-2"
  min_nodes           = 1 # per zone
  max_nodes           = 3 # per zone
  spot                = true
  deletion_protection = false
  release_channel     = "REGULAR"
  immutable_tags      = false

  # Non-overlapping IP plan (dev and prod differ so they could be peered).
  subnet_cidr   = "10.10.0.0/20"
  pods_cidr     = "10.20.0.0/16"
  services_cidr = "10.30.0.0/20"
  master_cidr   = "172.16.0.0/28"
  flow_sampling = 0.25
}

# Turn on the Google APIs we use. disable_on_destroy = false so destroying
# this stack never switches off an API that something else might depend on.
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# A "module" block calls a reusable module with inputs. Terraform works out
# the order from references (e.g. gke uses module.network outputs).
module "network" {
  source = "../../modules/network"

  project_id        = var.project_id
  region            = var.region
  name              = local.name
  subnet_cidr       = local.subnet_cidr
  pods_cidr         = local.pods_cidr
  services_cidr     = local.services_cidr
  flow_log_sampling = local.flow_sampling

  depends_on = [google_project_service.apis]
}

module "gke" {
  source = "../../modules/gke"

  project_id                 = var.project_id
  name                       = local.name
  location                   = var.cluster_location
  network_id                 = module.network.network_id
  subnet_id                  = module.network.subnet_id
  pods_range_name            = module.network.pods_range_name
  services_range_name        = module.network.services_range_name
  master_ipv4_cidr_block     = local.master_cidr
  master_authorized_networks = var.master_authorized_networks
  release_channel            = local.release_channel
  machine_type               = local.machine_type
  min_nodes                  = local.min_nodes
  max_nodes                  = local.max_nodes
  spot                       = local.spot
  deletion_protection        = local.deletion_protection
  labels                     = { env = "dev" }
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id     = var.project_id
  location       = var.region
  repository_id  = "voice-platform-dev"
  immutable_tags = local.immutable_tags
  # Nodes may pull images from this repo only.
  reader_members = ["serviceAccount:${module.gke.node_service_account}"]

  depends_on = [google_project_service.apis]
}
