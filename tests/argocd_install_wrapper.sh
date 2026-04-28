#!/usr/bin/env bash
# Sources the kind cluster's env file under `set -a` so KUBECONFIG/KUBECTL
# (which are bare KEY=VALUE without `export`) cross the `exec` boundary.
# Resolves the argocd_install bin via runfiles (sh_binary's `env=` attr only
# fires under `bazel run`, not when itest exec's the wrapper).
set -euo pipefail

CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
INSTALL_BIN="${RUNFILES_DIR}/_main/tests/argocd_bin.sh"
[[ -x "$INSTALL_BIN" ]] || { echo "wrapper: argocd_bin not at $INSTALL_BIN" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "argocd_install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

exec "$INSTALL_BIN"
