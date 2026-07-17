# Workstation and cloud readiness

I use this preflight as a hard gate before creating Kubernetes infrastructure. It is read-only except for the separate cloud-foundation bootstrap.

## What I verify

- macOS and the complete CLI toolchain
- Docker Desktop engine availability
- GCP user authentication and Application Default Credentials
- Azure and GitHub authentication
- GCP APIs, machine availability, regional CPU quota, budget, and remote-state access
- Azure provider registration, SKU restrictions, regional quota, VM-family quota, and budget
- Exact Kubernetes versions in both target regions
- A single operator IPv4 `/32` for both API servers
- A private cost cap and cleanup gate
- A repository free of state, plans, kubeconfigs, private keys, and private evidence

## Setup

I install the workstation tools with:

```bash
make bootstrap-macos
```

I authenticate each CLI directly:

```bash
gcloud auth login
gcloud auth application-default login
az login
gh auth login --web --git-protocol https
```

I keep environment-specific values in an ignored file:

```bash
cp config/preflight.env.example .env
chmod 600 .env
set -a
source .env
set +a
```

The cloud-foundation bootstrap enables prerequisite APIs and providers, creates the versioned GCS backend, and configures budget alerts. It does not create either cluster.

```bash
make bootstrap-cloud-foundation
```

I load the model credential separately when the check needs it. The value never belongs in `.env`, Terraform state, shell history, or Git.

## Gate

```bash
make verify-clean
make preflight
```

The preflight passes only with:

```text
warnings=0 failures=0
READY: preflight passed.
```

Any failure blocks Terraform apply.
