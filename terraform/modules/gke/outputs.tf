output "cluster_name" { value = google_container_cluster.this.name }
output "location" { value = google_container_cluster.this.location }
output "ingress_public_ip" { value = google_compute_address.ingress.address }
output "network_name" { value = google_compute_network.this.name }
output "subnetwork_name" { value = google_compute_subnetwork.this.name }
