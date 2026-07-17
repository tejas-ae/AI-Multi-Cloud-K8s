resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "ai-multicloud-k8s-gke-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = "ai-multicloud-k8s-gke-subnet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = "10.10.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "ai-multicloud-k8s-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = "ai-multicloud-k8s-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "ai-multicloud-gke-nodes"
  display_name = "AI Multi-Cloud K8s GKE nodes"
}

resource "google_project_iam_member" "node_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project            = var.project_id
  name               = var.cluster_name
  location           = var.zone
  min_master_version = var.kubernetes_version

  network    = google_compute_network.this.id
  subnetwork = google_compute_subnetwork.this.id

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
  networking_mode          = "VPC_NATIVE"
  enable_shielded_nodes    = true

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  addons_config {
    http_load_balancing {
      disabled = true
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.admin_cidr
      display_name = "operator"
    }
  }

  resource_labels = var.labels

  depends_on = [google_compute_router_nat.this]
}

resource "google_container_node_pool" "primary" {
  project  = var.project_id
  name     = "primary"
  location = var.zone
  cluster  = google_container_cluster.this.name
  version  = var.kubernetes_version

  initial_node_count = var.min_nodes

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.node_machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 60
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.node_roles]
}

resource "google_compute_address" "ingress" {
  project      = var.project_id
  name         = "ai-multicloud-k8s-gke-ingress"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}
