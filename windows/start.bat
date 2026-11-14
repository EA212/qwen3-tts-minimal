@echo off
setlocal
cd /d "%~dp0"
title Qwen3-TTS Local Server

set "TALK=models\qwen-talker-0.6b-customvoice-Q4_K_M.gguf"
set "CODEC=models\qwen-tokenizer-12hz-Q4_K_M.gguf"

if not exist "%TALK%" goto missing
if not exist "%CODEC%" goto missing

echo.
echo   Qwen3-TTS  --  Windows single-file edition
echo   --------------------------------------------------
echo   URL     : http://127.0.0.1:8080
echo   Loading about 820 MB of model weights, please wait.
echo   A browser window opens automatically; the page will
echo   reconnect by itself once the model is ready.
echo   Close this window to stop the server.
echo.

start "" "http://127.0.0.1:8080/"
tts-server.exe --model "%TALK%" --codec "%CODEC%" --host 127.0.0.1 --port 8080 --lang Chinese

echo.
echo Server stopped.
pause
exit /b

:missing
echo.
echo   [Model files missing]
echo   Run download-models.bat first, or put these two files
echo   into the models\ folder:
echo     %TALK%
echo     %CODEC%
echo.
pause
