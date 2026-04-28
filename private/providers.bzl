"""Providers exported by rules_argocd."""

ArgoCDInfo = provider(
    doc = "The resolved Argo CD install: pinned version + path to the " +
          "downloaded, sha256-verified manifest YAML the consumer applies " +
          "into a cluster.",
    fields = {
        "version": "Argo CD version string, e.g. '3.3.8'.",
        "manifest": "File: the downloaded manifests/install.yaml.",
        "namespace": "string: namespace Argo CD installs into. Defaults to " +
                     "'argocd'. The upstream manifest does NOT contain a " +
                     "Namespace resource — argocd_install creates it before " +
                     "applying.",
    },
)
