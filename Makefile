SHELL := /bin/bash

.PHONY: bootstrap-macos bootstrap-cloud-foundation preflight k8s-versions verify-clean tf-init tf-fmt tf-validate tf-plan tf-review tf-apply tf-destroy tf-output gitops-bootstrap gitops-status argocd-gke-ui argocd-aks-ui mesh-bootstrap mesh-status workload-bootstrap workload-status observability-bootstrap observability-status observability-gke-ui observability-aks-ui incident-replay incident-proposal incident-reject-unsafe fault-inject fault-clear fault-status fault-load fault-capture

bootstrap-macos:
	./scripts/bootstrap-macos.sh --execute

bootstrap-cloud-foundation:
	./scripts/bootstrap-cloud-foundation.sh --execute

preflight:
	./scripts/preflight.sh

k8s-versions:
	./scripts/kubernetes-versions.sh

verify-clean:
	./scripts/verify-repository.sh

tf-init:
	./scripts/terraform.sh init

tf-fmt:
	./scripts/terraform.sh fmt

tf-validate:
	./scripts/terraform.sh validate

tf-plan:
	./scripts/terraform.sh plan

tf-review:
	./scripts/review-terraform-plan.sh

tf-apply:
	./scripts/terraform.sh apply

tf-destroy:
	./scripts/terraform.sh destroy

tf-output:
	./scripts/terraform.sh output

gitops-bootstrap:
	./scripts/argocd.sh bootstrap

gitops-status:
	./scripts/argocd.sh status

argocd-gke-ui:
	./scripts/argocd.sh port-forward gke

argocd-aks-ui:
	./scripts/argocd.sh port-forward aks

mesh-bootstrap:
	./scripts/istio.sh bootstrap

mesh-status:
	./scripts/istio.sh status

workload-bootstrap:
	./scripts/platform.sh bootstrap

workload-status:
	./scripts/platform.sh status

observability-bootstrap:
	./scripts/observability.sh bootstrap

observability-status:
	./scripts/observability.sh status

observability-gke-ui:
	./scripts/observability.sh port-forward gke

observability-aks-ui:
	./scripts/observability.sh port-forward aks

incident-replay:
	./scripts/incident.sh replay

incident-proposal:
	./scripts/incident.sh propose

incident-reject-unsafe:
	./scripts/incident.sh reject-unsafe

fault-inject:
	./scripts/fault.sh inject

fault-clear:
	./scripts/fault.sh clear

fault-status:
	./scripts/fault.sh status

fault-load:
	./scripts/fault.sh load

fault-capture:
	./scripts/fault.sh capture
