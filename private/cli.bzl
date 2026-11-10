"""argocd_cli — the pinned argocd CLI binary as a runnable target (#5).

Each version hub (`@argocd`) declares `:argocd` with this rule, selecting the
per-platform binary repo for the target platform; `@rules_argocd//:argocd`
aliases the default hub's. `bazel run` runs it, and as a `data` dependency
its path is `$(rlocationpath ...)`.
"""

def _argocd_cli_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = out,
        target_file = ctx.file.binary,
        is_executable = True,
    )
    return [DefaultInfo(
        files = depset([out]),
        executable = out,
        runfiles = ctx.runfiles(files = [out]),
    )]

argocd_cli = rule(
    implementation = _argocd_cli_impl,
    executable = True,
    attrs = {
        "binary": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The argocd release binary for the target platform.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Argo CD version of the binary. Informational.",
        ),
    },
)
