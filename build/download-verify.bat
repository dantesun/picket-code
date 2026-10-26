@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Picket Code 自动下载 + 合并 + 校验（Windows cmd 版）
REM  用法: download-verify.bat [TAG] [gitee|github]
REM  示例: download-verify.bat        (默认 v1.143.1-p1, gitee 源)
REM        download-verify.bat v1.143.1-p1 github
REM ============================================================

set "TAG=%~1"
if "%TAG%"=="" set "TAG=v1.143.1-p1"
set "SOURCE=%~2"
if "%SOURCE%"=="" set "SOURCE=gitee"

set "HOST=https://gitee.com/dsun/picket-code"
if /i "%SOURCE%"=="github" set "HOST=https://github.com/dantesun/picket-code"

REM 检测架构（仅发布 win32-x64 时可忽略，保留 ARM 兼容）
set "ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE:~0,3%"=="ARM" set "ARCH=arm64"
set "BASE=picket-code-win32-%ARCH%.zip"

echo == 下载 %BASE% (源: %SOURCE%) ==
set "i=0"
:download
if %i% LSS 10 (set "segnum=0%i%") else (set "segnum=%i%")
set "SEG=%BASE%.%segnum%.part"
curl -fSL --retry 3 -o "%SEG%" "%HOST%/releases/download/%TAG%/%SEG%" >nul 2>&1
if errorlevel 1 (
  if %i% EQU 0 ( echo 第一段下载失败: %SEG% & exit /b 1 )
  del "%SEG%" >nul 2>&1
  goto merge
)
set /a i+=1
goto download

:merge
if %i% EQU 0 ( echo 未下载到任何分卷段 & exit /b 1 )
echo == 合并 %i% 段 ==
set "cmdline=copy /b %BASE%.00.part"
for /L %%j in (1,1,9) do ( if exist "%BASE%.0%%j.part" set "cmdline=!cmdline! + %BASE%.0%%j.part" )
for /L %%j in (10,1,99) do ( if exist "%BASE%.%%j.part" set "cmdline=!cmdline! + %BASE%.%%j.part" )
!cmdline! %BASE% >nul

echo == 校验 SHA256 ==
curl -fSL --retry 3 -o MERGE.txt "%HOST%/releases/download/%TAG%/MERGE.txt" >nul 2>&1
certutil -hashfile "%BASE%" SHA256 > hash.txt
for /f "skip=1 delims=" %%h in (hash.txt) do (
  echo %%h | findstr /v /i "CertUtil" >nul && echo 实际 SHA256: %%h
)
del hash.txt >nul 2>&1
echo 预期 SHA256: 请与 release 页描述中的【合并后校验值】比对
echo 完成。解压 %BASE% 后即可使用。
endlocal
