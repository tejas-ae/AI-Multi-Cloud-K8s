# GKE availability incident walkthrough

This is the incident story I demonstrated on the live GKE and AKS portfolio environment. The failure was deliberate, bounded, reversible, and isolated from the health route.

## 1. Healthy baseline

Both platform deployments were ready behind their Istio ingress gateways. Azure Traffic Manager reported the GKE and AKS endpoints Enabled and Online with equal weights. Argo CD reported the workload and observability policies synchronized and healthy.

![Azure Traffic Manager showing GKE and AKS enabled, online, and weighted 50/50](images/evidence/traffic-manager-baseline-50-50.png)

This capture establishes the healthy active-active baseline: both cloud endpoints were enabled, online, and configured at equal weights before I introduced the controlled failure.

Prometheus, Grafana, Alertmanager, and Tempo were available only through local Kubernetes port-forwards. No monitoring dashboard or administrative service was exposed publicly.

![GKE cluster running with two nodes](images/evidence/gcp-gke-cluster-overview.png)

![Azure resource dashboard showing the AKS and Traffic Manager foundation](images/evidence/azure-multicloud-resources.png)

![Argo CD applications healthy and synchronized](images/evidence/argocd-applications-healthy.png)

![Grafana Prometheus overview during the healthy baseline](images/evidence/grafana-prometheus-overview.png)

## 2. Controlled failure

I explicitly confirmed the fault command before it modified the GKE VirtualService. The injected rule returned HTTP 503 only for application traffic; `/healthz` remained untouched so platform health and the controlled user-visible failure stayed distinct.

The bounded load generator completed, and the source-side Istio metric reached 8.91 HTTP 503 requests per second. The `PlatformApiAvailabilityDemo` rule fired and appeared through the internal Alertmanager route.

![Prometheus source-side HTTP 503 request rate](images/evidence/prometheus-http-503-rate.png)

![Prometheus availability alert transitioning to firing](images/evidence/prometheus-availability-alert.png)

![Grafana Alertmanager overview showing the incident signal](images/evidence/grafana-alertmanager-overview.png)

![Grafana Explore showing the active HTTP 503 load-test plateau](images/evidence/grafana-load-test-http-503.png)

![Prometheus showing repeated bounded load-test windows returning to zero](images/evidence/prometheus-load-test-windows.png)

## 3. Evidence-grounded analysis

The incident bundle referenced three evidence items:

- the Prometheus HTTP 503 rate;
- a Tempo trace through the GKE ingress; and
- the healthy AKS rollout.

The live Claude analyzer returned structured JSON with confidence 0.85. It recommended the only permitted action, `shift_traffic`, from GKE 50 / AKS 50 to GKE 30 / AKS 70. It also required human approval and recorded the exact 50/50 rollback state.

The deterministic validator checked the action type, evidence identifiers, evidence freshness, destination health, confidence threshold, maximum 20-point shift, approval flag, and rollback weights. A separate unsafe fixture was rejected.

![Offline incident-policy replay rejecting an unsafe remediation action](images/evidence/incident-unsafe-action-rejected.png)

This offline replay proves that the deterministic policy rejects an unauthorized action and permits only the bounded, human-approved traffic-shift workflow.

![Claude structured diagnosis with evidence identifiers, approval requirement, and rollback weights](images/evidence/claude-structured-diagnosis.png)

## 4. Human-approved remediation

Claude did not change the platform. I reviewed the proposed two-line Git diff and committed it. Terraform then produced a saved plan.

Before apply, a JSON assertion proved that the plan contained exactly two in-place updates: the GKE Traffic Manager endpoint weight changed to 30 and the AKS endpoint weight changed to 70. No resource creation, replacement, or deletion was permitted.

![Traffic Manager endpoints online after the approved GKE 30 and AKS 70 shift](images/evidence/traffic-manager-shift-30-70.png)

## 5. Recovery verification

After the approved apply, Traffic Manager reported both endpoints Enabled and Online at GKE 30 / AKS 70. Five independent health requests returned HTTP 200. The fault was inactive, both workload deployments rolled out successfully, and both ingress health routes passed.

![Post-load-test verification showing zero HTTP 503 rate, inactive fault, and healthy workloads](images/evidence/post-load-test-recovery.png)

## 6. Git rollback

I created a second reviewed Git commit that restored the tracked configuration to GKE 50 / AKS 50. A second saved Terraform plan was constrained to the two endpoint weight updates before apply. The final endpoint table returned both clouds to the healthy equal-weight baseline.

## What this proves

The demonstration proves a bounded AI-assisted incident workflow with observable failure, structured diagnosis, deterministic policy, human approval, infrastructure-as-code execution, recovery verification, and Git rollback.

It does not prove autonomous remediation, request-level weighted routing, cross-cluster Istio discovery, globally aggregated telemetry, high availability, or production retention. Azure Traffic Manager is DNS-based, so cached DNS decisions must be considered in any timing analysis.
