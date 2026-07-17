# Observability foundation

I run a small, independent observability stack in each cluster. Prometheus stores metrics, the OpenTelemetry Collector receives Istio spans, Tempo stores traces, and Grafana provides a local dashboard. Nothing in this boundary sends telemetry or credentials between clouds.

This is an evidence foundation rather than a production retention design. It proves that each cluster can discover the platform workload, collect mesh request metrics, receive distributed traces, and expose those signals to an operator before I add SLO evaluation and incident automation.

## Topology and ownership

Each cluster has an `observability` namespace with three pinned Helm releases:

| Release          | Chart version                       | Responsibility                                                                  |
| ---------------- | ----------------------------------- | ------------------------------------------------------------------------------- |
| `observability`  | `kube-prometheus-stack` `87.17.0`   | Prometheus Operator, Prometheus, Grafana, kube-state-metrics, and node exporter |
| `otel-collector` | `opentelemetry-collector` `0.165.0` | OTLP ingestion, Kubernetes metadata enrichment, batching, and trace export      |
| `tempo`          | `tempo` `2.2.3`                     | Single-binary local trace storage and search                                    |

Helm owns these foundations because the charts install CRDs, ClusterRoles, admission resources, and other cluster-scoped objects. I do not grant Argo CD that cluster-wide surface.

Argo CD owns only two resources in `platform`:

- a `PodMonitor` that discovers the `platform-api` sidecar metrics port; and
- an Istio `Telemetry` resource that selects the named OpenTelemetry tracing provider.

The matching Role and AppProject permit only `PodMonitor` and `Telemetry` in `platform`. They cannot manage Secrets, workloads, RBAC, other namespaces, or cluster-scoped resources.

## Metrics path

The `PodMonitor` selects Pods labeled `app.kubernetes.io/name=platform-api` and scrapes the injected proxy's `http-envoy-prom` port at `/stats/prometheus` every 15 seconds.

Prometheus selects only PodMonitors with the repository's explicit telemetry label and only from the `platform` namespace. The bootstrap sets an external `cluster` label to `gke` or `aks`, so the same query remains attributable if the data is aggregated later.

The first runtime assertion queries for `istio_requests_total` with `destination_service_name="platform-api"`. A successful Pod rollout alone is not enough; the status command fails if Prometheus has not ingested the workload request metric.

## Trace path

Istiod declares a provider named `otel-tracing` that sends OTLP over the cluster network to `otel-collector.observability.svc.cluster.local:4317`. The `platform-tracing` policy enables that provider in `platform` and samples 100 percent of requests during this low-volume verification boundary.

The Collector runs one replica with a traces-only pipeline:

1. receive OTLP over gRPC or HTTP;
2. enforce a memory limit;
3. add Kubernetes namespace, Pod, Deployment, node, and cluster metadata;
4. batch spans; and
5. export OTLP to the local Tempo Service.

Tempo uses local ephemeral storage with six-hour retention. Prometheus also keeps six hours of data on ephemeral storage. Restarting or replacing the storage Pods can discard evidence, which is acceptable for this verification boundary but not for a production incident archive.

## Capacity and exposure

Prometheus, Tempo, the Collector, Grafana, the operator, and metadata exporters all have explicit requests and limits. Prometheus, Tempo, and the Collector each run one replica to fit the reviewed two-node cluster baseline. The monitoring data plane is therefore not highly available yet.

All Services remain `ClusterIP`. There is no public Grafana, Prometheus, Collector, or Tempo endpoint. Grafana uses its chart-generated administrator Secret, and the repository never stores or prints the generated password.

Alertmanager and the default Prometheus rules are disabled. SLO rules and alert routing need an explicit design instead of inheriting a large generic ruleset before ownership and notification paths exist.

## Bootstrap

I load the same ignored environment used by the earlier boundaries, reconcile Istio so the live control plane has the tracing provider, and then install observability:

```bash
set -a
source .env
set +a

make mesh-bootstrap
make workload-status
make observability-bootstrap
make observability-status
```

The bootstrap performs these checks in each cluster:

1. confirm API access and the cluster-scoped permissions required by the Helm charts;
2. require the live Istio configuration to contain the reviewed `otel-tracing` provider;
3. create the `observability` namespace idempotently;
4. install the three pinned Helm releases and wait for their resources;
5. apply the restricted Role, AppProject, and Application;
6. synchronize the policy through namespace-safe Argo CD core mode;
7. wait for Prometheus, Grafana, exporters, Tempo, and the Collector;
8. verify the exact tracing provider, sample rate, and metrics endpoint in the live policy;
9. send requests through the cluster's fixed ingress address;
10. query Prometheus for the platform request metric; and
11. query Tempo for at least one trace.

The status command repeats the rollout, policy, metrics, and trace assertions. It generates a small amount of traffic so the evidence check does not depend on a recent manual request.

## Grafana access

I keep the dashboard local to my workstation. For GKE I run:

```bash
make observability-gke-ui
```

For AKS I run:

```bash
make observability-aks-ui
```

While the command is running, Grafana is available at `http://127.0.0.1:3000`. The username is `admin`. I retrieve the generated password directly from the selected cluster without copying it into a file:

```bash
kubectl \
  --context "$GKE_CONTEXT" \
  --namespace observability \
  get secret observability-grafana \
  --output jsonpath='{.data.admin-password}' |
base64 --decode
echo
```

I substitute `$AKS_CONTEXT` to access the other independent Grafana instance. If local port 3000 is occupied, I set `GRAFANA_LOCAL_PORT` before running the Make target.

## Safe reruns and remaining boundary

The bootstrap uses `helm upgrade --install`, declarative Kubernetes apply, and manual Argo CD synchronization. A safe rerun reconciles the same pinned chart versions and policy. A chart upgrade requires updating the values, version constants, CI rendering, and this document together.

This boundary does not yet include durable object storage, highly available telemetry backends, TLS or single sign-on for Grafana, application-native instrumentation, recording rules, SLOs, alert routing, logs, or cross-cluster aggregation. Those additions should follow the same explicit ownership and credential boundaries.
