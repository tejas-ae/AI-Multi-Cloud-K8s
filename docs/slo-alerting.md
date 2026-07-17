# SLO evaluation and alert routing

I evaluate a focused set of service signals for `platform-api` independently in GKE and AKS. The rules turn the Istio request telemetry already collected by Prometheus into understandable availability, error-budget, and latency signals.

This is an operational proving boundary, not a contractual production SLO. Prometheus retains six hours of ephemeral data, so the longest evaluation window is six hours. A production version needs durable storage and a rolling compliance window before I use the results for release policy or business reporting.

## Objectives

| Signal | Objective | Good event | Bad event |
| --- | --- | --- | --- |
| Request success | 99.9% | An Istio destination request that does not return HTTP 5xx | An Istio destination request that returns HTTP 5xx |
| Request latency | p95 at or below 500 ms | The observed p95 is at or below 500 ms | The observed p95 is above 500 ms while traffic is present |

I use destination-reported Istio metrics so one request is counted once at the workload boundary. The availability error budget is `1 - 0.999`, or 0.1% failed requests. A burn rate of `1` consumes that budget at the objective's steady rate; a burn rate above `1` consumes it faster.

## Recording rules

The `platform-api-slos` PrometheusRule records request rate, HTTP 5xx rate, error ratio, and availability burn rate over 5-minute, 30-minute, 1-hour, and 6-hour windows. It also records p95 request duration over 5-minute and 30-minute windows.

The windows fit entirely inside the local retention boundary. The rule uses a small denominator floor when there is no traffic, which prevents division-by-zero values without fabricating an error. The latency alert separately requires a positive request rate.

Prometheus selects this rule through the same explicit repository label and `platform` namespace selector used for the PodMonitor. Argo CD can update the rule because its namespace Role and AppProject whitelist `PrometheusRule`; it still cannot manage monitoring Secrets, workloads, or cluster-scoped resources.

## Alerts

| Alert | Severity | Long window | Short window | Threshold | Hold time |
| --- | --- | --- | --- | --- | --- |
| `PlatformApiAvailabilityBudgetFastBurn` | critical | 1 hour | 5 minutes | Both burn rates above 14.4 | 2 minutes |
| `PlatformApiAvailabilityBudgetSlowBurn` | warning | 6 hours | 30 minutes | Both burn rates above 6 | 15 minutes |
| `PlatformApiLatencyObjectiveAtRisk` | warning | 30 minutes | 5 minutes | Both p95 values above 500 ms with traffic | 10 minutes |

The paired windows reduce noise: a short spike alone is insufficient, while a sustained slower regression still becomes visible. The availability thresholds follow the multi-window, multi-burn-rate pattern described in the Google SRE Workbook. I chose hold times that keep this small demo responsive while still requiring repeated evaluations.

These alerts describe user-visible symptoms. They do not guess at a cause. Metrics, traces, Kubernetes state, and later evidence collection provide the diagnostic context after an alert becomes active.

## Alertmanager boundary

Each cluster runs one Alertmanager replica behind a `ClusterIP` Service. Prometheus sends local alerts to it, and Alertmanager groups them by alert name, cluster, service, and severity.

The only receiver is `slo-null`. It intentionally has no email, webhook, or chat integration. This lets me validate rule-to-Alertmanager delivery, grouping, repeat intervals, and silencing without committing notification credentials or creating an accidental paging path. Adding a real receiver requires a separately reviewed Secret source, an owner, and a tested delivery destination.

## Runtime proof

I run:

```bash
make observability-bootstrap
make observability-status
```

For each cluster, the script now requires all of the following:

1. the live PrometheusRule contains the reviewed recording and alert names;
2. the Prometheus rules API reports both custom groups and every rule reports healthy evaluation;
3. Alertmanager is ready and its status API contains the `slo-null` route;
4. Prometheus still contains the platform API Istio request metric; and
5. Tempo still contains an Istio trace generated through that cluster's ingress.

The check proves configuration and data flow without deliberately breaking a live workload. Controlled failure injection will exercise pending, firing, recovery, and error-budget behavior later.

## What remains

Before treating these objectives as a production control, I still need durable metrics retention, a rolling compliance window, traffic-volume policy, real notification ownership, receiver credentials from a secret manager, alert delivery tests, dashboards for budget consumption, and documented response actions. I also need controlled failure experiments that prove the alerts fire and resolve at the intended thresholds.
