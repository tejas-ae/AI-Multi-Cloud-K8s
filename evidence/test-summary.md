# Demonstration test summary

This summary records the successful controlled-fault validation on the live portfolio environment. It contains no cloud identifiers, credentials, public addresses, or raw dashboard exports.

| Check | Result |
| --- | --- |
| GKE-only application-route fault | Injected as HTTP 503; health route remained outside the fault path |
| Bounded load generation | Completed |
| Prometheus source-side 503 rate | 8.91 requests/second during the controlled fault |
| `PlatformApiAvailabilityDemo` | Fired |
| Alertmanager route | Received the firing alert through the internal route |
| Fault recovery | Route cleared successfully; status reported inactive |
| Argo CD, Grafana, Prometheus | Reached through local private port-forwards |
| Incident-policy replay | Valid proposal accepted; unsafe action rejected |

The full demonstration runbook is in [the demo runbook](../docs/demo-runbook.md). Screenshots and recordings are added only after they have been sanitized.
