# Picket Code 自动下载安装 · AI 提示词

复制下方【任务】全文发给任意 AI 助手（豆包、Claude、Codex 等），AI 将自动完成下载、校验与安装：

---

【任务】请自动下载并安装 Picket Code v1.143.1-p5（当前最新发行版）。

1. 下载对应平台的自动脚本（脚本会自动下载发行包并做 SHA256 校验）：
   - Windows PowerShell: https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.ps1
   - Windows cmd: https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.bat
   - Linux/macOS: https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.sh
   若 GitHub 直连失败，改用 Gitee 源码镜像的同一路径（仅镜像源码，不含 Release 附件）：
   https://gitee.com/dsun/picket-code/raw/main/build/download-verify.ps1
2. 运行脚本：
   - Windows: powershell -ExecutionPolicy Bypass -File download-verify.ps1
   - Linux/macOS: bash download-verify.sh
3. 校验通过后，解压下载到的 zip/tar.gz，放置到合适目录（如 ~/picket-code）。
4. 启动：Windows 运行 Picket Code.exe；Linux 运行 ./picket-code。
5. 完成后报告：发行包 SHA256、校验结果、安装路径。
