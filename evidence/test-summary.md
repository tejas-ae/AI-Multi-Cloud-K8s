# Demonstration test summary

This file records the successful live portfolio demonstration without cloud identifiers, credentials, public addresses, raw plans, or dashboard exports.

| Check | Result |
| --- | --- |
| GKE and AKS workload readiness | Deployments rolled out and both ingress health routes passed |
| Traffic Manager baseline | Both endpoints Enabled and Online at 50/50 |
| GKE-only application fault | HTTP 503 injected on the application route; `/healthz` remained outside the fault path |
| Bounded traffic generation | Completed |
| Prometheus source-side 503 rate | 8.91 requests/second during the controlled fault |
| `PlatformApiAvailabilityDemo` | Fired |
| Alertmanager route | Received the firing alert through the internal SLO route |
| Fault recovery | Fault cleared and status returned inactive |
| Offline incident replay | Valid recommendation accepted |
| Unsafe incident fixture | Rejected as expected |
| Live Claude response | Structured response passed policy with confidence 0.85 |
| Evidence references | Prometheus 503 rate, Tempo ingress trace, and AKS rollout health |
| Human-approved proposal | GKE 50 / AKS 50 to GKE 30 / AKS 70 |
| Terraform safety review | Only the two Traffic Manager endpoint weights changed in place |
| Recovery verification | Five HTTP 200 responses; both endpoints remained Enabled and Online |
| Git rollback | A separate reviewed commit restored GKE 50 / AKS 50 |
| Private UI access | Argo CD, Grafana, Prometheus, and Alertmanager reached through local port-forwards |

Exact detection, review, synchronization, and recovery durations were not captured with a single shared clock during this run, so I do not publish estimated timings. A future run will record those timestamps automatically.

The complete sequence and approval boundary are documented in [the incident walkthrough](../docs/incident-walkthrough.md) and [the demo runbook](../docs/demo-runbook.md). Screenshots, video, and cost exports are published only after sanitization.
