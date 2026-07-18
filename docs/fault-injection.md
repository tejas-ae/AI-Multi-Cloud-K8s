# Controlled GKE latency fault

I use a short-lived Istio delay fault on GKE's application route for the incident demonstration. It leaves the `/healthz` route untouched, targets only the verification workload, and has no AKS effect.

The fault script will not change a cluster unless I explicitly set `CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s`. It first verifies the expected VirtualService shape, then adds a three-second delay to the application route. Clearing the fault removes exactly that field and restores the Git-managed route.

```bash
CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s make fault-inject
make fault-load
make fault-capture
CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s make fault-clear
make fault-status
```

`fault-load` sends traffic only to the GKE ingress for a bounded duration. `fault-capture` reads the ingress/source-side p95 latency, which includes the injected delay, and prints whether the short-window demo alert is firing. It does not write evidence, modify Alertmanager, or change traffic weights.

I clear the fault before reviewing any traffic proposal. The later traffic change is a separate Git review and Terraform apply, not a consequence of this script.
