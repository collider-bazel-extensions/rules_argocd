"""Public API for rules_argocd."""

load("//private:argocd_health_check.bzl", _argocd_health_check = "argocd_health_check")
load("//private:argocd_install.bzl", _argocd_install = "argocd_install")
load("//private:providers.bzl", _ArgoCDInfo = "ArgoCDInfo")

argocd_install = _argocd_install
argocd_health_check = _argocd_health_check

ArgoCDInfo = _ArgoCDInfo
