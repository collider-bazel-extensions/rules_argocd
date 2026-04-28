"""argocd_toolchain — exposes the pinned, sha256-verified Argo CD
manifest as a `ToolchainInfo` so consumer rules can resolve it without
depending on the manifest's specific path.
"""

load("//private:providers.bzl", "ArgoCDInfo")

ARGOCD_TOOLCHAIN_TYPE = Label("//toolchain:argocd")

def _toolchain_impl(ctx):
    info = ArgoCDInfo(
        version = ctx.attr.version,
        manifest = ctx.file.manifest,
        namespace = ctx.attr.namespace,
    )
    return [
        platform_common.ToolchainInfo(argocd = info),
        DefaultInfo(files = depset([ctx.file.manifest])),
    ]

argocd_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "manifest": attr.label(allow_single_file = True, mandatory = True),
        "namespace": attr.string(
            default = "argocd",
            doc = "Namespace Argo CD's manifest installs into. Default " +
                  "'argocd' matches the manifest's hard-coded references " +
                  "in ConfigMaps and RoleBindings.",
        ),
    },
)
