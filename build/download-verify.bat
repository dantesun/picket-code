@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Picket Code auto download + merge + verify (Windows cmd)
REM  Usage: download-verify.bat [TAG] [gitee|github]
REM  Example: download-verify.bat                  (default v1.143.1-p1, gitee)
REM           download-verify.bat v1.143.1-p5 github
REM ============================================================

set "TAG=%~1"
if "%TAG%"=="" set "TAG=v1.143.1-p1"
set "SOURCE=%~2"
if "%SOURCE%"=="" set "SOURCE=gitee"

set "HOST=https://gitee.com/dsun/picket-code"
if /i "%SOURCE%"=="github" set "HOST=https://github.com/dantesun/picket-code"

REM detect arch (win32-x64 is the current release; keep ARM compatible)
set "ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE:~0,3%"=="ARM" set "ARCH=arm64"
set "BASE=picket-code-win32-%ARCH%.zip"

echo == downloading %BASE% (source: %SOURCE%) ==
set "i=0"
:download
if %i% LSS 10 (set "segnum=0%i%") else (set "segnum=%i%")
set "SEG=%BASE%.%segnum%.part"
REM resume (-C -) + retry 5x + progress bar; fallback to full download if server rejects Range
curl -fL -C - --retry 5 --retry-delay 2 --progress-bar -o "%SEG%" "%HOST%/releases/download/%TAG%/%SEG%"
if errorlevel 1 (
  del "%SEG%" >nul 2>&1
  curl -fL --retry 5 --retry-delay 2 --progress-bar -o "%SEG%" "%HOST%/releases/download/%TAG%/%SEG%"
)
if errorlevel 1 (
  if %i% EQU 0 ( echo first segment download failed: %SEG% & exit /b 1 )
  del "%SEG%" >nul 2>&1
  goto merge
)
set /a i+=1
goto download

:merge
if %i% EQU 0 ( echo no segments downloaded & exit /b 1 )
echo == merging %i% segments ==
set "cmdline=copy /b %BASE%.00.part"
for /L %%j in (1,1,9) do ( if exist "%BASE%.0%%j.part" set "cmdline=!cmdline! + %BASE%.0%%j.part" )
for /L %%j in (10,1,99) do ( if exist "%BASE%.%%j.part" set "cmdline=!cmdline! + %BASE%.%%j.part" )
!cmdline! %BASE% >nul

echo == verifying SHA256 ==
curl -fSL --retry 3 -o MERGE.txt "%HOST%/releases/download/%TAG%/MERGE.txt" >nul 2>&1
certutil -hashfile "%BASE%" SHA256 > hash.txt
for /f "skip=1 delims=" %%h in (hash.txt) do (
  echo %%h | findstr /v /i "CertUtil" >nul && echo actual SHA256: %%h
)
del hash.txt >nul 2>&1
echo expected SHA256: compare with the "merged SHA256" values in the release description (MERGE.txt).
echo done. unzip %BASE% and use it.
endlocal
