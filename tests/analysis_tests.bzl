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
