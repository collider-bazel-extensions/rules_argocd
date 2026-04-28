"""argocd_install — long-running `kubectl apply` of the toolchain's pinned
Argo CD manifest. Drops directly into `itest_service.exe`.

Pass the appropriate kubeconfig env-var name via `kubeconfig_env`. Under
rules_kind compositions, that's typically `KUBECONFIG` (after the consumer
sources rules_kind's per-cluster env file) — see the in-tree smoke test
for the canonical wrapper pattern.
"""

load("//private:providers.bzl", "ArgoCDInfo")  # buildifier: keep

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:argocd"]
    info = tc.argocd

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{MANIFEST}": info.manifest.short_path,
            "{NAMESPACE}": info.namespace,
            "{KUBECONFIG_ENV}": ctx.attr.kubeconfig_env,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [ctx.executable._launcher, info.manifest])
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [
        DefaultInfo(executable = out, runfiles = runfiles),
        info,
    ]

argocd_install = rule(
    implementation = _impl,
    attrs = {
        "kubeconfig_env": attr.string(
            default = "KUBECONFIG",
            doc = "Env var holding the path to the target cluster's " +
                  "kubeconfig. Defaults to `KUBECONFIG`.",
        ),
        "_launcher": attr.label(
            default = "//private:launcher",
            executable = True,
            cfg = "exec",
        ),
        "_tmpl": attr.label(
            default = "//private:install.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:argocd"],
    executable = True,
)
