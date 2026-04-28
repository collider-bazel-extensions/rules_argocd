#!/usr/bin/env bash
# Runs once Argo CD is `Available`. Creates an Application that points at
# argoproj/argocd-example-apps `guestbook` (a tiny, stable Argo project
# example) and asserts it reaches Synced + Healthy. This is a stronger
# assertion than "Deployments are Available" — it proves the controller
# + repo-server actually clone, render, and apply manifests, which is
# the whole point of Argo CD.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

echo "smoke_test: applying AppProject + Application (guestbook)"
"${KCTL[@]}" apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: smoke
  namespace: argocd
spec:
  description: rules_argocd smoke test
  sourceRepos:
    - "https://github.com/argoproj/argocd-example-apps"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: default
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: ""
      kind: "*"
    - group: "apps"
      kind: "*"
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: smoke-guestbook
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: smoke
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "smoke_test: waiting for Application smoke-guestbook to reach Synced + Healthy"
deadline=$(( $(date +%s) + 240 ))
while (( $(date +%s) < deadline )); do
  sync=$("${KCTL[@]}" -n argocd get application smoke-guestbook \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health=$("${KCTL[@]}" -n argocd get application smoke-guestbook \
    -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  echo "smoke_test: sync=$sync health=$health"
  if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
    echo "smoke_test: OK — Application Synced + Healthy"
    # Sanity: the guestbook deployment should now exist in `default`.
    "${KCTL[@]}" -n default get deploy guestbook-ui -o name >/dev/null
    echo "smoke_test: OK — default/guestbook-ui Deployment exists"
    exit 0
  fi
  sleep 5
done

echo "smoke_test: FAIL — Application never reached Synced + Healthy" >&2
"${KCTL[@]}" -n argocd get application smoke-guestbook -o yaml >&2 || true
"${KCTL[@]}" -n argocd get pods >&2 || true
exit 1
