"""Per-version hub repo: downloads Argo CD's manifests/install.yaml at the
pinned URL + sha256, exposes it as an `argocd_toolchain` per platform, and
declares the runnable CLI `:argocd`, which selects one of the per-platform
CLI repos (`<hub>_cli_<platform>`). Those download only when built.
"""

load(":versions.bzl", "ARGOCD_CLI_URL", "ARGOCD_MANIFEST_URL", "ARGOCD_VERSIONS", "PLATFORMS")

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
    rctx.download(
        url = rctx.attr.url,
        output = "install.yaml",
        sha256 = rctx.attr.sha256,
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
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        # The hub's apparent name, which prefixes its CLI repos' names.
        "hub": attr.string(mandatory = True),
    },
)

def _cli_repo_impl(rctx):
    os, arch = rctx.attr.platform.split("_")
    version = rctx.attr.version
    if not rctx.attr.sha256:
        fail("rules_argocd: no sha256 for the Argo CD {} CLI on {}; add it to argocd.version(cli_sha256 = {{\"{}\": ...}}) (from the release's cli_checksums.txt).".format(
            version,
            rctx.attr.platform,
            rctx.attr.platform,
        ))
    rctx.download(
        url = ARGOCD_CLI_URL.format(version = version, os = os, arch = arch),
        output = "argocd",
        sha256 = rctx.attr.sha256,
        executable = True,
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", 'exports_files(["argocd"], visibility = ["//visibility:public"])\n')

_argocd_cli_repository = repository_rule(
    implementation = _cli_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
        # Empty: no pin for this platform, so fetching fails (only when a
        # build needs this platform's CLI).
        "sha256": attr.string(),
    },
)

def argocd_version_repository(name, version, url = "", sha256 = "", cli_sha256 = {}):
    """Materialize the hub repo for one Argo CD version.

    Pins default to ARGOCD_VERSIONS[version]; `url`, `sha256` and
    `cli_sha256` (by platform) replace them, and a version not in
    ARGOCD_VERSIONS needs at least `sha256`.
    """
    known = ARGOCD_VERSIONS.get(version, {})
    if not sha256 and not known:
        fail("rules_argocd: unknown version '{}' and no sha256. Known: {}".format(
            version,
            sorted(ARGOCD_VERSIONS.keys()),
        ))
    for plat in cli_sha256:
        if plat not in PLATFORMS:
            fail("rules_argocd: cli_sha256 has unknown platform '{}'. Platforms: {}".format(
                plat,
                sorted(PLATFORMS.keys()),
            ))
    _argocd_hub_repository(
        name = name,
        version = version,
        url = url or known.get("url") or ARGOCD_MANIFEST_URL.format(version = version),
        sha256 = sha256 or known["sha256"],
        hub = name,
    )
    cli = dict(known.get("cli", {}))
    cli.update(cli_sha256)
    for plat in PLATFORMS.keys():
        _argocd_cli_repository(
            name = "{}_cli_{}".format(name, plat),
            version = version,
            platform = plat,
            sha256 = cli.get(plat, ""),
        )
