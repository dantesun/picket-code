#!/usr/bin/env bash
# Compile stage of the Picket Code build (aligned with the VSCodium pipeline).
#
# Usage: build.sh <vscode-version> <picket-code-version> <linux|win32> [x64|arm64]
#
# This stage clones microsoft/vscode at the pinned tag, trims built-in
# extensions, applies Picket Code patches (product.json merge + Copilot removal),
# runs npm ci (with retry) and the upstream min build for this platform:
# `vscode-<platform>-<arch>-min`. Note: the old VSCodium task names
# (`vscode-min-prepack`, `vscode-<plat>-<arch>-min-packing`) no longer exist
# in the modern upstream gulpfile; `-min` produces the full product folder
# (VSCode-<platform>-<arch>) in the workspace root.
#
# The vscode/ tree AND the built VSCode-<platform>-<arch> folder are
# compressed into vscode.tar.gz and consumed by the per-platform package
# job, exactly like VSCodium's CI split. No packaging happens here, so a
# packaging failure never re-runs the ~4 min compile.
set -euo pipefail

VSCODE_VERSION="$1"
PICKET_VERSION="${2#v}"   # CI passes the git tag (v1.143.1-p5); keep the bare version
PLATFORM="${3:-linux}"
ARCH="${4:-x64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$PLATFORM" in
  linux|win32) ;;
  *) echo "Unknown platform: $PLATFORM (expected linux|win32)" >&2; exit 1 ;;
esac

case "$ARCH" in
  x64|arm64) ;;
  *) echo "Unknown arch: $ARCH (expected x64|arm64)" >&2; exit 1 ;;
esac

echo "==> [picket-code] Checking the release contract (tags / archive layout / js-debug)"
bash "$SCRIPT_DIR/check-contract.sh"

echo "==> [picket-code] Cloning microsoft/vscode@$VSCODE_VERSION"
rm -rf "$ROOT_DIR/vscode"
git clone --depth 1 --branch "$VSCODE_VERSION" \
  https://github.com/microsoft/vscode.git "$ROOT_DIR/vscode"

echo "==> [picket-code] Trimming built-in extensions to the minimal set"
cd "$ROOT_DIR/vscode"
REMOVE_COUNT=0
while IFS= read -r ext; do
  [ -z "$ext" ] && continue
  ext="${ext%$'\r'}"
  if [ -d "extensions/$ext" ]; then
    rm -rf "extensions/$ext"
    REMOVE_COUNT=$((REMOVE_COUNT + 1))
  else
    echo "WARN: extensions/$ext listed in build/extensions-remove.list but absent upstream" >&2
  fi
done < "$SCRIPT_DIR/extensions-remove.list"
echo "Removed $REMOVE_COUNT built-in extension dirs (see build/extensions-remove.list)"

echo "==> [picket-code] Applying Picket Code patches (product.json, Copilot, extension lists)"
bash "$SCRIPT_DIR/apply-patches.sh" "$ROOT_DIR/vscode"

echo "==> [picket-code] Installing dependencies (npm ci; retry up to 5 times)"
for i in 1 2 3 4 5; do
  if npm ci --no-audit --no-fund; then
    break
  fi
  if [ "$i" -eq 5 ]; then
    echo "npm ci failed 5 times" >&2
    exit 1
  fi
  echo "npm ci failed $i/5, retrying..." >&2
  sleep $(( 15 * (i + 1) ))
done

echo "==> [picket-code] Stamping product version"
# The packaged app reports `package.json`'s version (gulpfile.vscode.ts copies it into the
# built product.json). Build metadata (`+pN`) keeps the value semver-compatible with
# extension engine ranges, which a prerelease (`-pN`) would break.
case "$PICKET_VERSION" in
  *-*) PICKET_REV="${PICKET_VERSION##*-}" ;;
  *)   PICKET_REV="local" ;;
esac
python3 - "$VSCODE_VERSION" "$PICKET_REV" <<'PYEOF'
import json, sys
version = f'{sys.argv[1]}+{sys.argv[2]}'
with open('package.json', encoding='utf-8') as f:
    package = json.load(f)
package['version'] = version
with open('package.json', 'w', encoding='utf-8') as f:
    json.dump(package, f, indent=2, ensure_ascii=False)
    f.write('\n')
print(f'  package.json version = {version}')
PYEOF

echo "==> [picket-code] Building vscode-$PLATFORM-$ARCH-min"
export NODE_OPTIONS="--max-old-space-size=8192"
export VSCODE_PUBLISH_COUNTER=1
npm run gulp "vscode-$PLATFORM-$ARCH-min"

if [ ! -d "$ROOT_DIR/VSCode-$PLATFORM-$ARCH" ]; then
  echo "Build completed but output dir VSCode-$PLATFORM-$ARCH is missing" >&2
  exit 1
fi

echo "==> [picket-code] Compressing vscode/ + VSCode-$PLATFORM-$ARCH for the package stage"
cd "$ROOT_DIR"
tar -czf vscode.tar.gz \
  --exclude='vscode/node_modules' \
  --exclude='vscode/.git' \
  --exclude='vscode/.build/node' \
  vscode "VSCode-$PLATFORM-$ARCH"

echo "==> [picket-code] Compile stage done. Picket Code v$PICKET_VERSION ($PLATFORM-$ARCH) from VS Code $VSCODE_VERSION"
ls -lh "$ROOT_DIR/vscode.tar.gz"
