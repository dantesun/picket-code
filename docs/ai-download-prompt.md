# Picket Code 自动下载安装 · AI 提示词

复制下方【任务】全文发给任意 AI 助手（豆包、Claude、Codex 等），AI 将自动完成下载、合并、校验与安装：

---

【任务】请自动下载并安装 Picket Code v1.143.1-p1（当前最新发行版）。

1. 下载对应平台的自动脚本（脚本会自动下载分卷段、合并、SHA256 校验）：
   - Windows PowerShell: https://gitee.com/dsun/picket-code/raw/main/build/download-verify.ps1
   - Windows cmd: https://gitee.com/dsun/picket-code/raw/main/build/download-verify.bat
   - Linux/macOS: https://gitee.com/dsun/picket-code/raw/main/build/download-verify.sh
2. 运行脚本：
   - Windows: powershell -ExecutionPolicy Bypass -File download-verify.ps1
   - Linux/macOS: bash download-verify.sh
3. 校验通过后，解压还原出的 zip/tar.gz，放置到合适目录（如 ~/picket-code）。
4. 启动：Windows 运行 Picket Code.exe；Linux 运行 ./picket-code。
5. 若 Gitee 下载慢或失败，改用 GitHub 源：
   - Linux: bash download-verify.sh v1.143.1-p1 github
   - Windows PowerShell: .\download-verify.ps1 -Source github
6. 完成后报告：合并文件 SHA256、校验结果、安装路径。
