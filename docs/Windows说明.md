# Windows 使用说明

## 先说结论

**Qwen3-TTS 的 GGML 引擎没有 Windows 原生 wheel，不能直接用 Windows 的 Python 跑。**

查过 PyPI 上 `qwentts-cpp-python` 的全部历史版本，发布过的平台标签只有：

```
manylinux_2_39_aarch64     Linux ARM64
manylinux_2_39_x86_64      Linux x86_64（CUDA 版）
manylinux_2_35_x86_64      Linux x86_64（CPU 版，本仓库用的）
macosx_14_0_arm64          macOS Apple Silicon
```

没有 `win_amd64`。hf-mirror 的 CPU wheel 仓库里也只有 `cpu / cu124 / cu128 / cu130 / metal / rocm724` 几类，
同样没有 Windows。引擎是 C++ + GGML，需要编译出 `.dll` 才能原生跑，上游目前没提供。

所以 Windows 上只有两条可行路线，本仓库都已一键封装：

| 路线 | 适合谁 | 命令 |
|---|---|---|
| **① Docker Desktop**（推荐） | 想要最贴近「最小镜像」、不想折腾 Linux 环境 | `make.bat docker` |
| **② WSL2** | 已有 WSL2、想在 Linux 里做二次开发 | `make.bat wsl` |

直接敲 `make.bat` 会自动检测：**有 Docker 就走 Docker，没有就转 WSL2**。

> 这两条路线跑的都是同一份 Linux wheel 和同一份 GGUF 权重，
> 和 Linux 机器上的效果完全一致，不是"阉割版"。

---

## 路线 ①：Docker Desktop（推荐）

### 准备

1. 安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)；
2. 设置里启用 **WSL2 backend**（默认即是）；
3. 启动 Docker Desktop，确认托盘图标正常；
4. 安装 **Python 3**（[python.org](https://www.python.org/downloads/)）——只用来跑纯标准库的 `fetch_deps.py` 下载依赖，不需要任何第三方包。

### 一键运行

```bat
git clone <你的仓库地址> qwen3-tts-minimal
cd qwen3-tts-minimal
make.bat
```

脚本依次做：

1. `python fetch_deps.py` —— 下载 2 个 GGUF + 2 个 wheel（约 840 MB，支持断点续传）；
2. `docker build -t qwen3-tts-minimal:latest .` —— 首次会拉 `python:3.11-slim`；
3. `docker run -d --name qwen3-tts -p 3000:3000 ...`；
4. 打印 `http://localhost:3000`。

成功后：

```bat
docker logs -f qwen3-tts        :: 看日志
make.bat verify                 :: 容器内生成自检音频，导出到 audio\verify.wav
docker rm -f qwen3-tts          :: 停止并删除
```

换端口：

```bat
powershell -File setup.ps1 -Target docker -Port 8080
```

更多 Docker 用法见 [Docker使用.md](Docker使用.md)。

---

## 路线 ②：WSL2

### 准备

管理员 PowerShell 执行（首次需要重启）：

```powershell
wsl --install
```

默认装的是 Ubuntu，glibc 版本满足 `manylinux_2_35` 要求。
在 WSL 里确认有 `make` 和 Python 3.11：

```bash
sudo apt update && sudo apt install -y make python3 python3-venv
python3 -V
```

### 在 WSL 里构建

**方式 A**：让 `make.bat wsl` 帮你下载依赖并调用 WSL 里的 make：

```bat
make.bat wsl
```

**方式 B**：全流程在 WSL 里做（更适合开发）：

```bash
# 在 WSL 终端里，Windows 的 D 盘对应 /mnt/d
cd /mnt/d/你的路径/qwen3-tts-minimal
make setup        # 拉依赖 + 建 .venv
make verify       # 自检
make run          # 启动服务，Windows 浏览器打开 http://localhost:3000
```

> WSL2 里 `localhost` 转发是自动的，Windows 浏览器直接能访问 WSL 里起的服务。

**注意**：`.venv` 必须在 WSL 内部创建（Linux 版 Python），
不要复用 Windows 的 venv；`make.bat wsl` 已经处理好这点。

---

## 关于两个 Make 文件

| 文件 | 用途 |
|---|---|
| `make.bat` | **零依赖**，CMD / 双击直接跑，内部调 PowerShell。绝大多数 Windows 用户用这个 |
| `Makefile.win` | 给装了 GNU make 的 Windows 环境（Git Bash / MSYS2 / `choco install make`）用：`make -f Makefile.win docker` |
| `Makefile` | Linux / macOS / WSL2 用（不要直接在 Windows CMD 里跑） |
| `setup.ps1` | PowerShell 核心逻辑，被前两者调用；也可直接 `powershell -File setup.ps1 -Target docker -Port 8080` |

`setup.ps1` 的目标：

| Target | 作用 |
|---|---|
| `all`（默认） | 自动选 Docker（优先）或 WSL2 |
| `deps` | 只下载并校验依赖 |
| `docker` | 强制 Docker Desktop 路线 |
| `wsl` | 强制 WSL2 路线 |
| `verify` | 容器内生成自检音频并导出 |
| `help` | 帮助 |

复用已有权重（省 840 MB 下载）：

```bat
powershell -File setup.ps1 -Target docker -Cache D:\旧目录\qwen3-tts-minimal
```

---

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `make.bat` 报「未找到 Python」 | 装 Python 3，或确认 `python` / `py` 在 PATH 里 |
| 报「Docker 未安装或未启动」 | 启动 Docker Desktop；或改用 `make.bat wsl` |
| 报「WSL2 未就绪」 | 管理员执行 `wsl --install` 并重启 |
| `docker build` 时 pip 报找不到 wheel | 依赖没下全。`make.bat deps` 重跑（支持断点续传）后重建 |
| `.\make.bat` 被策略拦截 | 用 `powershell -ExecutionPolicy Bypass -File setup.ps1 -Target all`；脚本本身无第三方依赖 |
| 想原生 Windows Python 跑 | 上游没有 `win_amd64` wheel。可自行用 MSVC 编译 `qwentts.cpp` 生成 `.dll` 并替换 wheel 里的动态库，但这超出本仓库范围 |
| 路径含中文/空格 | `setup.ps1` 已用引号包裹，正常；`make.bat wsl` 会自动做 `/mnt/<盘符>/...` 路径转换 |
| macOS 能不能用 | Apple Silicon 有 `macosx_14_0_arm64` wheel，但本仓库 `fetch_deps.py` 固定拉 Linux wheel。最简单是走 Docker Desktop |

---

## 一句话总结

Windows 上 `make.bat` = **下载依赖 + 在 Docker/WSL2 的 Linux 运行时里跑起来**，
不用手动装 CUDA、PyTorch 或任何深度学习框架，也不用自己编译 C++ 引擎。
