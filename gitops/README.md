# GitOps layout

I keep the Argo CD bootstrap files here. The bootstrap script installs the pinned chart, creates the controller identity, registers the local cluster, and adds the `platform-bootstrap` application.

The first project is deliberately limited to its own namespace and `AppProject` resource. I will widen its destination and resource rules only when I add the matching Git-managed workloads. I keep incident-time traffic overrides outside this tree so reconciliation does not undo an approved temporary recovery action.
