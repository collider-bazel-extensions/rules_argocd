"""Per-version hub repo: downloads Argo CD's manifests/install.yaml at the
pinned URL + sha256, exposes it as an `argocd_toolchain` per platform.
"""

load(":versions.bzl", "ARGOCD_VERSIONS", "PLATFORMS")

_HUB_BUILD_TMPL = """\
load("@rules_argocd//toolchain:toolchain.bzl", "argocd_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["install.yaml"])

{toolchains}
"""

_HUB_TC_TMPL = """\
argocd_toolchain(
    name = "{plat}_impl",
    version = "{version}",
    manifest = ":install.yaml",
)

toolchain(
    name = "{plat}",
    toolchain_type = "@rules_argocd//toolchain:argocd",
    target_compatible_with = {compat},
    toolchain = ":{plat}_impl",
)
"""

def _hub_repo_impl(rctx):
    version = rctx.attr.version
    if version not in ARGOCD_VERSIONS:
        fail("rules_argocd: unknown version '{}'. Known: {}".format(
            version,
            sorted(ARGOCD_VERSIONS.keys()),
        ))
    pinned = ARGOCD_VERSIONS[version]
    rctx.download(
        url = pinned["url"],
        output = "install.yaml",
        sha256 = pinned["sha256"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))

    chunks = []
    for plat, compat in PLATFORMS.items():
        chunks.append(_HUB_TC_TMPL.format(
            plat = plat,
            version = version,
            compat = repr(compat),
        ))
    rctx.file("BUILD.bazel", _HUB_BUILD_TMPL.format(
        toolchains = "\n".join(chunks),
    ))

_argocd_hub_repository = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)

def argocd_version_repository(name, version):
    """Materialize the hub repo for one Argo CD version."""
    if version not in ARGOCD_VERSIONS:
        fail("rules_argocd: unknown version '{}'. Known: {}".format(
            version,
            sorted(ARGOCD_VERSIONS.keys()),
        ))
    _argocd_hub_repository(name = name, version = version)
