#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no argocd.version() in the root resolves, and an argocd_install builds
#      against rules_argocd's pinned version
#   2. the same version set twice in the root resolves
#   3. an unsupported version fails, naming argocd.version
#   4. tests/ and tools/ are not shipped, and @rules_argocd//... loads
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_argocd"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
version="$(sed -n '/^argocd.version(/,/)/s/.*version = "\(.*\)".*/\1/p' "$src/MODULE.bazel")"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_argocd")
local_path_override(module_name = "rules_argocd", path = "$src")
$2
MOD
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_argocd//:defs.bzl", "argocd_install")

argocd_install(
    name = "argocd",
    kubeconfig_env = "KUBECONFIG",
)
BUILD
    echo "$c"
}

# 1. No argocd.version(): resolves, and the install builds with the pinned manifest.
c="$(consumer untagged "")"
(cd "$c" && bazel build //:argocd)
(cd "$c" && bazel mod show_extension @rules_argocd//:extensions.bzl%argocd) | tee "$work/untagged.out"
grep -q "$version" "$work/untagged.out" || { echo "FAIL: untagged consumer did not get Argo CD $version" >&2; exit 1; }
echo "PASS: untagged root resolves, Argo CD $version"

# 2. The same version twice in the root.
c="$(consumer twice "argocd = use_extension(\"@rules_argocd//:extensions.bzl\", \"argocd\")
argocd.version(version = \"$version\")
argocd.version(version = \"$version\")")"
(cd "$c" && bazel build //:argocd)
echo "PASS: repeated identical argocd.version resolves"

# 3. An unsupported version fails with a message naming argocd.version.
c="$(consumer unsupported 'argocd = use_extension("@rules_argocd//:extensions.bzl", "argocd")
argocd.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'argocd.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_argocd//... >/dev/null)
echo "PASS: @rules_argocd//... loads"
