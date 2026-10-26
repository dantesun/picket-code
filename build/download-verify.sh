#!/usr/bin/env bash
# ============================================================
#  Picket Code 自动下载 + 合并 + SHA256 校验（Linux/macOS 版）
#  用法: bash download-verify.sh [TAG] [gitee|github]
#  示例: bash download-verify.sh                (默认 v1.143.1-p1, gitee 源)
#        bash download-verify.sh v1.143.1-p1 github
# ============================================================
set -euo pipefail

TAG="${1:-v1.143.1-p1}"
SOURCE="${2:-gitee}"

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  *) OS="linux" ;;
esac
case "$(uname -m)" in
  aarch64|arm64) ARCH="arm64" ;;
  *) ARCH="x64" ;;
esac

BASE="picket-code-$OS-$ARCH.tar.gz"
if [ "$SOURCE" = "github" ]; then
  HOST="github.com/dantesun/picket-code"
else
  HOST="gitee.com/dsun/picket-code"
fi
PREFIX="https://$HOST/releases/download/$TAG"

echo "== 下载 $BASE (源: $SOURCE) =="
SEGS=()
i=0
while :; do
  SEGN=$(printf "%s.%02d.part" "$BASE" "$i")
  if ! curl -fSL --retry 3 -o "$SEGN" "$PREFIX/$SEGN"; then
    [ "$i" -eq 0 ] && { echo "第一段下载失败: $PREFIX/$SEGN" >&2; exit 1; }
    break
  fi
  SEGS+=("$SEGN")
  i=$((i+1))
done
[ "${#SEGS[@]}" -eq 0 ] && { echo "未下载到任何分卷段" >&2; exit 1; }

echo "== 合并 ${#SEGS[@]} 段 =="
cat "${SEGS[@]}" > "$BASE"

echo "== 校验 SHA256 =="
HASH=$(sha256sum "$BASE" | awk '{print $1}')
curl -fSL --retry 3 -o MERGE.txt "$PREFIX/MERGE.txt"
EXPECTED=$(grep "合并后校验值.*${BASE} = " MERGE.txt | grep -oE '[0-9a-f]{64}' | tail -1)
if [ "$HASH" = "$EXPECTED" ]; then
  echo "校验通过: $BASE"
  echo "SHA256: $HASH"
  echo "完成。解压 $BASE 后即可使用。"
else
  echo "校验失败!" >&2
  echo "实际: $HASH" >&2
  echo "预期: $EXPECTED" >&2
  exit 1
fi
