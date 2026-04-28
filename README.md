# rules_argocd

Hermetic [Argo CD](https://argo-cd.readthedocs.io/) install + readiness for
Bazel tests. Drops into [`rules_itest`](https://github.com/dzbarsky/rules_itest)
and composes with [`rules_kind`](https://github.com/collider-bazel-extensions/rules_kind)
(or any cluster the consumer provides via `KUBECONFIG`).

This rule set is the smallest path to "an Argo CD `Application` actually
reconciles in a Bazel test." If the in-cluster reconciler isn't running,
the assertion fails — so smoke-green proves the controller, repo-server,
and CRD wiring all work end-to-end.

**Supported platforms (v0.1):** Linux (x86\_64). macOS untested but the
rule is platform-independent (just kubectl + a static YAML). See
[Contributing](#contributing).

**Pinned versions:** Argo CD 3.3.8. The published `manifests/install.yaml`
is downloaded directly and sha256-verified — **no `helm` is required at
maintainer or consumer side**.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Rules](#rules)
  - [argocd\_install](#argocd_install)
  - [argocd\_health\_check](#argocd_health_check)
- [`rules_itest` integration](#rules_itest-integration)
- [Providers](#providers)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_argocd", version = "0.1.0")

argocd = use_extension("@rules_argocd//:extensions.bzl", "argocd")
argocd.version(version = "3.3.8")
use_repo(argocd, "argocd")

register_toolchains("@argocd//:all")
```

`rules_argocd` is **Bzlmod-only** in v0.1. Until it lands in BCR, consume
via `archive_override` or a git pin pointing at a tag.

For the in-tree smoke test composition, you also need
[`rules_kind`](https://github.com/collider-bazel-extensions/rules_kind)
**≥ 0.1.2** (the smoke pins `k8s_version = "1.32"`).

---

## Quickstart

```python
load("@rules_argocd//:defs.bzl", "argocd_install", "argocd_health_check")

# Long-running: creates the `argocd` Namespace if absent, applies the
# pinned manifest, then waits for all Argo CD Deployments + the
# application-controller StatefulSet to be ready before idling.
argocd_install(
    name = "argocd",
    kubeconfig_env = "KUBECONFIG",
)

# Readiness: the Application CRD is registered + all Deployments
# `Available=True` + the application-controller StatefulSet rolled out.
argocd_health_check(name = "argocd_health")
```

The rule itself doesn't bring up a cluster — it just installs Argo CD into
one you already have. For a kind-based composition, see
[`rules_itest` integration](#rules_itest-integration).

---

## Rules

### `argocd_install`

```python
argocd_install(
    name = "argocd",
    kubeconfig_env = "KUBECONFIG",
)
```

Two-step install:

1. Apply a `Namespace/argocd` resource (idempotent — Argo CD's
   `install.yaml` does **not** include a Namespace, unlike cert-manager's).
2. `kubectl apply --server-side -f` the toolchain's pinned `install.yaml`
   into `-n argocd`. Two-pass apply with retry to absorb transient
   API-server warm-up errors.

Then blocks until **all six Deployments** (applicationset-controller,
dex-server, notifications-controller, redis, repo-server, server) reach
`Available=True` *and* the **`argocd-application-controller` StatefulSet**
rolls out. Only then does the install service idle and let `rules_itest`
mark it ready.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `kubeconfig_env` | `string` | `"KUBECONFIG"` | Env var holding the kubeconfig path. Under `rules_kind` + `rules_itest` you typically point this at whatever `kind_cluster`'s env file exports (often just `KUBECONFIG` after sourcing). |

### `argocd_health_check`

```python
argocd_health_check(
    name = "argocd_health",
    namespace = "argocd",
)
```

Three-step probe: (1) the `applications.argoproj.io` CRD is registered
(proves the manifest finished applying); (2) all Deployments in the
configured namespace are `Available=True`; (3) the
`argocd-application-controller` StatefulSet rollout is complete.
`rules_itest` retries until success or timeout.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `namespace` | `string` | `"argocd"` | Namespace Argo CD installs into; matches the manifest's hard-coded references. |
| `kubeconfig_env` | `string` | `"KUBECONFIG"` | Env var holding the kubeconfig path. |

---

## `rules_itest` integration

`rules_argocd` integrates by emitting `itest_service.exe` /
`health_check`-shaped targets. Composition is the consumer's job — no
pass-through `services=` attr, matching the
`rules_pg`/`rules_temporal`/`rules_kind`/`rules_playwright`/`rules_capsule`/`rules_certmanager`/`rules_cilium`
convention.

The in-tree smoke test is the canonical reference. Composition shape:

```python
load("@rules_argocd//:defs.bzl", "argocd_install", "argocd_health_check")
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# 1. The cluster.
kind_cluster(name = "cluster", k8s_version = "1.32")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. Argo CD.
argocd_install(name = "argocd_bin")
argocd_health_check(name = "argocd_health_bin")

# 3. Wrappers that bind the cluster-source-agnostic rule binaries to the
#    specific rules_kind cluster (source the env file with `set -a` so
#    KUBECONFIG/KUBECTL cross the `exec` boundary).
sh_binary(
    name = "argocd_install_wrapper",
    srcs = ["argocd_install_wrapper.sh"],
    data = [":argocd_bin"],
)
sh_binary(
    name = "argocd_health_wrapper",
    srcs = ["argocd_health_wrapper.sh"],
    data = [":argocd_health_bin"],
)
itest_service(
    name = "argocd_svc",
    exe = ":argocd_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":argocd_health_wrapper",
)
```

The `tests/` directory has the wrapper shell scripts and an end-to-end
test that creates an `AppProject` + `Application` pointing at
`argoproj/argocd-example-apps` `guestbook`, then asserts the Application
reaches `Synced` + `Healthy` and the resulting `guestbook-ui` Deployment
exists. This is the assertion that proves the controller + repo-server
chain actually reconciles.

---

## Providers

### `ArgoCDInfo`

| Field | Type | Description |
|---|---|---|
| `version` | `string` | Argo CD version, e.g. `"3.3.8"` |
| `manifest` | `File` | The downloaded, sha256-verified `install.yaml` |
| `namespace` | `string` | Defaults to `"argocd"` (matches the manifest's hard-coded references) |

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| `install.yaml` | Fully hermetic. URL + sha256 pinned in `private/versions.bzl`; downloaded by the bzlmod extension. | Update via `bash tools/update_versions.sh <version>` when bumping. |
| `kubectl` | **Not vendored.** v0.1 honors `$KUBECTL` env (set by `rules_kind`'s per-cluster env file) and falls back to `$PATH`. | Future: bundle a hermetic kubectl via toolchain. |
| Target cluster | Out of scope — bring your own (`rules_kind`, real cluster, etc.). | The rule reads `KUBECONFIG` from env. |
| Argo CD container images | **Pulled at runtime** by the cluster's nodes. Not pre-loaded. | Future: optional `images = [...]` attr for pre-loading via `kind_cluster.images`. |
| Smoke-test Git source | The smoke pulls `argoproj/argocd-example-apps` (`guestbook`) over the public internet — `requires-network`. | Acceptable v0.1 tradeoff vs vendoring our own Git server. |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned Argo CD version: `bash tools/update_versions.sh <new-version> --update`.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted: macOS validation

The rule is platform-independent (kubectl + static YAML), but no one has
run the smoke test on Darwin. A green smoke run on macOS — even a pasted
log from `bazel test //tests:smoke_test` — would unblock the macOS
support claim. Filing an issue with the result is plenty.
