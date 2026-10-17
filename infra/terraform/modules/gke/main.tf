# -----------------------------------------------------------------------------
# GKE module: a private GKE Standard cluster + one autoscaling node pool.
#
# "Standard" (vs Autopilot) means we manage node pools ourselves, which is
# what this project wants to demonstrate.
# -----------------------------------------------------------------------------

# --- Node service account (least privilege) --------------------------------
# By default nodes run as the Compute Engine default service account, which
# has the very broad "Editor" role on the project. Instead we create a
# dedicated account with only what nodes need: write logs/metrics, and (granted
# in the env root) pull images from our Artifact Registry repo.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes for ${var.name}"
}

locals {
  node_roles = [
    "roles/logging.logWriter",                   # ship container logs
    "roles/monitoring.metricWriter",             # ship metrics
    "roles/monitoring.viewer",                   # read metrics (needed by agents)
    "roles/stackdriver.resourceMetadata.writer", # attach resource metadata
    "roles/autoscaling.metricsWriter",           # cluster autoscaler metrics
  ]
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# --- The cluster (control plane) -------------------------------------------
resource "google_container_cluster" "this" {
  # Scanner findings we accept on purpose (checkov / trivy):
  # checkov:skip=CKV_GCP_12: NetworkPolicy IS enforced - by Dataplane V2 (ADVANCED_DATAPATH). The legacy network_policy (Calico) block conflicts with it.
  # checkov:skip=CKV_GCP_66: Binary Authorization needs signed images from CI; planned for the CI/CD step.
  # checkov:skip=CKV_GCP_65: Google Groups for RBAC needs a Workspace/Cloud Identity domain, which a portfolio project doesn't have.
  project  = var.project_id
  name     = var.name
  location = var.location

  # Terraform-managed node pools are easier to change than the built-in
  # default pool, so we create the cluster with a tiny default pool and
  # delete it immediately. Our real pool is defined below.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Safety catch: `terraform destroy` fails while this is true.
  deletion_protection = var.deletion_protection

  network    = var.network_id
  subnetwork = var.subnet_id

  # VPC-native networking: pods/services use the subnet's secondary ranges.
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Dataplane V2 (eBPF/Cilium-based). It enforces Kubernetes NetworkPolicies
  # natively, so no separate Calico add-on is needed.
  datapath_provider = "ADVANCED_DATAPATH"

  # Private cluster: nodes get only internal IPs (outbound via Cloud NAT).
  # The control plane keeps a public endpoint so CI/you can run kubectl, but
  # only from master_authorized_networks (see below).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Allow-list for the Kubernetes API. An empty list = no external access
  # (only from inside the VPC).
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Google applies Kubernetes upgrades automatically within this channel.
  release_channel {
    channel = var.release_channel
  }

  # Workload Identity: lets a Kubernetes ServiceAccount act as a Google
  # service account - no JSON key files inside pods.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Shielded nodes: verified boot + node identity, prevents node impersonation.
  enable_shielded_nodes = true

  # Kubernetes RBAC only; the legacy ABAC authorizer stays off.
  enable_legacy_abac = false

  # Never issue long-lived client certificates; kubectl auth goes through
  # short-lived Google OAuth tokens (gcloud) instead.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Make pod-to-pod traffic on the same node visible to VPC flow logs (normally
  # it never leaves the node, so it would be invisible).
  enable_intranode_visibility = true

  # Cloud Logging / Monitoring. WORKLOADS = our app's stdout (our JSON logs).
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    # Google Managed Service for Prometheus - scrapes Prometheus-format
    # /metrics endpoints; used in the observability step.
    managed_prometheus {
      enabled = true
    }
  }

  # Don't let Google upgrade/repair at random times: a weekly window
  # (UTC) on Saturday/Sunday nights.
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T01:00:00Z"
      end_time   = "2026-01-03T05:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # Kubernetes labels on the cluster resource itself (cost breakdowns).
  resource_labels = var.labels

  # The temporary default pool is still created; harden its config too so
  # scanners (and reality) are happy for the minute it exists.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    # node_config only describes the deleted default pool; changes to it
    # would otherwise force recreating the whole cluster.
    ignore_changes = [node_config]
  }
}

# --- App node pool ---------------------------------------------------------
resource "google_container_node_pool" "app" {
  project  = var.project_id
  name     = "${var.name}-app"
  location = var.location
  cluster  = google_container_cluster.this.name

  # The cluster autoscaler adds/removes nodes when pods don't fit or nodes
  # sit idle. Limits are per zone.
  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  # Let GKE replace unhealthy nodes and keep node versions current.
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades: add 1 new node before draining an old one, so capacity
  # never drops during upgrades (pairs with our PodDisruptionBudget).
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD" # Google's hardened, minimal node OS
    spot         = var.spot

    # Least-privilege identity (above). The broad OAuth scope is the
    # Google-recommended setting: actual permissions come from IAM roles.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required for Workload Identity: pods see the GKE metadata server, not
    # the node's credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(var.labels, { pool = "app", spot = tostring(var.spot) })

    # Block the old, insecure metadata API.
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    # The autoscaler changes node counts; don't fight it on every apply.
    ignore_changes = [initial_node_count]
  }
}
