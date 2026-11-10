"""Per-version hub repo: downloads Argo CD's manifests/install.yaml at the
pinned URL + sha256, exposes it as an `argocd_toolchain` per platform, and
declares the runnable CLI `:argocd`, which selects one of the per-platform
CLI repos (`<hub>_cli_<platform>`). Those download only when built.
"""

load(":versions.bzl", "ARGOCD_CLI_URL", "ARGOCD_VERSIONS", "PLATFORMS")

_HUB_BUILD_TMPL = """\
load("@rules_argocd//private:cli.bzl", "argocd_cli")
load("@rules_argocd//toolchain:toolchain.bzl", "argocd_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["install.yaml"])

{toolchains}
{cli_settings}
# `bazel run @{hub}//:argocd -- version --client`
argocd_cli(
    name = "argocd",
    version = "{version}",
    binary = select(
        {{
{cli_select}
        }},
        no_match_error = "rules_argocd: no argocd CLI for this target platform; supported: {platforms}",
    ),
)
"""

_HUB_CLI_SETTING_TMPL = """\
config_setting(
    name = "_{plat}",
    constraint_values = {compat},
)
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
    settings = []
    selects = []
    for plat, compat in PLATFORMS.items():
        chunks.append(_HUB_TC_TMPL.format(
            plat = plat,
            version = version,
            compat = repr(compat),
        ))
        settings.append(_HUB_CLI_SETTING_TMPL.format(plat = plat, compat = repr(compat)))
        selects.append('            ":_{plat}": "@{hub}_cli_{plat}//:argocd",'.format(
            plat = plat,
            hub = rctx.attr.hub,
        ))
    rctx.file("BUILD.bazel", _HUB_BUILD_TMPL.format(
        toolchains = "\n".join(chunks),
        cli_settings = "\n".join(settings),
        cli_select = "\n".join(selects),
        hub = rctx.attr.hub,
        version = version,
        platforms = ", ".join(sorted(PLATFORMS.keys())),
    ))

_argocd_hub_repository = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        # The hub's apparent name, which prefixes its CLI repos' names.
        "hub": attr.string(mandatory = True),
    },
)

def _cli_repo_impl(rctx):
    os, arch = rctx.attr.platform.split("_")
    version = rctx.attr.version
    rctx.download(
        url = ARGOCD_CLI_URL.format(version = version, os = os, arch = arch),
        output = "argocd",
        sha256 = ARGOCD_VERSIONS[version]["cli"][rctx.attr.platform],
        executable = True,
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", 'exports_files(["argocd"], visibility = ["//visibility:public"])\n')

_argocd_cli_repository = repository_rule(
    implementation = _cli_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)

def argocd_version_repository(name, version):
    """Materialize the hub repo for one Argo CD version."""
    if version not in ARGOCD_VERSIONS:
        fail("rules_argocd: unknown version '{}'. Known: {}".format(
            version,
            sorted(ARGOCD_VERSIONS.keys()),
        ))
    _argocd_hub_repository(name = name, version = version, hub = name)
    for plat in PLATFORMS.keys():
        _argocd_cli_repository(
            name = "{}_cli_{}".format(name, plat),
            version = version,
            platform = plat,
        )
