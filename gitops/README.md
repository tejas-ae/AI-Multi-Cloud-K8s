# GitOps layout

I keep the Argo CD bootstrap files here. The bootstrap script installs the pinned chart, resets any stale release values, uses Argo CD's native in-cluster target, confirms the settings ConfigMap exists, and runs core mode through a temporary namespace-scoped kubeconfig.

The first project is deliberately limited to its own namespace and `AppProject` resource. The chart does not create cluster roles, and I will add only the permissions required by each matching Git-managed workload. I keep incident-time traffic overrides outside this tree so reconciliation does not undo an approved temporary recovery action.
