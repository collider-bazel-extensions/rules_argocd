# rules_argocd — design decisions

Hermetic [Argo CD](https://argo-cd.readthedocs.io/) install + readiness for
Bazel tests. Drop-in for `rules_itest` services; composes with `rules_kind`
(or any cluster the consumer provides via `KUBECONFIG`).

All decisions inherited from sibling
`rules_pg`/`rules_temporal`/`rules_kind`/`rules_playwright`/`rules_capsule`/`rules_certmanager`/`rules_cilium`.
Anything Argo CD-specific is flagged.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | rules_certmanager precedent |
| 2 | Module extension shape | One tag class: `version` (download). No `system` mode — Argo CD is an in-cluster operator, not a host CLI. | rules_certmanager |
| 3 | Toolchain type | `ARGOCD_TOOLCHAIN_TYPE = Label("//toolchain:argocd")`. `ToolchainInfo(argocd = …)` carries the pinned manifest. | All siblings |
| 4 | Manifest provisioning | `manifests/install.yaml` is fetched at extension/repo-rule time via `download` from the upstream tag at the sha256 pinned in `private/versions.bzl`. **No helm needed at maintainer or consumer side** — Argo CD publishes the manifest as a static raw-content asset on every release tag. | rules_certmanager pattern |
| 5 | Public surface | `argocd_install`, `argocd_health_check` + `ArgoCDInfo` provider. CR resources (`AppProject`, `Application`, `ApplicationSet`) are consumer-authored YAML; no rule for them in v0.1. | All siblings |
| 6 | Namespace handling | The Argo CD `install.yaml` is **NOT** self-contained — it contains no `Namespace` resource (unlike cert-manager.yaml). `argocd_install`'s launcher applies a `Namespace` resource via `kubectl apply -f -` first, then applies the manifest with `-n argocd`. The toolchain's `namespace` attr defaults to `"argocd"` to match the manifest's hard-coded references in ConfigMaps and RoleBindings. | Argo CD-specific divergence |
| 7 | Manifest variant | **`manifests/install.yaml`** — the standard non-HA install. Covers application-controller (StatefulSet), repo-server, server, applicationset-controller, notifications-controller, dex-server, redis. v0.2 may add `core-install` / `ha-install` variants if a real consumer asks. | Argo CD-specific |
| 8 | rules_itest integration | `argocd_install` produces an `itest_service.exe`-shaped target; `argocd_health_check` is the readiness probe. **No pass-through `services=` attr.** | All siblings |
| 9 | rules_kind dependency | **Examples-only.** The rule itself depends on neither `rules_kind` nor any cluster-provider rule; it just needs `KUBECONFIG` (or env-var-named-kubeconfig). | rules_certmanager precedent |
| 10 | Platform matrix v1 | Platform-independent (just `kubectl` + YAML). Validated on Linux x86_64; macOS pending. | rules_certmanager |
| 11 | MODULE deps | `bazel_skylib`, `platforms`, `rules_python`. **No `rules_oci`**, no `rules_helm`. `rules_kind`/`rules_itest`/`rules_shell` are dev-only. | rules_certmanager |
| 12 | Default test tags | `["argocd"]`; internal wrapper rules tagged `manual`. Smoke tests also `["requires-network", "no-sandbox"]`. | All siblings |
| 13 | Naming | snake_case rules, `MixedCaseInfo` providers, `UPPER_SNAKE` constants. | All siblings |
| 14 | Update workflow | `tools/update_versions.sh <version>` curls the manifest from the upstream tag, computes sha256, rewrites `private/versions.bzl`. | rules_certmanager |
| 15 | Runtime lifecycle | One Python `private/launcher.py`: env setup, kubectl exec, namespace pre-create, SIGTERM forwarding. Install path waits for **all Argo CD Deployments Available + the application-controller StatefulSet rolled out** before idling. | rules_certmanager v0.1.2 precedent (Deployments-block-idle) extended for the StatefulSet |
| 16 | kubectl provisioning | **Host kubectl required** at v0.1, OR `$KUBECTL` env var (set by rules_kind's per-cluster env file). | All siblings |
| 17 | Smoke assertion | Apply an `AppProject` + an `Application` pointing at `argoproj/argocd-example-apps` `guestbook`; assert the Application reaches `Synced + Healthy` and that the resulting Deployment exists in `default`. This is the assertion that justifies pulling Argo CD in: a cluster without the controller would never reconcile this. Requires outbound network to GitHub during the smoke run; tagged `requires-network`. | Argo CD-specific |

## Argo CD-specific notes

- `install.yaml` size is large (~33 K lines, ~6 Deployments + 1 StatefulSet + 3 CRDs + a flotilla of RBAC). Server-side apply is the only sane way to install it; the launcher passes `--server-side=true --validate=false`.
- The `argocd-application-controller` runs as a `StatefulSet` (not a Deployment) because it shards work by ID. The health check has to wait for both kinds.
- The `Application` and `AppProject` CRDs are registered in `install.yaml` itself, so they are available immediately after apply — no operator-side registration race like Cilium.
- v0.1 uses the public `argoproj/argocd-example-apps` Git repo for the smoke test source. If that repo is ever moved or the `guestbook` directory removed, the smoke test fails — accept that as a tradeoff for not vendoring our own Git server.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| Module extension (`version` only) | planned |
| Pinned Argo CD 3.3.8 sha256 | planned |
| `argocd_install`, `argocd_health_check` rules | planned |
| `launcher.py` (env, exec, ns pre-create, SIGTERM) | planned |
| Analysis tests | planned |
| In-tree smoke test (kind + Argo CD + guestbook Application Synced+Healthy) | planned |
| End-to-end `bazel test` runtime | planned (validated under CI Docker; macOS pending) |

## Deferred (not v0.1.0)

- **CR-shaped public rules** (`argocd_application`, `argocd_appproject`, `argocd_applicationset`). Consumers author these as YAML for now. Add only if a real consumer asks.
- **HA + core install variants.** v0.1 ships only `install.yaml`. `manifests/ha/install.yaml` and `manifests/core-install.yaml` are the obvious follow-ups.
- **Hermetic kubectl.** v0.1 trusts host kubectl on PATH or `$KUBECTL` env var.
- **Hermetic argocd CLI.** Useful for `argocd app sync` flows and password retrieval; not needed for the manifest-only smoke. Defer until a consumer wants CR-shaped rules.
- **Bundled example-apps.** v0.1 sources the smoke from `argoproj/argocd-example-apps`. If consumers ask, ship a tiny in-tree manifest set behind a local file:// or in-cluster Git server.
