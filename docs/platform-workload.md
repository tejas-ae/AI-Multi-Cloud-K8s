# Platform verification workload

I use a small stateless HTTP workload to verify the delivery and traffic path before adding business services. The workload runs independently in GKE and AKS, participates in each local Istio mesh, and exposes the `/healthz` route monitored by Azure Traffic Manager.

This is a platform verification target, not the final application architecture. It lets me prove GitOps, sidecar injection, strict mTLS, ingress routing, disruption behavior, fixed public addresses, and global DNS health without introducing a database or cross-cloud credentials.

## Runtime

The Deployment runs Kubernetes `agnhost` `2.59` in `netexec` mode. That version is tied to the Kubernetes 1.35 patch line used by the clusters. The server provides:

- `/healthz` for container probes, ingress verification, and Traffic Manager monitoring;
- `/hostname` for observing which replica answered; and
- `/` for a simple HTTP response.

The `netexec` UDP readiness listener remains enabled because its `/healthz` handler reports success only after that listener is ready. The Kubernetes Service publishes only HTTP, so neither Istio ingress nor Traffic Manager exposes the UDP port. The Pod does not mount a service-account token.

## Availability

Each cluster runs two replicas. Required pod anti-affinity places the replicas on different worker nodes, and a PodDisruptionBudget keeps at least one available during voluntary disruption.

The Deployment uses a rolling update with no surge and one permitted unavailable replica. This lets Kubernetes remove one old Pod before placing its replacement on the freed worker, which is required when two replicas with hard anti-affinity fill the two-node baseline. The remaining replica stays available, consistent with the PodDisruptionBudget. Startup, readiness, and liveness probes all use the same server-owned `/healthz` endpoint.

Resource requests remain deliberately small because this workload validates the platform rather than generating production load. Both requests and limits are explicit so scheduling and later capacity changes remain reviewable.

## Container boundary

The application container:

- runs as a non-root numeric user and group;
- disables privilege escalation;
- drops every Linux capability;
- uses the runtime-default seccomp profile;
- uses a read-only root filesystem; and
- does not receive Kubernetes API credentials.

Istio injects `istio-proxy` because the existing `platform` namespace carries the injection label. Depending on the Kubernetes and Istio capabilities, the proxy appears either as a regular sidecar container or as a restartable native sidecar in the Pod's init-container list. The namespace's default `PeerAuthentication` requires `STRICT` mTLS for workload traffic.

## Ingress route

The namespaced Istio Gateway selects the ingress deployment through its `istio: ingress` label. It accepts HTTP on port 80 because TLS and public DNS ownership are not introduced yet.

The VirtualService sends both `/healthz` and application requests to the local `platform-api` Service. The health route has a short timeout. Application requests have bounded retries for connection failures, resets, and `503` responses.

Both clusters use the same manifests. Argo CD's native in-cluster destination keeps each application local to its cluster, while Traffic Manager resolves clients to one of the two public ingress addresses.

## Restricted GitOps permissions

The operator bootstrap adds a Role in `platform` for the Argo CD application controller. It can manage only:

- Services;
- Deployments;
- PodDisruptionBudgets;
- Istio Gateways; and
- Istio VirtualServices.

The `platform-workloads` AppProject accepts only this repository, the local `platform` namespace, and those same resource kinds. It does not permit Secrets, service accounts, Roles, RoleBindings, cluster-scoped resources, or other destinations.

Synchronization is manual and does not prune or self-heal. That keeps the first workload rollout observable before automated reconciliation is enabled.

## Bootstrap

I first confirm Terraform, Argo CD, and Istio are healthy. Then I load the ignored environment and run:

```bash
set -a
source .env
set +a

make gitops-status
make mesh-status
make workload-bootstrap
make workload-status
```

The workload bootstrap:

1. checks both Kubernetes APIs and operator permissions;
2. reads the two reserved ingress addresses and Traffic Manager name from Terraform outputs;
3. applies the restricted Role, AppProject, and Application in each cluster;
4. synchronizes the `platform-api` Application through namespace-safe Argo CD core mode;
5. waits for the Deployment and Argo CD health;
6. requires exactly two workload Pods with `istio-proxy` injected as either a regular or native sidecar;
7. confirms the namespace still enforces strict mTLS;
8. requests `/healthz` through each fixed ingress address; and
9. requests `/healthz` through Traffic Manager.

The final message is:

```text
The platform workload is ready through both ingresses and Traffic Manager.
```

## Manual checks

I can observe replica selection through either ingress:

```bash
curl "http://$(terraform -chdir=terraform output -raw gke_ingress_public_ip)/hostname"
curl "http://$(terraform -chdir=terraform output -raw aks_ingress_public_ip)/hostname"
```

I can verify the global route without printing its value separately:

```bash
curl "http://$(terraform -chdir=terraform output -raw traffic_manager_fqdn)/healthz"
```

The health request should return success. Repeated `/hostname` requests can reach different replicas inside the selected cluster.

## Ownership and safe reruns

Terraform continues to own Traffic Manager and both reserved public addresses. Helm owns the Istio control planes and ingress deployments. Argo CD owns the workload and namespaced routing objects.

Rerunning `make workload-bootstrap` reapplies the same bootstrap permissions and synchronizes the same Git revision. It does not create another application or broaden permissions.

The workload should be removed through its Argo CD Application before deleting its permissions. The Istio ingress Services must be deleted before destroying Terraform-managed public addresses.

## Remaining boundary

This workload proves an HTTP health path, but it does not yet provide:

- HTTPS certificates or a custom public domain;
- application-specific telemetry;
- service-level objectives or alerts;
- failure injection or progressive traffic shifting;
- a production container build and provenance chain; or
- business APIs and persistent data.

Those capabilities build on this verified route rather than being mixed into the first workload rollout.
