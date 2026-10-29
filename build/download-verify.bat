@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Picket Code download + SHA256 verify (Windows cmd)
REM  Usage: download-verify.bat [TAG]
REM  Example: download-verify.bat                       (latest GitHub release)
REM           download-verify.bat v1.143.1-p2
REM
REM  Artifacts are versioned: picket-code-<tag>-win32-<arch>.zip
REM  and the checksum file is picket-code-<tag>-SHA256SUMS.
REM ============================================================

set "HOST=https://github.com/dantesun/picket-code"
set "TAG=%~1"
if "%TAG%"=="" (
  for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "(Invoke-RestMethod -Uri '%HOST%/releases/latest' -Headers @{ 'User-Agent' = 'picket-code-downloader' }).tag_name"`) do set "TAG=%%t"
)
if "%TAG%"=="" ( echo could not resolve the latest tag, pass one explicitly & exit /b 1 )

REM detect arch (win32-x64 is the current release; keep ARM compatible)
set "ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE:~0,3%"=="ARM" set "ARCH=arm64"
set "BASE=picket-code-%TAG%-win32-%ARCH%.zip"
set "SUMS=picket-code-%TAG%-SHA256SUMS"
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
if exist "%SUMS%" del "%SUMS%" >nul 2>&1
curl -fSL --retry 3 -o "%SUMS%" "%HOST%/releases/download/%TAG%/%SUMS%" >nul 2>&1
if exist "%SUMS%" (
  for /f "tokens=1,2 delims= " %%a in ('findstr /i /c:"%BASE%" "%SUMS%"') do (
    set "NAME=%%b"
    if "!NAME:~0,1!"=="*" set "NAME=!NAME:~1!"
    if /i "!NAME!"=="%BASE%" set "EXPECTED=%%a"
  )
)

if "!EXPECTED!"=="" (
  echo WARNING: %BASE% is not in %SUMS%, compare with the release notes.
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
