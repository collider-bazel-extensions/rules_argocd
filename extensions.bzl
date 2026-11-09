"""Bzlmod extension. Same shape as rules_certmanager: one `version` tag class."""

load("//private:repositories.bzl", "argocd_version_repository")
load("//private:versions.bzl", "ARGOCD_VERSIONS")

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "argocd"),
    "version": attr.string(mandatory = True),
})

def _tags_by_name(mod):
    repos = {}
    for tag in mod.tags.version:
        prev = repos.get(tag.name)
        if prev != None and prev != tag.version:
            fail("rules_argocd: {} sets argocd.version(name = \"{}\") to both {} and {}; set one.".format(
                "the root module" if mod.is_root else mod.name,
                tag.name,
                prev,
                tag.version,
            ))
        repos[tag.name] = tag.version
    return repos

def _impl(mctx):
    # The extension runs once for the whole build and sees every module's
    # tags; the repos it creates are global to it, so each name is created
    # once. rules_argocd's own MODULE.bazel imports `@argocd` and registers
    # its toolchain for every consumer, so its tags are the base and the
    # root module's tags override them by name (or add names). Other
    # modules' tags are ignored. A root without argocd.version() therefore
    # gets rules_argocd's pinned version.
    own = {}
    root = {}
    for mod in mctx.modules:
        if mod.is_root:
            root = _tags_by_name(mod)
        elif mod.name == "rules_argocd":
            own = _tags_by_name(mod)
    repos = dict(own)
    repos.update(root)
    for name, version in repos.items():
        if version not in ARGOCD_VERSIONS:
            fail("rules_argocd: argocd.version(version = \"{}\") is not supported. Supported: {}".format(
                version,
                ", ".join(sorted(ARGOCD_VERSIONS.keys())),
            ))
        argocd_version_repository(
            name = name,
            version = version,
        )

argocd = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
