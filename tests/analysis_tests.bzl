"""Analysis-time tests. Verify rules instantiate cleanly and expose
DefaultInfo without needing kubectl / a real cluster."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_argocd//:defs.bzl", "argocd_health_check", "argocd_install")

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def argocd_install_test_suite(name):
    argocd_install(name = name + "_subject", tags = ["manual"])
    _has_executable_test(name = name + "_executable", target_under_test = ":" + name + "_subject")
    native.test_suite(name = name, tests = [":" + name + "_executable"])

def argocd_health_check_test_suite(name):
    argocd_health_check(name = name + "_subject", tags = ["manual"])
    _has_executable_test(name = name + "_executable", target_under_test = ":" + name + "_subject")
    native.test_suite(name = name, tests = [":" + name + "_executable"])

def _cli_platform_impl(ctx):
    # The CLI symlinks the per-platform binary repo for the target platform.
    env = analysistest.begin(ctx)
    srcs = [
        f.path
        for a in analysistest.target_actions(env)
        if a.mnemonic == "ExecutableSymlink"
        for f in a.inputs.to_list()
    ]
    asserts.equals(env, 1, len(srcs), "expected one ExecutableSymlink input, got {}".format(srcs))
    asserts.true(
        env,
        len(srcs) == 1 and ("_cli_" + ctx.attr.platform + "/argocd") in srcs[0],
        "expected the {} binary, got {}".format(ctx.attr.platform, srcs),
    )
    return analysistest.end(env)

_cli_linux_arm64_test = analysistest.make(
    _cli_platform_impl,
    attrs = {"platform": attr.string(default = "linux_arm64")},
    config_settings = {
        "//command_line_option:platforms": str(Label("//tests:linux_arm64")),
    },
)

def argocd_cli_test_suite(name):
    """//:argocd selects the linux/arm64 binary for a linux/arm64 target."""
    _cli_linux_arm64_test(name = name + "_linux_arm64", target_under_test = "//:argocd")
    native.test_suite(name = name, tests = [":" + name + "_linux_arm64"])
