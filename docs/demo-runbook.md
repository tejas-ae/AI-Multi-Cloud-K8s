# Portfolio demonstration runbook

I use this runbook to reproduce one bounded GKE availability incident, an evidence-grounded Claude recommendation, a human-approved traffic shift, recovery, and Git rollback.

## 1. Capture the healthy baseline

I open Argo CD, Grafana, Prometheus, and Alertmanager through local port-forwards. I record healthy applications, empty alerts, both workload rollouts, and Traffic Manager at GKE 50 / AKS 50.

The primary fault query is:

```promql
sum(rate(istio_requests_total{reporter="source",response_code="503"}[1m]))
```

## 2. Run the controlled incident

```bash
CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s make fault-inject
make fault-load
make fault-capture
```

I record the 503 spike, the firing `PlatformApiAvailabilityDemo` alert, the Alertmanager group, and the corresponding Grafana and Tempo views.

## 3. Clear the fault

```bash
CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s make fault-clear
make fault-status
```

The traffic recommendation remains a separate review step; clearing the experiment never changes public weights.

## 4. Validate the decision boundary

```bash
make incident-replay
make incident-proposal
make incident-reject-unsafe
```

For the optional live model call, I load the key only into the current terminal, run `make incident-claude`, and immediately unset it. I record only the structured, policy-approved result.

## 5. Review and apply the traffic proposal

I commit the reviewed change to `config/traffic-weights.env`, pull it locally, and create a saved Terraform plan. Before apply, I query the plan JSON and require exactly two in-place Traffic Manager endpoint updates with no additions or deletions.

The apply command still requires a human confirmation value:

```bash
CONFIRM_APPLY=AI-Multi-Cloud-K8s make tf-apply
```

I record the 30/70 endpoint table, five HTTP 200 health checks, fault status, workload rollouts, and ingress health.

## 6. Roll back through Git

I commit a second change restoring `config/traffic-weights.env` to 50/50. I repeat the saved-plan assertion, apply with explicit confirmation, and record the final equal-weight endpoint table.

## 7. Publish sanitized evidence

I publish only:

- healthy, firing, and recovered monitoring views;
- the structured Claude result without prompts, keys, or account metadata;
- policy acceptance and unsafe-fixture rejection;
- the reviewed traffic-weight commits;
- sanitized plan summaries showing only action counts and intended resources;
- recovery and rollback endpoint tables; and
- actual cost and cleanup verification.

I do not publish public addresses, project or subscription identifiers, kubeconfigs, generated passwords, raw Terraform plans, state, authorization ranges, or unredacted terminal history.

## 8. Destroy the environment

After exporting the final evidence, I remove Kubernetes LoadBalancer Services, wait for the cloud load balancers to disappear, run the confirmed Terraform destroy, and query both providers for remaining project resources. Cleanup is part of the demonstration, not an optional follow-up.
