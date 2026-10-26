#!/usr/bin/env bash
# split-for-gitee.sh — 将大资产分卷为 Gitee Release 兼容段（单段 < 100M）
# 用法: bash split-for-gitee.sh <资产目录> [每段上限，默认 95M]
# 产物: 原大文件替换为 .00.part/.01.part/... 段 + MERGE.txt + SHA256SUMS（含段与合并校验值）
set -euo pipefail

SRC_DIR="${1:?usage: split-for-gitee.sh <dir> [max-seg-size]}"
MAX="${2:-95M}"
MAX_BYTES=$(numfmt --from=iec "${MAX}" 2>/dev/null || echo 99614720)
cd "$SRC_DIR"

# 固定说明模板
rm -f MERGE.txt MERGE_TMP.txt
cat > MERGE_TMP.txt <<'EOF'
【分卷合并说明】

本发行版的大体积文件已按 Gitee 附件限制（单文件 100M）拆分为多个 .part 段。
请下载全部段后按以下步骤还原：

一、Windows（PowerShell 或 cmd 均可）

  假设拆分的是 picket-code-win32-x64.zip，段为：
    picket-code-win32-x64.zip.00.part
    picket-code-win32-x64.zip.01.part
    picket-code-win32-x64.zip.02.part

  cmd 合并（按文件名顺序，务必按 00、01、02 排列）：
    copy /b picket-code-win32-x64.zip.00.part + picket-code-win32-x64.zip.01.part + picket-code-win32-x64.zip.02.part picket-code-win32-x64.zip

  PowerShell 合并（推荐，自动按序）：
    Get-ChildItem "picket-code-win32-x64.zip.*.part" | Sort-Object Name | ForEach-Object { [System.IO.File]::AppendAllBytes("picket-code-win32-x64.zip", [System.IO.File]::ReadAllBytes($_.FullName)) }

二、Linux / macOS
    cat picket-code-win32-x64.zip.00.part picket-code-win32-x64.zip.01.part picket-code-win32-x64.zip.02.part > picket-code-win32-x64.zip

三、校验（必须执行）
    Windows: certutil -hashfile picket-code-win32-x64.zip SHA256
    Linux:   sha256sum picket-code-win32-x64.zip
    将输出与本说明末尾【合并后校验值】比对，一致即合并成功。

四、解压使用：还原出的 zip/tar.gz 与 GitHub Release 原始资产完全一致。
EOF

# 拆分大于上限的文件，记录原文件校验值
for f in *; do
	[ -f "$f" ] || continue
	[ "$f" = "MERGE.txt" ] || [ "$f" = "MERGE_TMP.txt" ] && continue
	size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
	if [ "$size" -gt "$MAX_BYTES" ]; then
		echo "== splitting: $f ($size bytes -> ${MAX}/seg)"
		orig_hash=$(sha256sum "$f" | awk '{print $1}')
		split -b "$MAX" -d -a 2 --additional-suffix=.part "$f" "${f}."
		rm -f "$f"
		printf '【合并后校验值】%s = %s\n' "$f" "$orig_hash" >> MERGE_TMP.txt
	fi
done

cat MERGE_TMP.txt > MERGE.txt
rm -f MERGE_TMP.txt

# 重算 SHA256SUMS（全部段 + MERGE.txt）
sha256sum * > SHA256SUMS.new
mv SHA256SUMS.new SHA256SUMS

echo "== done. 可上传 Gitee 的文件清单："
ls -la
