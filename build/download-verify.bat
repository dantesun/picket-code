@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Picket Code download + SHA256 verify (Windows cmd)
REM  Usage: download-verify.bat [TAG]
REM  Example: download-verify.bat                  (default v1.143.1-p1)
REM           download-verify.bat v1.143.1-p1
REM
REM  The default TAG below must match download-verify.sh,
REM  download-verify.ps1 and docs/ai-download-prompt.md;
REM  build/check-contract.sh enforces that at build time.
REM ============================================================

set "TAG=%~1"
if "%TAG%"=="" set "TAG=v1.143.1-p1"
set "HOST=https://github.com/dantesun/picket-code"

REM detect arch (win32-x64 is the current release; keep ARM compatible)
set "ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE:~0,3%"=="ARM" set "ARCH=arm64"
set "BASE=picket-code-win32-%ARCH%.zip"
set "URL=%HOST%/releases/download/%TAG%/%BASE%"

echo == downloading %BASE% (tag: %TAG%) ==
REM resume (-C -) + retry 5x + progress bar; fallback to full download if server rejects Range
curl -fL -C - --retry 5 --retry-delay 2 --progress-bar -o "%BASE%" "%URL%"
if errorlevel 1 (
  del "%BASE%" >nul 2>&1
  curl -fL --retry 5 --retry-delay 2 --progress-bar -o "%BASE%" "%URL%"
)
if errorlevel 1 ( echo download failed: %URL% & exit /b 1 )

echo == verifying SHA256 ==
set "ACTUAL="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%BASE%" SHA256 2^>nul') do (
  if not defined ACTUAL set "ACTUAL=%%h"
)
REM Some certutil builds group the digest with spaces; normalise before comparing.
set "ACTUAL=!ACTUAL: =!"
if "!ACTUAL!"=="" ( echo could not compute SHA256 of %BASE% & exit /b 1 )

set "EXPECTED="
REM sha256sum writes "hash  name" (text mode) or "hash *name" (binary mode).
if exist SHA256SUMS del SHA256SUMS >nul 2>&1
curl -fSL --retry 3 -o SHA256SUMS "%HOST%/releases/download/%TAG%/SHA256SUMS" >nul 2>&1
if exist SHA256SUMS (
  for /f "tokens=1,2 delims= " %%a in ('findstr /i /c:"%BASE%" SHA256SUMS') do (
    set "NAME=%%b"
    if "!NAME:~0,1!"=="*" set "NAME=!NAME:~1!"
    if /i "!NAME!"=="%BASE%" set "EXPECTED=%%a"
  )
)

if "!EXPECTED!"=="" (
  echo WARNING: %BASE% is not in SHA256SUMS, compare with the release notes.
  echo actual SHA256: !ACTUAL!
  echo done. unzip %BASE% and use it.
  endlocal & exit /b 0
)
if /i "!ACTUAL!"=="!EXPECTED!" (
  echo verify OK: %BASE%
  echo SHA256: !ACTUAL!
  echo done. unzip %BASE% and use it.
  endlocal & exit /b 0
)
echo verify FAILED
echo actual SHA256:   !ACTUAL!
echo expected SHA256: !EXPECTED!
endlocal & exit /b 1
