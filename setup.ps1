# =============================================================================
# Qwen3-TTS 极简环境 —— Windows 一键脚本（PowerShell）
#
#   .\make.bat                  或  powershell -File setup.ps1
#   .\make.bat deps             只下载权重与 wheel
#   .\make.bat docker           Docker Desktop 路线（推荐）
#   .\make.bat wsl              WSL2 路线
#   .\make.bat verify           Docker 容器内生成一段自检音频
#   powershell -File setup.ps1 -Target docker -Port 8080 -Cache D:\old\qwen3-tts-minimal
#
# 重要：GGML 引擎没有 Windows 原生 wheel（上游只发布 Linux / macOS）。
#       因此 Windows 必须二选一：
#         ① Docker Desktop（推荐，最贴近最小镜像目标）
#         ② WSL2（在 Linux 子系统里跑 Makefile）
#       脚本会自动检测并优先选 Docker。
# =============================================================================
param(
    [ValidateSet('all','deps','docker','wsl','verify','help')]
    [string]$Target = 'all',
    [int]$Port = 3000,
    [string]$Cache = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "`n[错误] $msg" -ForegroundColor Red; exit 1 }

# ---- 定位 Python（fetch_deps.py 只用标准库，任何 Python 3.x 均可） ----
# 返回 'python' 或 'py'（后者用 py -3 调用）
function Get-Python {
    if (Get-Command python -ErrorAction SilentlyContinue) { return 'python' }
    if (Get-Command py -ErrorAction SilentlyContinue) { return 'py' }
    Fail '未找到 Python。请安装 Python 3（https://www.python.org/downloads/）后重试。'
}
$PY = Get-Python

function Invoke-Deps {
    Write-Step '拉取依赖（2 个 GGUF 权重 + 2 个 wheel，支持断点续传）'
    if ($PY -eq 'py') {
        if ($Cache) { & py -3 fetch_deps.py --cache-dir $Cache }
        else        { & py -3 fetch_deps.py }
    } else {
        if ($Cache) { & python fetch_deps.py --cache-dir $Cache }
        else        { & python fetch_deps.py }
    }
    if ($LASTEXITCODE -ne 0) { Fail '依赖下载未完成，可重跑（支持断点续传）。' }
}

function Test-Docker {
    $d = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $d) { return $false }
    & docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Docker {
    Write-Step '路线：Docker Desktop'
    if (-not (Test-Docker)) {
        Fail 'Docker 未安装或未启动。请安装 Docker Desktop 并启动后重试；或改用 ".\make.bat wsl" 走 WSL2 路线。'
    }
    Invoke-Deps
    Write-Step '构建镜像（首次需拉取 python:3.11-slim 基础镜像）'
    & docker build -t qwen3-tts-minimal:latest .
    if ($LASTEXITCODE -ne 0) { Fail '镜像构建失败。' }
    Write-Step "启动容器，端口 $Port"
    & docker rm -f qwen3-tts > $null 2>&1
    & docker run -d --name qwen3-tts -p "${Port}:3000" qwen3-tts-minimal:latest
    if ($LASTEXITCODE -ne 0) { Fail '容器启动失败。' }
    Write-Host "`n完成！打开 http://localhost:$Port" -ForegroundColor Green
    Write-Host '查看日志：docker logs -f qwen3-tts    停止：docker rm -f qwen3-tts' -ForegroundColor Gray
}

function Invoke-Wsl {
    Write-Step '路线：WSL2'
    $w = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $w) { Fail '未检测到 WSL。请先安装 WSL2（管理员 PowerShell 执行 wsl --install），或改用 Docker 路线。' }
    & wsl --status *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'WSL2 未就绪，请先执行 wsl --install 并重启。' }
    Invoke-Deps
    # Windows 路径转 WSL 路径：D:\a\b -> /mnt/d/a/b
    $drive = $Root.Substring(0,1).ToLower()
    $wslPath = "/mnt/$drive/" + $Root.Substring(3).Replace('\','/')
    Write-Step "在 WSL2 中执行 make setup（路径 $wslPath）"
    & wsl -e bash -lc "cd '$wslPath' && make setup && echo '环境就绪。后续在 WSL 里执行 make run'"
    if ($LASTEXITCODE -ne 0) { Fail 'WSL2 内构建失败，请查看上方输出。' }
}

function Invoke-Verify {
    if (-not (Test-Docker)) { Fail 'verify 需要 Docker。或先执行 .\make.bat docker。' }
    Write-Step '容器内生成自检音频'
    & docker exec qwen3-tts python3 synth.py --text "环境复现成功，这是自检音频。" --out /app/audio/verify.wav
    if ($LASTEXITCODE -ne 0) { Fail '自检失败，请先执行 .\make.bat docker。' }
    & docker cp qwen3-tts:/app/audio/verify.wav (Join-Path $Root 'audio\verify.wav')
    Write-Host '已导出 audio\verify.wav' -ForegroundColor Green
}

switch ($Target) {
    'help' {
        Write-Host @'
Qwen3-TTS 极简环境 · Windows 用法

  .\make.bat              自动选择 Docker（优先）或 WSL2，拉取依赖并运行
  .\make.bat deps         只下载权重与 wheel
  .\make.bat docker       强制走 Docker Desktop
  .\make.bat wsl          强制走 WSL2
  .\make.bat verify       Docker 容器内生成自检音频并导出
  .\make.bat help         本帮助

说明：引擎无 Windows 原生 wheel，必须借助 Docker Desktop 或 WSL2。
      详见 docs\Windows说明.md
'@
    }
    'deps'   { Invoke-Deps }
    'docker' { Invoke-Docker }
    'wsl'    { Invoke-Wsl }
    'verify' { Invoke-Verify }
    'all' {
        if (Test-Docker) { Invoke-Docker } else { Invoke-Wsl }
    }
}
