# AI Multi-Cloud K8s

I’m building a multi-cloud Kubernetes reliability platform across GKE and AKS. The platform combines GitOps, Istio, OpenTelemetry, SLO-based alerting, evidence-grounded Claude analysis, policy checks, human approval, progressive traffic shifting, verification, and rollback.

## What I have built

- A macOS preflight that checks tools, identities, quotas, budgets, versions, and repository hygiene
- Terraform modules for GKE, AKS, isolated networking, managed identities, fixed ingress addresses, and Azure Traffic Manager
- Private GKE workers and IP-restricted Kubernetes API endpoints
- Entra-backed AKS access with local accounts and Run Command disabled
- Pinned Kubernetes and Terraform provider versions
- A sanitized plan reviewer with an exact 24-resource allowlist
- CI checks for Terraform, shell scripts, secrets, unsafe files, and executable modes

## Architecture

- Terraform owns cloud infrastructure.
- GitHub Actions handles CI and immutable image publication.
- Argo CD is installed in each cluster and owns local delivery from Git.
- Istio will provide service identity, mTLS, failure injection, and traffic shifting.
- Prometheus, OpenTelemetry, Tempo, and Grafana will provide incident evidence.
- Claude will return schema-validated diagnoses tied to supplied evidence IDs.
- OPA and human approval will gate remediation.
- Every traffic change will be verified and rolled back when SLOs get worse.

## Guardrails

I keep cloud identifiers and credentials in an ignored `.env`. Terraform state lives in a versioned GCS backend, raw plans stay local, and the repository check blocks state, plans, kubeconfigs, private keys, and private evidence.

The main workflow is:

```bash
make preflight
make tf-init
make tf-validate
make tf-plan
make tf-review
```

`tf-apply` and `tf-destroy` both require explicit confirmation values.

## Status

The workstation and cloud readiness gate passes with zero failures. The Terraform foundation validates, the provider lock is committed, and the creation plan passes the resource-scope and security assertions.

The cloud foundation is live. I am using Argo CD as the pull-based delivery layer before adding the mesh, services, and observability stack.
