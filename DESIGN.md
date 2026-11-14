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
| 14 | Update workflow | `tools/update_versions.sh <version>` curls the manifest from the upstream tag, computes sha256, pins the CLI binaries from the release's `cli_checksums.txt` (checking each download), rewrites `private/versions.bzl`. | rules_certmanager |
| 15 | Runtime lifecycle | One Python `private/launcher.py`: env setup, kubectl exec, namespace pre-create, SIGTERM forwarding. Install path waits for **all Argo CD Deployments Available + the application-controller StatefulSet rolled out** before idling. | rules_certmanager v0.1.2 precedent (Deployments-block-idle) extended for the StatefulSet |
| 16 | kubectl provisioning | **Host kubectl required** at v0.1, OR `$KUBECTL` env var (set by rules_kind's per-cluster env file). | All siblings |
| 17 | Smoke assertion | Apply an `AppProject` + an `Application` pointing at `argoproj/argocd-example-apps` `guestbook`; assert the Application reaches `Synced + Healthy` and that the resulting Deployment exists in `default`. This is the assertion that justifies pulling Argo CD in: a cluster without the controller would never reconcile this. Requires outbound network to GitHub during the smoke run; tagged `requires-network`. | Argo CD-specific |
| 18 | Which tags the extension honours (v0.1.1) | rules_argocd's own `argocd.version()` tags are the base and the root module's override them by `name` (or add names); other modules' tags are ignored, and each repo is created once. rules_argocd's `MODULE.bazel` imports `@argocd` and registers its toolchain for every consumer, so through v0.1.0, when only the root's tags counted, a root without `argocd.version()` failed with `does not generate repository "argocd"`. The old comment's "collision" was the extension creating the same repo twice, which a root repeating a tag still triggered. One module giving a name two versions, or a version not in `ARGOCD_VERSIONS`, fails naming `argocd.version`. | Same fix as rules_atlas#12 |
| 19 | Release archive | `tests/` (dev-only `rules_itest`, `rules_kind`, `rules_oci`, `rules_shell`) and `tools/` (maintainer-only) are `export-ignore`, so `@rules_argocd//...` loads for consumers. `REPO.bazel` `ignore_directories` would also hide them from this repo's own `bazel test`. A `git_override` clone still contains them. CI's `consumer` job (`.github/consumer/check.sh`) checks this and #18 from the commit's `git archive`. | Same fix as rules_kubectl#5 |
| 20 | argocd CLI (v0.2.0, #5) | Each hub (`argocd.version()`, named `<hub>`) declares `:argocd`, an `argocd_cli` (`private/cli.bzl`): an executable symlink to the release binary for the target platform, selected over `<hub>_cli_<platform>` repos the extension creates next to the hub. Each downloads one `argocd-<os>-<arch>` at the sha in `ARGOCD_VERSIONS[v]["cli"]`, and only when a build needs it, so an install-only consumer doesn't fetch ~200 MB of CLI. `@rules_argocd//:argocd` aliases `@argocd//:argocd`, so the CLI follows the root's `argocd.version()`. Not on the toolchain: a `data` dependency (`$(rlocationpath)`) is what a consumer's binary needs, and the toolchain is resolved for rules, not runfiles. `PLATFORMS` gains `linux_arm64`, which the toolchains also lacked: a linux/arm64 target had no `@argocd` toolchain (this repo's dev `//tests:smoke_toolchain`, which has no constraints, hid it). | rules_temporal#13 (`//:temporal`) |
| 21 | Argo CD 3.3.19; self-pinned versions (v0.3.0, #7) | Default 3.3.19: 3.3.8's controller panics at `controller/sync.go:311` on a nil APIResource from discovery, the recovery marks the operation `Error` before the retry switch, and automated sync never retries the revision (argoproj/argo-cd#26608; fixed by #26610, in 3.3 from 3.3.10). 3.3.8 stays in `ARGOCD_VERSIONS`. `argocd.version()` also takes `sha256`, `url` and `cli_sha256` (by platform), so a consumer can use a release before rules_argocd lists it; for a listed version they replace its pins. An unlisted version needs `sha256`; `url` defaults to `ARGOCD_MANIFEST_URL`. A platform without a CLI sha gets a CLI repo that fails with a message naming `cli_sha256`, only when fetched, so an install-only consumer pins just the manifest. The existing design (a hub per `argocd.version()` name, per-platform toolchains and CLI repos) was already a versioned toolchain; the only gap was the closed version list. One module giving a name two different tags (any pin differing) still fails. | rules_go `go_sdk.download(sdks = ...)` |

## Argo CD-specific notes

- `install.yaml` size is large (~33 K lines, ~6 Deployments + 1 StatefulSet + 3 CRDs + a flotilla of RBAC). Server-side apply is the only sane way to install it; the launcher passes `--server-side=true --validate=false`.
- The `argocd-application-controller` runs as a `StatefulSet` (not a Deployment) because it shards work by ID. The health check has to wait for both kinds.
- The `Application` and `AppProject` CRDs are registered in `install.yaml` itself, so they are available immediately after apply — no operator-side registration race like Cilium.
- **Smoke-test redis, without the registry.** `install.yaml` runs redis as `public.ecr.aws/docker/library/redis:<tag>` with `imagePullPolicy: Always`. GitHub runners' anonymous pulls from ECR Public intermittently fail with `429 Too Many Requests: Data limit exceeded`, which left redis unready and timed out the smoke test. Preloading the image alone doesn't help: with `Always`, the kubelet contacts the registry even when the image is on the node (verified: "Pulling image" despite the preload). So, for the in-tree smoke only:
  1. `oci.pull` (rules_oci, dev dependency) fetches the redis index by digest from `mirror.gcr.io/library/redis`, Google's Docker Hub cache, which serves the same Docker Official Image under the same digest. Fetching from ECR Public at build time got the same 429 on the first CI run. `oci_load` tags it with the `public.ecr.aws/...` name `install.yaml` uses, and `filegroup(output_group = "tarball")` produces a docker-archive that `kind_cluster(images = ...)` loads at boot. Bazel's repository cache keeps the blobs.
  2. `//tests:smoke_install_yaml` copies the pinned `install.yaml` and changes that container's `imagePullPolicy` to `IfNotPresent`, nothing else; `//tests:smoke_toolchain` serves it and is registered (dev dependency) ahead of `@argocd//:all`. The kubelet then reports "already present on machine".
  The genrule fails unless exactly one `image: <REDIS_IMAGE>` line is followed by `imagePullPolicy: Always`, so an Argo CD bump that changes redis forces the tag and digest to be updated together. The quay.io Argo CD images (also `Always`) are still pulled; they haven't been rate-limited.
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
- **Bundled example-apps.** v0.1 sources the smoke from `argoproj/argocd-example-apps`. If consumers ask, ship a tiny in-tree manifest set behind a local file:// or in-cluster Git server.
