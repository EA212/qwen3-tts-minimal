@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title Qwen3-TTS - Model Downloader

echo.
echo   Qwen3-TTS  --  one-click model downloader
echo   ==================================================
echo   Files are saved into the  models  folder right here,
echo   next to tts-server.exe.
echo.

REM ---- 1. auto-create the models folder next to this BAT ----
if not exist "models\" (
    mkdir "models" 2>nul
    if errorlevel 1 (
        echo [ERROR] Cannot create folder: models
        echo         Try running this BAT from a writable location.
        goto failed
    )
    echo [OK] Created folder: models\
) else (
    echo [OK] Folder already exists: models\
)

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] curl.exe not found. Windows 10 1803+ is required.
    goto failed
)

set "BASE=https://www.modelscope.cn/models/tardigrade4ai/Qwen3-TTS-GGUF/resolve/master"

REM ---- 2. download both weights (size + SHA256 verified) ----
call :get "qwen-talker-0.6b-customvoice-Q4_K_M.gguf" 604878080 b3a7e6613d80f8a703c06267fc1e94d48ce91932ab82ab6e31c50f4ca4868e1e
if errorlevel 1 goto failed
call :get "qwen-tokenizer-12hz-Q4_K_M.gguf" 254974752 cf3788b4d50aaa665fb6e57c170396aae03a3555fea52d2b5d0cda902d658039
if errorlevel 1 goto failed

echo.
echo   ==================================================
echo    All done. Models are in the  models  folder.
echo    Now just DOUBLE-CLICK  tts-server.exe  to run.
echo    (it finds the models and opens the browser itself)
echo   ==================================================
echo.
pause
exit /b 0

:failed
echo.
echo   Download did not finish. Check your network and run
echo   this BAT again - it resumes / re-downloads safely.
echo.
pause
exit /b 1

REM ============================================================
:get
set "NAME=%~1"
set "EXPECTED=%~2"
set "SHA=%~3"
set "DST=models\%NAME%"
set "URL=%BASE%/%NAME%"

REM skip only if the file is already complete
if exist "%DST%" (
    for %%A in ("%DST%") do set "CUR=%%~zA"
    if "!CUR!"=="%EXPECTED%" (
        echo [skip] %NAME%  ^(already complete^)
        exit /b 0
    )
    echo [info] %NAME% incomplete ^(!CUR! bytes^), re-downloading
    del /f /q "%DST%" >nul 2>&1
)

echo.
echo [download] %NAME%
echo            %EXPECTED% bytes
curl.exe -L --fail --retry 3 --retry-delay 2 -# -o "%DST%" "%URL%"
if errorlevel 1 (
    echo [ERROR] Download failed: %NAME%
    exit /b 1
)

for %%A in ("%DST%") do set "CUR=%%~zA"
if not "!CUR!"=="%EXPECTED%" (
    echo [ERROR] Wrong size: got !CUR!, expected %EXPECTED%
    exit /b 1
)

echo [verify] checking SHA256 ...
powershell -NoProfile -Command "if ((Get-FileHash -Algorithm SHA256 -LiteralPath '%DST%').Hash.ToLower() -ne '%SHA%') { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] SHA256 mismatch: %NAME%
    echo         Delete the file and run this BAT again.
    exit /b 1
)
echo [ok] %NAME%  verified
exit /b 0
