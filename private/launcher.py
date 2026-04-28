#!/usr/bin/env python3
"""Runtime launcher for argocd_install / argocd_health_check.

Same role as launcher.py in rules_pg / rules_temporal / rules_kind /
rules_playwright / rules_capsule / rules_certmanager / rules_cilium. Owns:
- env setup (KUBECONFIG resolution, kubectl resolution honoring $KUBECTL)
- exec of `kubectl` against the resolved kubeconfig
- SIGTERM/SIGINT forwarding so itest can stop the long-running install
  service cleanly
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time


def _resolve_runfiles(rel: str) -> str:
    rfd = os.environ.get("RUNFILES_DIR") or os.environ.get("TEST_SRCDIR")
    if not rfd:
        return rel
    candidate = os.path.join(rfd, "_main", rel)
    if os.path.exists(candidate):
        return candidate
    candidate = os.path.join(rfd, rel)
    if os.path.exists(candidate):
        return candidate
    return rel


def _kubeconfig_from_env(name: str) -> str | None:
    if name and os.environ.get(name):
        return os.environ[name]
    if os.environ.get("KUBECONFIG"):
        return os.environ["KUBECONFIG"]
    return None


def _resolve_kubectl() -> str | None:
    cand = os.environ.get("KUBECTL")
    if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
        return cand
    return shutil.which("kubectl")


def _run(cmd: list[str], env: dict[str, str], stdin: bytes | None = None) -> int:
    print("rules_argocd: " + " ".join(cmd), file=sys.stderr, flush=True)
    return subprocess.run(cmd, env=env, input=stdin).returncode


def _ensure_namespace(kubectl: str, kubeconfig: str, ns: str, env: dict[str, str]) -> int:
    """The Argo CD install.yaml does NOT contain a Namespace resource (unlike
    cert-manager's). Create the namespace idempotently before the apply so
    the namespaced resources have somewhere to land."""
    ns_yaml = f"apiVersion: v1\nkind: Namespace\nmetadata:\n  name: {ns}\n".encode()
    cmd = [kubectl, "--kubeconfig", kubeconfig, "apply", "-f", "-"]
    return _run(cmd, env, stdin=ns_yaml)


def _install(args, env: dict[str, str]) -> int:
    manifest = _resolve_runfiles(args.manifest)
    if not os.path.isfile(manifest):
        print(f"rules_argocd: manifest not in runfiles: {manifest}", file=sys.stderr)
        return 2

    kubectl = _resolve_kubectl()
    if not kubectl:
        print(
            "rules_argocd: kubectl not found. Set $KUBECTL (e.g. via "
            "rules_kind's env file) or put kubectl on $PATH.",
            file=sys.stderr,
        )
        return 127

    kubeconfig = _kubeconfig_from_env(args.kubeconfig_env)
    if not kubeconfig:
        print(
            f"rules_argocd: no kubeconfig — set ${args.kubeconfig_env} or $KUBECONFIG.",
            file=sys.stderr,
        )
        return 2
    env["KUBECONFIG"] = kubeconfig

    rc = _ensure_namespace(kubectl, kubeconfig, args.namespace, env)
    if rc != 0:
        return rc

    # The manifest declares its resources with hard-coded `namespace: argocd`,
    # so `-n argocd` here is the same namespace the manifest resources target.
    # Argo CD's install.yaml is large but self-contained — no embedded CRs of
    # its own CRDs (those are consumer-authored). Single-pass apply normally
    # succeeds; retry once defensively for transient API-server warm-up.
    apply_cmd = [kubectl, "--kubeconfig", kubeconfig, "-n", args.namespace,
                 "apply", "-f", manifest,
                 "--server-side=true", "--validate=false"]
    rc = 1
    for attempt in (1, 2):
        rc = _run(apply_cmd, env)
        if rc == 0:
            break
        if attempt == 1:
            print(
                f"rules_argocd: apply attempt {attempt} failed; "
                f"retrying once after 5s.",
                file=sys.stderr,
            )
            time.sleep(5)
    if rc != 0:
        return rc

    # Block until Argo CD's six Deployments are Available + the application-
    # controller StatefulSet is rolled out. Without this, downstream services
    # that try to apply Application CRs immediately may race the controller's
    # webhook coming online.
    print(
        f"rules_argocd: waiting for Deployments in {args.namespace} to be Available",
        file=sys.stderr, flush=True,
    )
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "-n", args.namespace, "wait",
         "deploy", "--all", "--for=condition=Available", "--timeout=300s"],
        env,
    )
    if rc != 0:
        return rc
    print(
        f"rules_argocd: waiting for sts/argocd-application-controller rollout",
        file=sys.stderr, flush=True,
    )
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "-n", args.namespace,
         "rollout", "status", "sts/argocd-application-controller",
         "--timeout=300s"],
        env,
    )
    if rc != 0:
        return rc

    print("rules_argocd: install applied; sleeping until SIGTERM",
          file=sys.stderr, flush=True)
    while True:
        time.sleep(3600)


def _health_check(args, env: dict[str, str]) -> int:
    kubectl = _resolve_kubectl()
    if not kubectl:
        print(
            "rules_argocd: kubectl not found. Set $KUBECTL or put kubectl on $PATH.",
            file=sys.stderr,
        )
        return 127

    kubeconfig = _kubeconfig_from_env(args.kubeconfig_env)
    if not kubeconfig:
        print(
            f"rules_argocd: no kubeconfig — set ${args.kubeconfig_env} or $KUBECONFIG.",
            file=sys.stderr,
        )
        return 2
    env["KUBECONFIG"] = kubeconfig

    ns = args.namespace
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "get", "crd",
         "applications.argoproj.io", "-o", "name"],
        env,
    )
    if rc != 0:
        return rc
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "-n", ns, "wait", "deploy",
         "--all", "--for=condition=Available", "--timeout=0s"],
        env,
    )
    if rc != 0:
        return rc
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "-n", ns, "rollout", "status",
         "sts/argocd-application-controller", "--timeout=0s"],
        env,
    )
    return rc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["install", "health_check"], required=True)
    ap.add_argument("--manifest", default="", help="Pinned install.yaml (install mode).")
    ap.add_argument("--namespace", default="argocd")
    ap.add_argument("--kubeconfig-env", default="KUBECONFIG",
                    help="Env var holding the path to the kubeconfig file. " +
                         "Defaults to KUBECONFIG; rules_kind compositions " +
                         "typically set KUBECONFIG_<cluster> via itest.")
    args = ap.parse_args(argv[1:])

    env = os.environ.copy()

    if args.mode == "install":
        proc_func = lambda: _install(args, env)
    else:
        proc_func = lambda: _health_check(args, env)

    def handle(_signum, _frame):
        sys.exit(143)

    signal.signal(signal.SIGTERM, handle)
    signal.signal(signal.SIGINT, handle)

    return proc_func() or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
