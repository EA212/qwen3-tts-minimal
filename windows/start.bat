@echo off
cd /d "%~dp0"
title Qwen3-TTS

REM tts-server.exe is fully self-contained: double-clicking it finds
REM models\ next to the exe, starts the server and opens the browser.
REM This BAT is just a convenience wrapper that keeps the window open
REM after the server exits. You do NOT need it to run the program.

echo.
echo   Qwen3-TTS  --  starting...
echo   URL: http://127.0.0.1:8080
echo   Loading about 820 MB of model weights, please wait.
echo   The browser opens automatically and reconnects once ready.
echo   Close this window to stop the server.
echo   (you can also double-click tts-server.exe directly)
echo.

tts-server.exe

echo.
echo Server stopped.
pause
