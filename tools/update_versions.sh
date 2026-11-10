#!/usr/bin/env bash
# tools/update_versions.sh — refresh ARGOCD_VERSIONS in private/versions.bzl.
#
# Usage:
#     bash tools/update_versions.sh <version>            # add or update entry
#     bash tools/update_versions.sh <version> --update   # also auto-edit
#                                                        # private/versions.bzl
#
# Argo CD publishes manifests/install.yaml at the matching git tag, so this
# is just curl + sha256 — no helm rendering needed. The CLI binaries
# (argocd-<os>-<arch>, one per PLATFORMS entry) come from the release; their
# shas are read from the release's cli_checksums.txt and checked against the
# downloaded binaries.
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

CLI_PLATFORMS=(darwin_amd64 darwin_arm64 linux_amd64 linux_arm64)
REL="https://github.com/argoproj/argo-cd/releases/download/v${VERSION}"
echo "[update_versions] fetching $REL/cli_checksums.txt"
curl -fsSL "$REL/cli_checksums.txt" -o "$WORKDIR/cli_checksums.txt"
CLI_SHAS=()
for plat in "${CLI_PLATFORMS[@]}"; do
    asset="argocd-${plat/_/-}"
    want=$(awk -v a="$asset" '$2 == a {print $1}' "$WORKDIR/cli_checksums.txt")
    [[ -n "$want" ]] || { echo "no $asset in cli_checksums.txt" >&2; exit 1; }
    echo "[update_versions] fetching $REL/$asset"
    curl -fsSL "$REL/$asset" -o "$WORKDIR/$asset"
    got=$(sha256sum "$WORKDIR/$asset" | awk '{print $1}')
    [[ "$got" == "$want" ]] || { echo "$asset: sha256 $got, cli_checksums.txt says $want" >&2; exit 1; }
    rm -f "$WORKDIR/$asset"
    CLI_SHAS+=("$plat=$got")
done

echo
echo "[update_versions] OK"
echo "    url:    $URL"
echo "    sha256: $SHA256"
echo "    bytes:  $SIZE"
for kv in "${CLI_SHAS[@]}"; do
    echo "    cli ${kv%%=*}: ${kv#*=}"
done

if (( UPDATE )); then
    echo
    echo "[update_versions] updating $VERSIONS_BZL"
    python3 - "$VERSIONS_BZL" "$VERSION" "$URL" "$SHA256" "${CLI_SHAS[@]}" <<'PY'
import re, sys
path, version, url, sha = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
cli = dict(kv.split("=", 1) for kv in sys.argv[5:])
src = open(path).read()
m = re.search(r"(ARGOCD_VERSIONS\s*=\s*\{)([\s\S]*?)(\n\})", src)
if not m:
    sys.exit("could not locate ARGOCD_VERSIONS dict in versions.bzl")
head, body, tail = m.group(1), m.group(2), m.group(3)
entry = (
    f'\n    "{version}": {{\n'
    f'        "url": "{url}",\n'
    f'        "sha256": "{sha}",\n'
    f'        "cli": {{\n'
    + "".join(f'            "{p}": "{h}",\n' for p, h in sorted(cli.items()))
    + f'        }},\n'
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
    echo "           \"cli\": {"
    for kv in "${CLI_SHAS[@]}"; do
        echo "               \"${kv%%=*}\": \"${kv#*=}\","
    done
    echo "           },"
    echo "       },"
    echo
    echo "  2. Bump MODULE.bazel's \`argocd.version(version = \"$VERSION\")\`."
    echo "  3. Run \`bazel test //tests:...analysis\` to verify."
fi
