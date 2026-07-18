# Portfolio demonstration runbook

I use this short runbook to record one bounded GKE incident and recovery. It is deliberately manual: the fault is confirmed locally, remediation remains a reviewed Git diff, and recovery is verified before any cleanup.

## Baseline

I first open the local, private port-forwards for one cluster:

```bash
make argocd-gke-ui
make observability-gke-ui
kubectl --context "$GKE_CONTEXT" --namespace observability \
  port-forward service/observability-kube-prometh-prometheus 9090:9090
kubectl --context "$GKE_CONTEXT" --namespace observability \
  port-forward service/observability-kube-prometh-alertmanager 9093:9093
```

I capture the healthy Argo CD application list, Grafana Explore, the Prometheus query below, and Alertmanager with no firing alerts:

```promql
sum(rate(istio_requests_total{reporter="source",response_code="503"}[1m]))
```

## Controlled incident and recovery

In a separate terminal, I inject only the GKE application-route fault, generate bounded traffic, and wait for the one-minute alert window plus Alertmanager grouping:

```bash
CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s make fault-inject
make fault-load
make fault-capture
```

While the fault is active, I record the 503 query, the `PlatformApiAvailabilityDemo` alert in Prometheus and Alertmanager, and the Grafana graph. I then restore the Git-managed route and confirm recovery:

```bash
CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s make fault-clear
make fault-status
make workload-status
```

## Diagnosis and approval boundary

I run the deterministic incident replay after capturing the runtime evidence:

```bash
make incident-replay
make incident-proposal
make incident-reject-unsafe
```

The proposal is only a reviewable change to `config/traffic-weights.env`; it is not applied by the analyzer. I record the proposed diff, rejection of the unsafe fixture, and the explicit rollback weights.

## Evidence checklist

I publish only sanitized evidence:

- healthy and firing Alertmanager views;
- Prometheus and Grafana views of the 503 spike;
- Argo CD healthy/synced applications before and after recovery;
- terminal output from `fault-capture`, `fault-status`, and the incident-policy commands;
- the reviewed traffic-weight diff and rollback values; and
- final cleanup verification and actual cost.

I do not publish public IPs, subscription or project identifiers, kubeconfigs, generated passwords, raw plans, or unredacted screenshots.
