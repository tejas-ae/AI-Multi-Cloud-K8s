# Live Claude analyzer

I keep the live Claude call outside the cluster for this portfolio demonstration. The local analyzer sends a compact, sanitized incident bundle and current Git traffic weights to the Anthropic Messages API, requires JSON-only output, and then passes that output through the repository's deterministic policy validator.

The analyzer cannot modify Kubernetes, Terraform, GitHub, cloud resources, or traffic weights. It writes the temporary model response only to a local temporary file while validation runs, then removes it.

## Run it

I set these values only in my local terminal. I do not put them in `.env`, Git, Terraform variables, screenshots, or logs:

```bash
export ANTHROPIC_API_KEY='set-this-in-your-shell'
make incident-claude
```

The command lists the models enabled for my Anthropic account, selects the first Sonnet model returned, uses the sanitized incident fixture, and prints only the policy-approved summary. I can set `ANTHROPIC_MODEL` locally to override automatic selection. The command exits nonzero if Claude returns invalid JSON or violates any guardrail. The existing offline commands remain the repeatable test path:

```bash
make incident-replay
make incident-proposal
make incident-reject-unsafe
```

## Guardrails

The model receives evidence IDs and compact evidence supplied in the fixture. The validator requires every evidence ID, confidence of at least 0.80, a healthy destination, a maximum 20-point weight delta, recorded rollback weights, and `approval_required: true`. The only permitted recommendation is `shift_traffic`.

This is a live model call with a local evidence fixture, not an Alertmanager webhook service. A webhook receiver and read-only live evidence collector remain future work; they should preserve this exact validation and approval boundary.
