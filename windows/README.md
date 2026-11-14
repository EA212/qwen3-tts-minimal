# Qwen3-TTS · Windows 单文件版

**一个 exe，双击即用。不需要 Python、venv、pip、Docker、WSL2、CUDA，也不需要装 VC++ 运行库。**

原仓库主方案在 Windows 上必须借 Docker Desktop 或 WSL2 跑 Linux wheel；本目录提供的是 **原生 Windows x86_64 单文件程序**，把那层整个去掉。模型权重外置（约 820 MB，单独下载）。

| 文件 | 大小 | 说明 |
|---|---|---|
| `tts-server.exe` | 6.8 MB | **主程序**：本地 HTTP 服务 + 已内嵌的网页界面 |
| `qwen-tts.exe` | 5.5 MB | 命令行版，便于脚本/管道调用 |
| `start.bat` | — | 一键启动服务并打开浏览器 |
| `download-models.bat` / `.ps1` | — | 下载两个 GGUF 并校验 SHA256 |
| `index.html` | 8.6 KB | 与 exe 内嵌界面相同的独立副本（可选，可自行改） |
| `build-windows.sh` + `mingw-toolchain.cmake` + `mingw-compat.h` | — | 仅在需要重新编译时用到 |

## 三步使用

1. 把整个 `windows` 目录拷到任意 Windows 机器（可放 U 盘，无需安装）。
2. 双击 **`download-models.bat`**，下载约 820 MB 模型到 `models\`（带 SHA256 校验，可中断后重跑续传）。
3. 双击 **`start.bat`** → 浏览器自动打开 <http://127.0.0.1:8080> → 输入文字、选音色 → 生成并播放/下载 WAV。

> 首次启动要加载约 820 MB 权重，页面会**自动重连**，等它显示「服务就绪」即可。关闭黑窗口即停止服务。

## 依赖与要求

- **零外部 DLL**：只链接 Windows 系统自带的 `ADVAPI32 / KERNEL32 / msvcrt / WS2_32`，无需任何运行库。
- Windows 10 / 11，x86_64；内存建议 ≥ 4 GB（推理常驻约 2.7 GB）。
- CPU 需支持 **AVX2 / FMA / BMI2**（`x86-64-v3` 基线，2013 年后 Intel Haswell、2015 年后 AMD 及以后基本都支持）。
  - 老机器不支持 AVX2 时，用 `build-windows.sh` 把 `-march=x86-64-v3` 改成 `-march=x86-64-v2` 重新编译即可。
  - **不要改成 `-march=native`**：那会把编译机的 AVX-512 指令烧进 exe，在没有该指令集的机器上直接非法指令崩溃。

## 性能实测（同文本「线上端到端测试，一切正常。」）

| 环境 | 耗时 | 音频 | RTF |
|---|---|---|---|
| 原生 C++（Linux，4 核，AVX-512 机器 / 通用基线编译） | 7.8 s | 3.2 s | 2.45 |
| 原方案 Python + GGML wheel（同机） | 8.5–10.4 s | 3.9 s | ≈2.3 |
| **Wine 9.0 中的本 exe（仅功能验证）** | 40.1 s | 3.6 s | 11.1 |

结论要如实说清楚：

- **换成 C++ 原生版并没有让「推理」本身变快**——计算本来就在 C++ 引擎里，Python 只是薄封装。真实收益是省掉 Python 启动 + venv 开销（约 0.7–2.5 s），以及**彻底消灭整套运行环境**。
- 显式打开 AVX-512 / VNNI / BF16 专用 kernel 重编译，实测与 `-march=native` 版完全一致（均 7.83 s）。因为 `-march=native` 已隐含启用全部指令集，且 Q4_K_M 量化的瓶颈不在这些指令上——**编译层面的优化空间已经到头**。
- **Wine 的 40 s 是模拟层系统调用转换开销，不代表真实 Windows 性能**；Wine 只用来证明 exe 能完整跑通。真实 Windows 原生应接近原生 C++ 基准。已验证 `OMP_NUM_THREADS` 对引擎无效（线程数由 ggml 按硬件并发自动决定），无需手动调。
- 想更快只能靠硬件：单核性能更强、支持 AVX2 的 CPU；或缩短文本。

## 命令行 / 接口

```bat
:: 命令行版：从 stdin 读文字，输出 WAV
echo 你好，这是命令行测试。 | qwen-tts.exe --model models\qwen-talker-0.6b-customvoice-Q4_K_M.gguf --codec models\qwen-tokenizer-12hz-Q4_K_M.gguf --speaker serena --lang Chinese -o out.wav

:: 服务版：OpenAI 兼容接口（服务已在 start.bat 中启动）
curl -X POST http://127.0.0.1:8080/v1/audio/speech -H "Content-Type: application/json" -d "{\"input\":\"你好\",\"voice\":\"serena\",\"response_format\":\"wav\"}" -o out.wav
```

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 内嵌网页界面 |
| GET | `/health` | 健康检查 `{"status":"ok"}` |
| GET | `/v1/models` | 已加载模型 |
| GET | `/v1/audio/voices` | 音色列表 |
| POST | `/v1/audio/speech` | 生成语音，`response_format=wav` 一次性返回 WAV |
| POST / DELETE | `/v1/audio/voices` | 注册 / 删除克隆音色 |

请求字段：`input`（文本，必填）、`voice`、`language`、`instructions`、`response_format`（`wav` 或 `pcm` 流式）、`speed`，以及可选采样参数。服务自带宽松 CORS，可被任意本地网页调用。

**9 个预设音色**：`serena`、`vivian`、`uncle_fu`、`ryan`、`aiden`、`ono_anna`、`sohee`、`eric`、`dylan`。

## 已验证

在 Wine 9.0 中实跑通过：两个 exe 的 `--help`、`/` 内嵌网页（HTTP 200 / 8789 字节 / 正确标题）、`/health`、`/v1/models`、`/v1/audio/voices`（9 个音色）、以及连续两次 `POST /v1/audio/speech` 真实生成 24 kHz 单声道 WAV（3.60 s / 3.68 s）。二进制经 `objdump` 确认 **AVX-512 指令为 0**、依赖表只剩系统 DLL。

## 重新编译（可选）

在 Ubuntu 22.04 / Debian 上：

```bash
sudo apt-get install -y mingw-w64 cmake ninja-build curl
cd windows && ./build-windows.sh
```

脚本会自动拉源码（含 ggml 子模块）、内嵌网页、交叉编译并覆盖两个 exe。三个关键坑已在脚本里处理：

1. `mingw-compat.h` 补齐 mingw 头文件缺少的 `THREAD_POWER_THROTTLING_STATE` 等 Win10 API 定义（否则 `ggml-cpu.c` 编译失败）；
2. 用通用 `-march=x86-64-v3`，**绝不用 `-march=native`**；
3. 修正 FindOpenMP 塞进来的 `libgomp.dll.a`，让 OpenMP 真正静态链接（否则会多出一个 `libgomp-1.dll`，就不是单文件了）。

---

本目录与仓库主方案共用同一份模型权重；主方案仍是 Linux / macOS 上的极简底座，本目录是 Windows 的原生替代。
