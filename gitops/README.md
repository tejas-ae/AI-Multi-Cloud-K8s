# GitOps layout

I keep the Argo CD bootstrap files here. The bootstrap script installs the pinned chart, uses Argo CD's native in-cluster target, and adds the `platform-bootstrap` application.

The first project is deliberately limited to its own namespace and `AppProject` resource. The chart does not create cluster roles, and I will add only the permissions required by each matching Git-managed workload. I keep incident-time traffic overrides outside this tree so reconciliation does not undo an approved temporary recovery action.
