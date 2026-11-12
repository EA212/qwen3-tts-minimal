@echo off
REM ===========================================================================
REM  Qwen3-TTS 极简环境 —— Windows 一键入口（无需安装 make）
REM
REM    make.bat            自动选 Docker Desktop（优先）或 WSL2，拉依赖并运行
REM    make.bat deps       只下载权重与 wheel
REM    make.bat docker     强制 Docker 路线
REM    make.bat wsl        强制 WSL2 路线
REM    make.bat verify     容器内生成自检音频
REM    make.bat help       帮助
REM
REM  注意：GGML 引擎没有 Windows 原生 wheel，必须借助 Docker Desktop 或 WSL2。
REM        详见 docs\Windows说明.md
REM ===========================================================================
setlocal
set TARGET=%1
if "%TARGET%"=="" set TARGET=all
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Target %TARGET%
exit /b %ERRORLEVEL%
