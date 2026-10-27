#!/usr/bin/env bash
# Apply Picket Code / VSCodium patches to a vscode source tree.
#
# Usage: apply-patches.sh [vscode-source-dir]   (default: current directory)
#
# Three steps, applied in order:
#   1. product.json merge - build/product.json is merged over the upstream
#      product.json (VSCodium's `jq -s '.[0] * .[1]'`, done in python to avoid
#      a jq dependency on the Windows runners). Keys we do not set keep their
#      upstream value.
#   2. JSON actions (*.json in build/patches/) - physical removals, VSCodium
#      semantics: every remove path MUST exist, otherwise exit 4.
#   3. git apply patches listed in build/patches/apply-list.txt (one filename
#      per line, '#' comments allowed) - applied with --ignore-whitespace.
#      A patch that does not apply exits 1 and prints the failing files.
#
# Patches in build/patches/ that are NOT listed in apply-list.txt are stored
# but not applied yet (see build/patches/README.md for status).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"
VSCODE="${1:-$(pwd)}"
cd "$VSCODE"

echo "==> [picket-code] Patching vscode tree at $VSCODE"

command -v python3 >/dev/null || { echo "FATAL: python3 is required (product.json merge + JSON actions)" >&2; exit 1; }

# ---- 1. product.json merge ----
echo "==> [picket-code] product.json merge: build/product.json"
python3 - "$VSCODE/product.json" "$SCRIPT_DIR/product.json" <<'PYEOF'
import json, sys
target, overlay = sys.argv[1], sys.argv[2]
product = json.load(open(target, encoding='utf-8'))
patch = json.load(open(overlay, encoding='utf-8'))
product.update(patch)
with open(target, 'w', encoding='utf-8') as f:
    json.dump(product, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('  ' + str(len(patch)) + ' keys: ' + ', '.join(sorted(patch)))
PYEOF

# ---- 2. JSON actions (physical removals, VSCodium semantics) ----
for f in "$PATCHES_DIR"/*.json; do
  [ -e "$f" ] || continue
  echo "==> [picket-code] JSON actions: $(basename "$f")"
  python3 - "$f" <<'PYEOF'
import json, os, shutil, sys
manifest = json.load(open(sys.argv[1]))
for action in manifest:
    if action.get("action") != "remove":
        print(f"WARN: unsupported action {action.get('action')}", file=sys.stderr)
        continue
    for p in action.get("paths", []):
        if not os.path.exists(p):
            print(f"FATAL: {p} does not exist (removal failed)", file=sys.stderr)
            sys.exit(4)
        if os.path.isdir(p):
            shutil.rmtree(p)
        else:
            os.remove(p)
        print(f"  removed {p}")
PYEOF
done

# ---- 3. git apply patches (whitelist) ----
APPLY_LIST="$PATCHES_DIR/apply-list.txt"
if [ -f "$APPLY_LIST" ]; then
  CHECK_ERR="$(mktemp)"
  trap 'rm -f "$CHECK_ERR"' EXIT
  while IFS= read -r patch; do
    patch="$(echo "$patch" | sed 's/\r$//')"
    [ -z "$patch" ] && continue
    case "$patch" in \#*) continue;; esac
    echo "==> [picket-code] git apply: $patch"
    if ! git apply --ignore-whitespace --check "$PATCHES_DIR/$patch" 2>"$CHECK_ERR"; then
      echo "FATAL: $patch does not apply to this tree" >&2
      grep '^error:' "$CHECK_ERR" | head -20 >&2 || true
      exit 1
    fi
    git apply --ignore-whitespace "$PATCHES_DIR/$patch"
  done < "$APPLY_LIST"
fi

echo "==> [picket-code] All patches applied."
