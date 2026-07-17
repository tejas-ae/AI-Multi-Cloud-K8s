#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute" >&2
  echo "Installs the AI Multi-Cloud K8s macOS toolchain with Homebrew." >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This bootstrap is only for macOS." >&2
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Install Apple Command Line Tools first: xcode-select --install" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh and rerun this command." >&2
  exit 1
fi

brew update
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install azure-cli kubectl helm gh jq yq shellcheck conftest istioctl k6 trivy cosign syft argocd
brew install Azure/kubelogin/kubelogin
brew install --cask gcloud-cli docker

echo
echo "Tool installation finished. Start Docker Desktop, open a new terminal, and run:"
echo "  make preflight"
