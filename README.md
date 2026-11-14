# Qwen3-TTS 极简 CPU 部署

**一个可以 `git clone` 下来、`make` 一键跑起来的 Qwen3-TTS 最小环境。**

只用 **numpy + 一个 GGML C++ 引擎 wheel**，没有 PyTorch、Transformers、ModelScope、CUDA、Web 框架、ffmpeg。全部本地推理，文字不上传任何第三方。适合作为 Docker 镜像或后续二次开发的最小底座。

| 项目 | 值 |
|---|---|
| 模型 | Qwen3-TTS-12Hz-0.6B-CustomVoice（Q4_K_M 量化，9 个预设音色） |
| 推理引擎 | `qwentts.cpp` / GGML C++，预编译 wheel `qwentts-cpp-python 0.5.0+cpu` |
| Python 运行期依赖 | **numpy（仅此一个）** |
| Web 服务 | Python 标准库 `http.server`，约 200 行 |
| 音频 | 24 kHz / 16-bit 单声道 WAV，标准库 `wave` 直接输出 |
| 权重体积 | 821 MB（2 个 GGUF） |
| 镜像体积 | 约 1.09 GB（含权重） |
| 环境体积 | venv 约 100 MB |

---

## 快速开始

### Linux / macOS / WSL2

```bash
git clone https://github.com/EA212/qwen3-tts-minimal.git qwen3-tts-minimal
cd qwen3-tts-minimal
make                 # 拉依赖 + 建 venv + 启动服务，一条命令搞定
```

打开 <http://localhost:3000>，输入文字即可生成并下载音频。首次会下载约 840 MB。

### Windows

**推荐：原生单文件版（无需任何环境）**

[windows/](windows/) 目录提供编译好的原生 Windows x86_64 单文件程序，`tts-server.exe` 已内嵌网页界面，只依赖系统自带 DLL：

1. 把 `windows` 整个目录拷到目标 Windows 机器（U 盘即可，无需安装）；
2. 双击 `download-models.bat` 下载模型（约 820 MB，带 SHA256 校验）；
3. 双击 `start.bat`，浏览器自动打开 <http://127.0.0.1:8080> 即可使用。

不需要 Python、venv、pip、Docker、WSL2、CUDA 或 VC++ 运行库；`qwen-tts.exe` 另提供命令行版。详见 [windows/README.md](windows/README.md)（含 Wine 实跑验证、性能实测与重新编译方法）。

**备选：Docker / WSL2 方案（原主方案）**

GGML 引擎上游只发布 Linux / macOS 的预编译包，**没有 Windows 原生 wheel**，所以 `make.bat` 会自动选择 **Docker Desktop**（优先）或 **WSL2**，在 Linux 运行时里跑，不能直接用 Windows 的 Python：

```bat
git clone https://github.com/EA212/qwen3-tts-minimal.git qwen3-tts-minimal
cd qwen3-tts-minimal
make.bat
```

详见 [docs/Windows说明.md](docs/Windows说明.md)。

### Docker（任意平台）

```bash
python fetch_deps.py                # 或 make deps：先把 wheel 和权重拉到本地
docker build -t qwen3-tts-minimal .
docker run -p 3000:3000 qwen3-tts-minimal
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/环境复现.md](docs/环境复现.md) | 从零复现这套配置：依赖清单与校验值、目录结构、原理、验证步骤、性能基准、调优与排错 |
| [docs/Docker使用.md](docs/Docker使用.md) | 镜像构建、离线构建原理、卷挂载瘦身、多实例、日志与排错 |
| [docs/Windows说明.md](docs/Windows说明.md) | Windows 的 Docker Desktop / WSL2 两条路线、为什么不能原生跑、常见问题 |

---

## 目录结构

仓库里只有源码、文档和构建脚本（几十 KB）；**环境文件本地保留但不入库**。

```
qwen3-tts-minimal/
├── app.py             Web 服务（标准库 http.server + 任务队列 + 轮询）
├── synth.py           CLI 推理（支持 --stream 流式）
├── qwen_ggml.py       GGML 后端封装（单文件，来自 faster-qwen3-tts）
├── envconfig.py       线程数按 CPU 配额自适应（纯标准库）
├── fetch_deps.py      跨平台依赖下载器（断点续传 / 校验 / 缓存复用）
├── index.html         网页
├── requirements.txt   运行期依赖：numpy
├── Dockerfile         离线构建的极简镜像
├── Makefile           Linux / macOS / WSL2 一键
├── Makefile.win       Windows GNU make
├── make.bat           Windows 零依赖一键入口
├── setup.ps1          Windows PowerShell 核心逻辑
├── start.sh           Linux 启动脚本
├── .gitignore / .dockerignore
├── docs/              三份文档
│
├── .venv/             ← 本地环境，make setup 生成，不入库
├── models/            ← 2 个 GGUF，make deps 下载，不入库
├── wheels/            ← 2 个 wheel，make deps 下载，不入库
└── audio/             ← 生成的 WAV，不入库
```

---

## 常用命令

```bash
make help               # 所有目标
make deps               # 只下载依赖（断点续传，可反复执行）
make setup              # 拉依赖 + 建环境，不启动服务
make run                # 启动 Web 服务（前台）
make verify             # 命令行生成一段自检音频
make PORT=8080          # 换端口
make deps CACHE=/旧目录 # 复用已有环境，跳过 840 MB 下载
make docker-build / make docker-run
make clean              # 只清生成物
make distclean          # 删除 .venv（保留权重）
```

命令行推理：

```bash
.venv/bin/python synth.py --text "你好，这是本地合成。" --speaker serena --out out.wav
.venv/bin/python synth.py --stream --text "..." --out out.wav    # 打印首包延迟
```

HTTP 接口：`GET /api/info`、`POST /api/generate {"text","speaker"}`、`GET /api/status/<job_id>`、`GET /audio/<job_id>.wav`。

---

## 依赖来源与许可

| 组件 | 来源 | 许可 |
|---|---|---|
| `qwen_ggml.py` | 抽取自 [faster-qwen3-tts](https://pypi.org/project/faster-qwen3-tts/) 0.5.4 的 `ggml_backend.py`，仅把 `soundfile` 改为惰性导入 | MIT |
| `qwentts-cpp-python` wheel | [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) 的 GGML C++ 引擎预编译包（[CPU wheel 镜像](https://hf-mirror.com/datasets/andito/qwentts-cpp-python-wheels)） | 见上游仓库 |
| GGUF 权重 | 魔搭第三方仓库 `tardigrade4ai/Qwen3-TTS-GGUF`，由 Qwen3-TTS-12Hz-0.6B-CustomVoice 量化而来 | 遵循 Qwen 模型许可 |
| Web 服务 / 脚本 | 本项目 | 可自由使用 |

权重与 wheel **不随仓库分发**，由 `fetch_deps.py` 从上述公开地址拉取，并做大小 + SHA-256 校验。

---

## 已知边界

- **CPU 配额决定速度**：本环境曾在 4 核 cgroup 配额的机器上实测，同一句话约 15–19 秒生成 3 秒音频（RTF≈5），线程数超过配额不会更快。给足 CPU 核数才会线性变快。
- **平台要求**：引擎 wheel 为 `manylinux_2_35_x86_64`（需 glibc ≥ 2.35，如 Ubuntu 22.04+）；numpy wheel 为 CPython 3.11。macOS 需换成上游的 macOS wheel，Windows 走 Docker/WSL2。
- 网页当前是整段生成后再播放；`synth.py --stream` 已支持流式（首包约 3.5 秒）。
