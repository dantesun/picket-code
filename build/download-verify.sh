#!/usr/bin/env bash
# Picket Code 下载 + SHA256 校验（Linux/macOS）
# 支持：显式进度（curl 进度条）、失败重试 5 次、断点续传（-C -）
# 用法: ./download-verify.sh [TAG]
#   bash download-verify.sh              # 默认 v1.143.1-p5
#   bash download-verify.sh v1.143.1-p5
# 默认 TAG 需与 download-verify.bat / download-verify.ps1 /
# docs/ai-download-prompt.md 保持一致（build/check-contract.sh 会校验）。
set -uo pipefail

TAG="${1:-v1.143.1-p5}"
REPO="dantesun/picket-code"

MACH="$(uname -m)"
case "$MACH" in arm64|aarch64) ARCH="arm64";; *) ARCH="x64";; esac
BASE="picket-code-linux-$ARCH.tar.gz"
if [ "$(uname -s)" = "Darwin" ]; then BASE="picket-code-darwin-$ARCH.tar.gz"; fi
PREFIX="https://github.com/$REPO/releases/download/$TAG"

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

# macOS 只有 shasum
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

echo "== 下载 $BASE (Tag: $TAG) =="
fetch "$PREFIX/$BASE" "$BASE" || { echo "下载失败: $PREFIX/$BASE"; exit 1; }

echo "== 校验 SHA256 =="
HASH="$(sha256_of "$BASE")"
EXPECTED=""
rm -f SHA256SUMS
if fetch "$PREFIX/SHA256SUMS" SHA256SUMS; then
  # GNU coreutils writes "<hash>  <name>" (text mode) or "<hash> *<name>" (binary mode,
  # which is what the Windows runner produces).
  EXPECTED="$(awk -v f="$BASE" '{ n = $2; sub(/^\*/, "", n); sub(/\r$/, "", n) } n == f { print $1 }' SHA256SUMS | tail -1)"
fi
if [ -z "$EXPECTED" ]; then
  echo "警告: SHA256SUMS 中没有 $BASE，请与该 Release 的说明手工比对"
  echo "SHA256: $HASH"
  exit 0
fi
if [ "$HASH" != "$EXPECTED" ]; then
  echo "校验失败!"
  echo "实际: $HASH"
  echo "预期: $EXPECTED"
  exit 1
fi
echo "校验通过: $BASE"
echo "SHA256: $HASH"
echo "完成。解压 $BASE 后即可使用。"
