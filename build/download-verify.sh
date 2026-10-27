#!/usr/bin/env bash
# Picket Code 自动下载 + 合并 + SHA256 校验（Linux/macOS）
# 支持：显式进度（curl 进度条 + 每段大小）、失败重试 5 次、断点续传（-C -）
# 用法: ./download-verify.sh [TAG] [gitee|github]
#   bash download-verify.sh                # 默认 v1.143.1-p4, gitee 源
#   bash download-verify.sh v1.143.1-p4 github
set -uo pipefail

TAG="${1:-v1.143.1-p4}"
SOURCE="${2:-gitee}"

MACH="$(uname -m)"
case "$MACH" in arm64|aarch64) ARCH="arm64";; *) ARCH="x64";; esac
BASE="picket-code-linux-$ARCH.tar.gz"
if [ "$(uname -s)" = "Darwin" ]; then BASE="picket-code-darwin-$ARCH.tar.gz"; fi

if [ "$SOURCE" = "github" ]; then
  PREFIX="https://github.com/dantesun/picket-code/releases/download/$TAG"
else
  PREFIX="https://gitee.com/dsun/picket-code/releases/download/$TAG"
fi

# 下载单文件：重试 5 次；优先断点续传（-C -），服务器不支持 Range 时自动降级全量
fetch() {
  local url="$1" path="$2" n=0 resume=1
  while :; do
    if [ "$resume" -eq 1 ] && [ -f "$path" ] && [ -s "$path" ]; then
      curl -fL -C - --retry 5 --retry-delay 2 --progress-bar -o "$path" "$url" 2>/dev/null
    else
      rm -f "$path" 2>/dev/null
      curl -fL --retry 5 --retry-delay 2 --progress-bar -o "$path" "$url" 2>/dev/null
    fi
    rc=$?
    [ $rc -eq 0 ] && return 0
    if [ $rc -eq 33 ]; then
      echo "  服务器不支持续传，改为全量下载" >&2
      resume=0
      rm -f "$path"
      continue
    fi
    n=$((n + 1))
    [ "$n" -ge 5 ] && return 1
    echo "  第 $n 次失败，2 秒后重试..." >&2
    sleep 2
  done
}

echo "== 下载 $BASE (源: $SOURCE, Tag: $TAG) =="
SEGS=()
i=0
while :; do
  s=$(printf '%02d' "$i")
  f="$BASE.$s.part"
  echo "  段 $s ..."
  if ! fetch "$PREFIX/$f" "$f"; then
    [ "$i" -eq 0 ] && { echo "第一段下载失败: $PREFIX/$f"; exit 1; }
    rm -f "$f"
    break
  fi
  echo "  段 $s 完成: $(du -h "$f" | cut -f1)"
  SEGS+=("$f")
  i=$((i + 1))
done
[ "${#SEGS[@]}" -eq 0 ] && { echo "未下载到任何分卷段"; exit 1; }

echo "== 合并 ${#SEGS[@]} 段 =="
cat "${SEGS[@]}" > "$BASE"

echo "== 校验 SHA256 =="
HASH=$(sha256sum "$BASE" | awk '{print $1}')
curl -fSL --retry 3 -o MERGE.txt "$PREFIX/MERGE.txt" 2>/dev/null || echo "警告: 无法下载 MERGE.txt，请与 Release 描述校验值手工比对"
EXPECTED=$(grep "合并后校验值.*${BASE} = " MERGE.txt 2>/dev/null | grep -oE '[0-9a-f]{64}' | tail -1)
if [ -n "$EXPECTED" ] && [ "$HASH" != "$EXPECTED" ]; then
  echo "校验失败!"
  echo "实际: $HASH"
  echo "预期: $EXPECTED"
  exit 1
elif [ -n "$EXPECTED" ]; then
  echo "校验通过: $BASE"
  echo "SHA256: $HASH"
else
  echo "SHA256: $HASH（无 MERGE.txt，请手工比对 Release 描述）"
fi
echo "完成。解压 $BASE 后即可使用。"
