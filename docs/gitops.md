# GitOps delivery

I run an Argo CD control plane in each cluster. Both instances pull from this repository, and each registers only its own cluster through `https://kubernetes.default.svc`.

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

The bootstrap uses Argo CD chart `9.7.1`, keeps the server as `ClusterIP`, disables browser exec, notifications, Dex, and ApplicationSet until I need them, and creates a `platform-bootstrap` application in each cluster.

The controller uses a dedicated `argocd-manager` service account in `kube-system`. At this point it can discover the API and reconcile only the bootstrap `AppProject` in the `argocd` namespace. It is not a user kubeconfig or a cloud credential, and the service-account token stays inside the receiving cluster. I will add narrower workload permissions with each Git-managed component instead of granting broad control up front.

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
