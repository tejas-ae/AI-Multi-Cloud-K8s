# GitOps layout

I keep the Argo CD bootstrap files here. The bootstrap script installs the pinned chart, resets any stale release values, uses Argo CD's native in-cluster target, confirms the settings ConfigMap exists, and runs core mode through a temporary namespace-scoped kubeconfig.

The first project is deliberately limited to its own namespace and `AppProject` resource. The chart does not create cluster roles, and I will add only the permissions required by each matching Git-managed workload. I keep incident-time traffic overrides outside this tree so reconciliation does not undo an approved temporary recovery action.

The `mesh` tree contains the pinned Istio values, operator bootstrap resources, restricted Argo CD project and application, and the namespace-scoped strict-mTLS policy. Helm owns the cluster-foundation releases; Argo CD owns only the policy kind explicitly granted in `platform`.

The `workloads` tree contains the stateless platform verification server, its Service and disruption budget, the Istio ingress route, and a separate restricted Argo CD boundary. The workload project cannot manage Secrets, RBAC, or cluster-scoped resources.

The `observability` tree keeps pinned values for Prometheus, the OpenTelemetry Collector, and Tempo alongside one restricted policy application. Helm owns the cluster-scoped monitoring foundation. Argo CD can manage only the `platform` namespace's `PodMonitor` and Istio `Telemetry` resources.
