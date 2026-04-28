#!/usr/bin/env bash
# tools/update_versions.sh — refresh ARGOCD_VERSIONS in private/versions.bzl.
#
# Usage:
#     bash tools/update_versions.sh <version>            # add or update entry
#     bash tools/update_versions.sh <version> --update   # also auto-edit
#                                                        # private/versions.bzl
#
# Argo CD publishes manifests/install.yaml at the matching git tag, so this
# is just curl + sha256 — no helm rendering needed.
set -euo pipefail

VERSION="${1:?usage: tools/update_versions.sh <version> [--update]}"
UPDATE=0
[[ "${2:-}" == "--update" ]] && UPDATE=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSIONS_BZL="$REPO_ROOT/private/versions.bzl"
URL="https://raw.githubusercontent.com/argoproj/argo-cd/v${VERSION}/manifests/install.yaml"

WORKDIR=$(mktemp -d -t update-argocd-XXXXXX)
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

echo "[update_versions] fetching $URL"
curl -fsSL "$URL" -o "$WORKDIR/install.yaml"
SHA256=$(sha256sum "$WORKDIR/install.yaml" | awk '{print $1}')
SIZE=$(stat -c %s "$WORKDIR/install.yaml")

echo
echo "[update_versions] OK"
echo "    url:    $URL"
echo "    sha256: $SHA256"
echo "    bytes:  $SIZE"

if (( UPDATE )); then
    echo
    echo "[update_versions] updating $VERSIONS_BZL"
    python3 - "$VERSIONS_BZL" "$VERSION" "$URL" "$SHA256" <<'PY'
import re, sys
path, version, url, sha = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
src = open(path).read()
m = re.search(r"(ARGOCD_VERSIONS\s*=\s*\{)([\s\S]*?)(\n\})", src)
if not m:
    sys.exit("could not locate ARGOCD_VERSIONS dict in versions.bzl")
head, body, tail = m.group(1), m.group(2), m.group(3)
entry = (
    f'\n    "{version}": {{\n'
    f'        "url": "{url}",\n'
    f'        "sha256": "{sha}",\n'
    f'    }},'
)
existing = re.search(rf'\n    "{re.escape(version)}":[\s\S]*?\n    \}},', body)
new_body = (body[:existing.start()] + entry + body[existing.end():]) if existing else (body.rstrip(",\n ") + "," + entry)
new_src = src[:m.start()] + head + new_body + tail + src[m.end():]
open(path, "w").write(new_src)
print(f"  wrote ARGOCD_VERSIONS['{version}'] = sha256={sha}")
PY
    echo
    echo "Next: bump MODULE.bazel's \`argocd.version(version = \"$VERSION\")\` if you"
    echo "      want this to be the default version, then run"
    echo "      \`bazel test //tests:...analysis\` to verify."
else
    echo
    echo "Next steps (re-run with --update to do this automatically):"
    echo "  1. Add or update in private/versions.bzl::ARGOCD_VERSIONS:"
    echo
    echo "       \"$VERSION\": {"
    echo "           \"url\": \"$URL\","
    echo "           \"sha256\": \"$SHA256\","
    echo "       },"
    echo
    echo "  2. Bump MODULE.bazel's \`argocd.version(version = \"$VERSION\")\`."
    echo "  3. Run \`bazel test //tests:...analysis\` to verify."
fi
