#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

non_executable_scripts=()
while IFS= read -r script; do
  if [[ ! -x "$script" ]]; then
    non_executable_scripts+=("$script")
  fi
done < <(find scripts -maxdepth 1 -type f -name '*.sh' | sort)

if (( ${#non_executable_scripts[@]} > 0 )); then
  printf 'shell script is not executable: %s\n' "${non_executable_scripts[@]}" >&2
  exit 1
fi

blocked_paths='(^|/)(\.env($|\.)|[^/]*\.tfstate($|\.)|[^/]*\.tfplan($|\.)|kubeconfig|[^/]*\.pem$|[^/]*\.key$|private-notes?/|\.workspace/|evidence/(raw|private)/)'
if find . -type f -not -path './.git/*' -print | sed 's#^./##' | grep -E "$blocked_paths"; then
  echo "repository contains blocked paths" >&2
  exit 1
fi

if find . -type f -not -path './.git/*' -print0 | xargs -0 grep -IEn 'sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' -- 2>/dev/null; then
  echo "repository contains a recognizable secret or private key" >&2
  exit 1
fi

echo "repository publication checks passed"
