"""Bzlmod extension. Same shape as rules_certmanager: one `version` tag class."""

load("//private:repositories.bzl", "argocd_version_repository")
load("//private:versions.bzl", "ARGOCD_VERSIONS")

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "argocd"),
    "version": attr.string(mandatory = True),
    # Pins for a version not in ARGOCD_VERSIONS (or to replace a known
    # version's): install.yaml's sha256 (url defaults to the upstream tag's
    # manifests/install.yaml), and the CLI binaries' shas by platform, from
    # the release's cli_checksums.txt.
    "url": attr.string(),
    "sha256": attr.string(),
    "cli_sha256": attr.string_dict(),
})

def _pins(tag):
    return struct(
        version = tag.version,
        url = tag.url,
        sha256 = tag.sha256,
        cli_sha256 = dict(tag.cli_sha256),
    )

def _tags_by_name(mod):
    repos = {}
    for tag in mod.tags.version:
        pins = _pins(tag)
        prev = repos.get(tag.name)
        if prev != None and prev != pins:
            fail("rules_argocd: {} sets argocd.version(name = \"{}\") twice, differently ({} and {}); set one.".format(
                "the root module" if mod.is_root else mod.name,
                tag.name,
                prev.version,
                pins.version,
            ))
        repos[tag.name] = pins
    return repos

def _impl(mctx):
    # The extension runs once for the whole build and sees every module's
    # tags; the repos it creates are global to it, so each name is created
    # once. rules_argocd's own MODULE.bazel imports `@argocd` and registers
    # its toolchain for every consumer, so its tags are the base and the
    # root module's tags override them by name (or add names). Other
    # modules' tags are ignored. A root without argocd.version() therefore
    # gets rules_argocd's pinned version. A version not in ARGOCD_VERSIONS
    # needs the tag's own sha256 (#7).
    own = {}
    root = {}
    for mod in mctx.modules:
        if mod.is_root:
            root = _tags_by_name(mod)
        elif mod.name == "rules_argocd":
            own = _tags_by_name(mod)
    repos = dict(own)
    repos.update(root)
    for name, pins in repos.items():
        if pins.version not in ARGOCD_VERSIONS and not pins.sha256:
            fail("rules_argocd: argocd.version(version = \"{}\") is not supported. Supported: {}. ".format(
                pins.version,
                ", ".join(sorted(ARGOCD_VERSIONS.keys())),
            ) + "For another version, pin it yourself: argocd.version(version = ..., sha256 = <install.yaml sha256>, cli_sha256 = {<platform>: <sha256>}).")
        argocd_version_repository(
            name = name,
            version = pins.version,
            url = pins.url,
            sha256 = pins.sha256,
            cli_sha256 = pins.cli_sha256,
        )

argocd = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
