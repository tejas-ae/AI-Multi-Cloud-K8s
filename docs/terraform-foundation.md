# Terraform foundation

I use Terraform to create the GKE and AKS foundation, isolated networks, managed identities, fixed ingress addresses, and Azure Traffic Manager. Applications, GitOps, the mesh, and observability come after both clusters are healthy.

## Design choices

- I pin exact Kubernetes patches instead of accepting provider-selected versions.
- I restrict both public API endpoints to one operator IPv4 `/32`.
- I keep GKE workers private behind Cloud NAT.
- I use Entra and Azure RBAC for AKS and disable local accounts.
- I disable AKS Run Command.
- I cap both node pools at two workers to stay inside the verified quotas.
- I keep raw plans local and review a sanitized view.

## Workflow

I refresh the version list whenever I recreate the clusters:

```bash
make k8s-versions
```

My validation sequence is:

```bash
set -a
source .env
set +a

make preflight
make tf-init
make tf-fmt
make tf-validate
make tf-plan
make tf-review
```

The reviewer requires the exact 24-resource create allowlist. It also checks versions, private workers, API allowlist counts, node ceilings, Entra RBAC, disabled AKS administrative paths, weighted routing, and `/healthz` monitoring. It never prints private IDs, addresses, or CIDR values.

The foundation includes:

- One zonal GKE cluster with two `e2-standard-4` workers
- One AKS cluster with two `Standard_D2_v4` workers
- One GCP VPC, subnet, router, and Cloud NAT
- One Azure VNet and subnet
- Two fixed ingress addresses
- One weighted Traffic Manager profile
- The identities and role assignments required by both clusters

It does not create databases, GPUs, persistent application disks, or private cross-cloud networking.

## Apply and access

I apply only the saved plan that passed review:

```bash
CONFIRM_APPLY=AI-Multi-Cloud-K8s make tf-apply
```

AKS uses my active Azure identity:

```bash
az aks get-credentials --resource-group "$AZURE_RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
```

The local AKS admin credential path is intentionally unavailable.

## Cleanup

I remove Kubernetes `LoadBalancer` Services before destroying the cloud foundation, then run:

```bash
CONFIRM_DESTROY=AI-Multi-Cloud-K8s make tf-destroy
```
