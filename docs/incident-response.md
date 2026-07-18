# Controlled incident response

I keep the incident workflow intentionally narrow. A diagnosis may recommend a small public traffic-weight shift from one healthy cloud to the other, but it cannot patch Kubernetes, call Terraform, merge Git, or bypass review.

## Local replay

The repository includes a sanitized GKE latency incident and a recorded structured diagnosis. I can validate the full decision without cloud access or an API key:

```bash
make incident-replay
make incident-proposal
make incident-reject-unsafe
```

The successful replay proves that the recommendation references every recent evidence item, identifies the current source and healthy destination, stays inside a 20-point traffic limit, records the exact rollback weights, and requires human approval. The unsafe fixture proves that an unsupported action, incomplete evidence, excessive weight change, or missing approval is rejected.

## Approval boundary

The only approved action is `shift_traffic`. The output is a small diff to the tracked `config/traffic-weights.env` file. I review that diff and commit it before Terraform plans and applies the Azure Traffic Manager weight change. No incident analyzer has credentials or code paths to change a cluster or cloud resource directly.

Traffic Manager uses DNS-based weighted routing, so it is a deliberate demonstration control rather than a request-level failover system. DNS caching means recovery measurements need to account for the configured TTL.

## Live integration boundary

The repository now includes a [live Claude analyzer](claude-analyzer.md) that sends a sanitized fixture through the Anthropic Messages API and validates the returned JSON with the same local policy. The Anthropic credential remains outside Git and Terraform state.

A webhook receiver and read-only live evidence collector remain future work. They will receive Alertmanager events, collect compact metrics, traces, Kubernetes events, and current traffic state, then submit only that bounded evidence to the same validator. They must not bypass the existing approval boundary.
