# AI Multi-Cloud K8s

I built a multi-cloud Kubernetes reliability demonstration across GKE and AKS. It combines infrastructure as code, GitOps delivery, service-mesh telemetry, SLO alerting, evidence-grounded Claude analysis, deterministic policy checks, human approval, traffic shifting, recovery verification, and Git-based rollback.

## Demonstrated result

I ran one bounded GKE availability incident from detection through rollback:

| Stage | Measured result |
| --- | --- |
| Controlled fault | GKE application traffic returned HTTP 503 while `/healthz` remained healthy |
| Prometheus signal | Source-side HTTP 503 rate reached 8.91 requests/second |
| Alert | `PlatformApiAvailabilityDemo` fired and reached Alertmanager |
| Claude analysis | Live structured response passed policy with 0.85 confidence |
| Recommendation | Shift Traffic Manager from GKE 50 / AKS 50 to GKE 30 / AKS 70 |
| Approval boundary | The analyzer produced a proposal; a human reviewed and committed the Git change |
| Recovery | Traffic Manager returned HTTP 200 five times and both endpoints remained Online |
| Rollback | A second reviewed Git commit restored GKE 50 / AKS 50 |

The repository contains sanitized fixtures and an offline replay, so the decision path can be tested without cloud credentials or an Anthropic API key.

## What I built

- Terraform modules for GKE, AKS, isolated networking, managed identities, fixed ingress addresses, and Azure Traffic Manager
- Private GKE workers and IP-restricted Kubernetes API endpoints
- Entra-backed AKS access with local accounts and Run Command disabled
- Independent Argo CD installations with restricted in-cluster delivery
- Separate Istio meshes with strict workload mTLS and redundant ingress
- A Git-managed verification workload served through both clouds and Traffic Manager
- Per-cluster Prometheus, Alertmanager, OpenTelemetry Collector, Tempo, and Grafana stacks
- Git-managed metrics discovery, tracing policy, SLO rules, and alert routing
- A controlled GKE-only HTTP 503 experiment with an explicit confirmation guard
- A live Claude analyzer that requires structured output and sends only a sanitized incident bundle
- A deterministic validator that limits actions, evidence, confidence, traffic delta, approval, and rollback data
- A human-approved Git and Terraform remediation path with a tested Git rollback
- GitHub Actions checks for rendered manifests, Helm values, shell quality, repository safety, and offline incident-policy replay

## Architecture

- Terraform owns cloud infrastructure and Traffic Manager weights.
- GitHub Actions validates the delivery configuration and incident-policy fixtures.
- Argo CD owns cluster-local workload and policy delivery from Git.
- Istio provides local service identity, strict mTLS, ingress routing, metrics, and traces.
- Prometheus and Alertmanager detect the controlled availability failure.
- Grafana and Tempo support investigation without cross-cloud telemetry credentials.
- Claude receives bounded evidence and returns a recommendation, never an executable command.
- Deterministic policy validation and human review gate every durable change.
- Git records both the remediation weights and the rollback weights.

This portfolio MVP uses independent service meshes and per-cluster observability stacks. It does not claim cross-cluster Istio service discovery, Thanos aggregation, autonomous remediation, or production-grade telemetry retention.

## Safety boundaries

I keep cloud identifiers and credentials in an ignored `.env`. Terraform state lives in a versioned GCS backend, raw plans stay local, and repository verification blocks state, saved plans, kubeconfigs, private keys, and private evidence.

The analyzer cannot patch Kubernetes, call Terraform, merge Git, or modify cloud resources. Terraform apply and destroy require explicit confirmation values. The fault script also requires a separate exact confirmation value and targets only the GKE application route.

## Reproduce the policy decision locally

```bash
make incident-replay
make incident-proposal
make incident-reject-unsafe
```

The accepted fixture produces a bounded traffic shift with recorded rollback weights. The unsafe fixture exits nonzero.

The live Claude path is optional and keeps the key only in the current shell:

```zsh
read -s "ANTHROPIC_API_KEY?Paste Anthropic API key (hidden): "
echo
export ANTHROPIC_API_KEY
make incident-claude
unset ANTHROPIC_API_KEY
```

## Repository guide

- [End-to-end incident walkthrough](docs/incident-walkthrough.md)
- [Portfolio demonstration runbook](docs/demo-runbook.md)
- [Controlled fault design](docs/fault-injection.md)
- [Incident-response guardrails](docs/incident-response.md)
- [Live Claude analyzer](docs/claude-analyzer.md)
- [SLO and Alertmanager design](docs/slo-alerting.md)
- [Observability implementation](docs/observability.md)
- [GitOps design](docs/gitops.md)
- [Sanitized test summary](evidence/test-summary.md)

## Current status

The cloud foundation, delivery layer, workload, observability stack, controlled incident, live Claude analysis, human-approved traffic shift, recovery verification, and Git rollback have all been exercised. The remaining portfolio work is publishing sanitized visual evidence and actual cost measurements, followed by mandatory destruction and verification of every billable resource.
