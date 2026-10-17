# -----------------------------------------------------------------------------
# Network module: a dedicated VPC for the cluster.
#
#   VPC ── subnet (nodes) ── secondary range "pods"
#                         └─ secondary range "services"
#   Cloud Router ── Cloud NAT  (outbound internet for private nodes)
# -----------------------------------------------------------------------------

# A VPC is a private, global network. We create subnets ourselves instead of
# letting Google auto-create one per region ("custom mode"), so IP ranges are
# predictable and don't clash with other networks later (VPN, peering).
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Explicit, logged "deny all ingress" as the lowest-priority rule. GCP already
# denies ingress implicitly, but an explicit rule shows up in firewall logs,
# so blocked connection attempts are visible. GKE adds its own allow rules
# (control plane -> nodes, health checks) at higher priority (1000).
# False positive: GCP-0074 flags wide port ranges in *allow* rules; this one denies.
# trivy:ignore:GCP-0074
resource "google_compute_firewall" "deny_all_ingress" {
  project   = var.project_id
  name      = "${var.name}-deny-all-ingress"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# The subnet lives in one region. GKE "VPC-native" clusters give pods and
# services real VPC IPs taken from the two secondary ranges below.
resource "google_compute_subnetwork" "subnet" {
  project       = var.project_id
  name          = "${var.name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  # Lets nodes without public IPs reach Google APIs (Artifact Registry,
  # Cloud Logging...) over Google's network.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # VPC flow logs: metadata about network connections, useful for security
  # investigations and debugging. Sampling keeps cost under control.
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT needs a Cloud Router to attach to.
resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Private nodes have no public IP, so they can't reach the internet (e.g. to
# pull a public image) on their own. Cloud NAT provides outbound-only access:
# connections out are allowed, nothing from the internet can connect in.
resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.name}-nat"
  region                             = var.region
  router                             = google_compute_router.router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Only log failures to keep log volume (and cost) low.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
