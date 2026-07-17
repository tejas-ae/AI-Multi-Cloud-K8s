SHELL := /bin/bash

.PHONY: bootstrap-macos bootstrap-cloud-foundation preflight k8s-versions verify-clean tf-init tf-fmt tf-validate tf-plan tf-review tf-apply tf-destroy tf-output gitops-bootstrap gitops-status argocd-gke-ui argocd-aks-ui

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
