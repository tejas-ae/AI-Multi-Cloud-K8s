# GKE availability incident walkthrough

This is the incident story I demonstrated on the live GKE and AKS portfolio environment. The failure was deliberate, bounded, reversible, and isolated from the health route.

## 1. Healthy baseline

Both platform deployments were ready behind their Istio ingress gateways. Azure Traffic Manager reported the GKE and AKS endpoints Enabled and Online with equal weights. Argo CD reported the workload and observability policies synchronized and healthy.

Prometheus, Grafana, Alertmanager, and Tempo were available only through local Kubernetes port-forwards. No monitoring dashboard or administrative service was exposed publicly.

## 2. Controlled failure

I explicitly confirmed the fault command before it modified the GKE VirtualService. The injected rule returned HTTP 503 only for application traffic; `/healthz` remained untouched so platform health and the controlled user-visible failure stayed distinct.

The bounded load generator completed, and the source-side Istio metric reached 8.91 HTTP 503 requests per second. The `PlatformApiAvailabilityDemo` rule fired and appeared through the internal Alertmanager route.

## 3. Evidence-grounded analysis

The incident bundle referenced three evidence items:

- the Prometheus HTTP 503 rate;
- a Tempo trace through the GKE ingress; and
- the healthy AKS rollout.

The live Claude analyzer returned structured JSON with confidence 0.85. It recommended the only permitted action, `shift_traffic`, from GKE 50 / AKS 50 to GKE 30 / AKS 70. It also required human approval and recorded the exact 50/50 rollback state.

The deterministic validator checked the action type, evidence identifiers, evidence freshness, destination health, confidence threshold, maximum 20-point shift, approval flag, and rollback weights. A separate unsafe fixture was rejected.

## 4. Human-approved remediation

Claude did not change the platform. I reviewed the proposed two-line Git diff and committed it. Terraform then produced a saved plan.

Before apply, a JSON assertion proved that the plan contained exactly two in-place updates: the GKE Traffic Manager endpoint weight changed to 30 and the AKS endpoint weight changed to 70. No resource creation, replacement, or deletion was permitted.

## 5. Recovery verification

After the approved apply, Traffic Manager reported both endpoints Enabled and Online at GKE 30 / AKS 70. Five independent health requests returned HTTP 200. The fault was inactive, both workload deployments rolled out successfully, and both ingress health routes passed.

## 6. Git rollback

I created a second reviewed Git commit that restored the tracked configuration to GKE 50 / AKS 50. A second saved Terraform plan was constrained to the two endpoint weight updates before apply. The final endpoint table returned both clouds to the healthy equal-weight baseline.

## What this proves

The demonstration proves a bounded AI-assisted incident workflow with observable failure, structured diagnosis, deterministic policy, human approval, infrastructure-as-code execution, recovery verification, and Git rollback.

It does not prove autonomous remediation, request-level weighted routing, cross-cluster Istio discovery, globally aggregated telemetry, high availability, or production retention. Azure Traffic Manager is DNS-based, so cached DNS decisions must be considered in any timing analysis.
