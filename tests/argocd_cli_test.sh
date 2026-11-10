#!/usr/bin/env bash
# #5: //:argocd is runnable from runfiles, at the pinned version, with no host
# `argocd` (PATH is cleared below). $1 is `$(rlocationpath //:argocd)`, $2 the
# pinned Argo CD version.
set -euo pipefail
cli="${RUNFILES_DIR:-$0.runfiles}/$1"
[[ -x "$cli" ]] || { echo "FAIL: $1 not executable in runfiles ($cli)" >&2; exit 1; }
out="$(PATH=/nonexistent "$cli" version --client --short)"
echo "$out"
[[ "$out" == "argocd: v$2+"* ]] || { echo "FAIL: want argocd v$2, got: $out" >&2; exit 1; }
echo "PASS: //:argocd runs the pinned CLI v$2 from runfiles"
