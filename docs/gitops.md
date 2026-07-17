# GitOps delivery

I run an Argo CD control plane in each cluster. Both instances pull from this repository and use the native in-cluster target at `https://kubernetes.default.svc`.

This keeps the Kubernetes API boundary simple: each public API server remains limited to my operator address, and neither cloud needs cross-cloud administrator access. The repository is still the shared desired state; the controllers reconcile their local copy of it.

## Bootstrap

After retrieving both kubeconfigs and converting the AKS one with `kubelogin`, I load my ignored environment file and run:

```bash
set -a
source .env
set +a

make gitops-bootstrap
make gitops-status
```

The bootstrap uses Argo CD chart `9.7.1`, keeps the server as `ClusterIP`, disables browser exec, notifications, and Dex, and creates a `platform-bootstrap` application in each cluster. I keep the bundled ApplicationSet controller available for the generated applications added later. The bootstrap does not create a service-account token secret or store a Kubernetes credential in Argo CD.

The application controller uses its ordinary projected workload token. The chart does not create cluster roles, and RBAC-aware discovery skips APIs that the controller cannot list. The bootstrap project can reconcile only its own `AppProject` in the `argocd` namespace. I will add the exact destination and resource permissions with each Git-managed component instead of granting broad control up front.

The source repository is public, so the controller does not need a GitHub token to read it. I start with manual synchronization and no pruning or self-healing. A later application can opt into automatic sync only after its health and rollback behaviour are tested.

## Access

I leave the Argo CD server private and use a local port-forward when I need the UI:

```bash
make argocd-gke-ui
# or
make argocd-aks-ui
```

The UI is available at `https://localhost:8080` while the command is running.

## Ownership

Terraform owns cloud networks, clusters, identities, public ingress addresses, and Traffic Manager. Argo CD owns Git-managed Kubernetes workloads. The incident controller will own only temporary traffic overrides, and permanent routing policy changes return through Git.
