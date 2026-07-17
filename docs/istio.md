# Istio mesh foundation

I run a separate Istio sidecar mesh in each cluster. The control planes use the same pinned release and configuration shape, but they have independent trust domains, certificate authorities, ingress Services, and failure boundaries.

## Why the meshes are independent

The current network design does not include private cross-cloud connectivity. Joining the clusters into one trust domain would add remote secrets, cross-cluster discovery, east-west gateways, and a larger credential boundary before any workload needs them.

Independent meshes provide the controls needed now:

- workload identity inside each cluster;
- strict mutual TLS for opted-in workloads;
- consistent traffic-management APIs;
- a local ingress failure boundary; and
- a clean path to later multi-cluster federation if the network and trust requirements justify it.

GKE uses `gke.ai-multicloud.local` as its trust domain, and AKS uses `aks.ai-multicloud.local`. A service identity issued in one cloud is not automatically trusted by the other.

## Release and installation model

I pin Istio `1.30.3`. Istio 1.30 supports Kubernetes 1.35, which is the Kubernetes minor running in both clusters.

The operator bootstrap installs three Helm releases in each cluster:

1. `istio-base` installs the CRDs and cluster-scoped base resources.
2. `istiod` installs the local control plane.
3. `istio-ingress` installs the public ingress data plane.

These cluster-foundation releases require cluster-scoped installation permissions, so the operator installs them with Helm. Argo CD does not receive wildcard cluster access. Argo CD owns only the namespace-scoped mesh security policy through a dedicated Role and AppProject.

## Availability and capacity

Each cluster runs:

- two `istiod` replicas;
- two ingress gateway replicas;
- a gateway PodDisruptionBudget requiring one available replica; and
- bounded HorizontalPodAutoscalers with minimum and maximum both set to two.

The fixed replica count matches the two-worker cluster baseline and prevents the mesh from exceeding the quota and cost assumptions already reviewed in Terraform. Resource requests are lower than Istio's large-cluster defaults but still explicit, which makes scheduling and later capacity review visible.

## Ingress address ownership

Terraform owns the two public IP reservations. The Istio bootstrap reads those addresses from Terraform outputs and asks each cloud controller to attach the matching address to its `istio-ingress` Service.

GKE uses both the reserved IPv4 value and the named-address annotation. It also requests the backend-service implementation of the external Layer 4 load balancer. AKS uses the reserved IPv4 value, public-IP name, and node-resource-group annotation.

The status command fails if a Service receives an address different from its Terraform reservation. Traffic Manager can remain degraded until a later workload and route return success from `/healthz`; installing the gateway alone does not create that application route.

## Workload enrollment and strict mTLS

The bootstrap creates an empty `platform` namespace with `istio-injection=enabled`. New Pods created there receive sidecars automatically.

A Git-managed `PeerAuthentication` named `default` requires `STRICT` mutual TLS in that namespace. I deliberately avoid a root-namespace policy at this point because Kubernetes and Argo CD system workloads are not enrolled in the mesh.

Strict mTLS requires both ends of a service connection to participate in the mesh. I therefore deploy application workloads into `platform` only after confirming sidecar injection, and I restart existing workloads after adding an injection label.

The mesh configuration also declares an OpenTelemetry tracing provider at the internal Collector Service. A namespaced `Telemetry` resource enables that provider only for `platform`; declaring the provider does not broaden mesh policy or expose a public telemetry endpoint.

## Least-privilege Argo CD access

The operator bootstrap creates one Role in `platform`. It permits the Argo CD application controller to manage only `PeerAuthentication` resources in that namespace. The matching AppProject permits:

- one source repository;
- one destination namespace;
- the native in-cluster API target; and
- one namespaced Istio resource kind.

The `mesh-security` Application starts with manual synchronization and no pruning or self-healing. This makes the initial policy transition explicit and observable.

## Bootstrap

I first confirm the Terraform foundation and Argo CD are healthy:

```bash
set -a
source .env
set +a

make gitops-status
make mesh-bootstrap
make mesh-status
```

The bootstrap checks both API contexts and cluster-scoped operator permissions before changing either cluster. It then installs GKE first and AKS second, waits for the deployments and ingress addresses, applies the narrow Argo CD Role, and synchronizes the strict-mTLS policy.

The expected result in each cluster is:

- all three Helm releases are deployed at `1.30.3`;
- two `istiod` Pods are running;
- two ingress Pods are running;
- the ingress Service address matches the Terraform output;
- `platform` has sidecar injection enabled;
- the default `PeerAuthentication` is `STRICT`; and
- the `mesh-security` Application is `Synced` and `Healthy`.

## Safe reruns

The bootstrap uses `helm upgrade --install` and declarative Kubernetes applies. A rerun reconciles the pinned values instead of creating additional releases.

I do not change the trust-domain value on a live mesh as a routine rerun. A trust-domain change alters workload identity and must be treated as a migration with compatibility aliases, certificate rotation, and explicit traffic verification.

## Workload verification

Before deploying the platform verification workload, I run:

```bash
make mesh-status
```

The workload bootstrap then adds an end-to-end check that proves:

- both Pods contain an `istio-proxy` container;
- the namespace remains under the strict mTLS policy;
- each ingress address serves the application health route; and
- Traffic Manager can reach the same health route.

The complete workload boundary and commands are in [Platform verification workload](platform-workload.md).

Metrics discovery, tracing policy, and the local evidence stores are described in [Observability foundation](observability.md).

## Upgrade boundary

The version is pinned in the bootstrap script, CI rendering, and documentation. An upgrade must update all three together, render both charts, review release notes and Kubernetes compatibility, and use a controlled control-plane/data-plane rollout. I do not let Helm select a newer minor implicitly.
