# Docker 使用指南

本仓库提供一个**完全离线构建**的极简 CPU 镜像：无 PyTorch / CUDA / transformers / ModelScope / Web 框架，
基础镜像只用一个 `python:3.11-slim`。

---

## 1. 最重要的前置步骤

**仓库本身不含权重和 wheel**（GitHub 单文件上限 100 MB，权重 605 MB 放不进去）。
所以 `docker build` 之前必须先把依赖拉到本地：

```bash
python fetch_deps.py          # 或 make deps
docker build -t qwen3-tts-minimal .
docker run -p 3000:3000 qwen3-tts-minimal
```

`make` 已经处理了这个顺序，可以直接：

```bash
make docker-build            # 自动先执行 deps，再 build
make docker-run              # 后台启动容器
```

> 如果跳过 `fetch_deps.py`，`Dockerfile` 里的 `COPY wheels/` / `COPY models/`
> 只会拿到空的 `.gitkeep`，`pip install --no-index` 会失败。这是最常见的构建报错原因。

---

## 2. 镜像是怎么构建的

`Dockerfile` 只有 4 步：

```dockerfile
FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1
WORKDIR /app

# ① 依赖：从本地 wheels/ 离线安装，构建阶段不访问 PyPI
COPY requirements.txt ./
COPY wheels/ ./wheels/
RUN pip install --no-index --find-links=wheels/ -r requirements.txt \
 && pip install --no-index --no-deps --find-links=wheels/ wheels/qwentts_cpp_python-*.whl \
 && rm -rf wheels

# ② 应用代码
COPY envconfig.py qwen_ggml.py app.py synth.py index.html ./

# ③ 权重（约 821 MB）
COPY models/ ./models/

RUN mkdir -p audio
EXPOSE 3000
CMD ["python3", "app.py", "3000"]
```

**为什么坚持离线 pip**：实测过容器内 `pip` 直连 PyPI 会卡住十几分钟（构建网络受限）。
把 numpy 和引擎的 wheel 放进构建上下文，`--no-index --find-links=wheels/` 只需约 5 秒，
而且**构建结果完全可复现**，不受 PyPI 版本变动影响。

`--no-deps` 是为了跳过 `qwentts-cpp-python` 声明里那个可选的 `huggingface-hub` —— 纯本地推理用不到它。

**体积构成**（约 1.09 GB）：

| 部分 | 大小 |
|---|---:|
| `python:3.11-slim` 基础镜像 | ~130 MB |
| numpy + 引擎 wheel | ~18 MB |
| 两个 GGUF 权重 | 821 MB |
| 应用代码 | < 100 KB |

`.dockerignore` 已排除 `.git`、`docs`、`.venv`、`audio/*.wav`、构建脚本等，
让构建上下文只留必要文件。

---

## 3. 运行方式

### 标准运行（自包含）

```bash
docker run -d --name qwen3-tts -p 3000:3000 qwen3-tts-minimal
docker logs -f qwen3-tts
# 打开 http://localhost:3000
```

查看状态：

```bash
curl -s localhost:3000/api/info | python3 -m json.tool
```

停止 / 删除：

```bash
docker rm -f qwen3-tts
```

### 卷挂载权重（镜像瘦身到 ~150 MB）

如果不想把 821 MB 打进镜像，改 `Dockerfile` 删掉 `COPY models/ ./models/` 那一行，重新构建后：

```bash
docker run -d --name qwen3-tts -p 3000:3000 \
  -v "$(pwd)/models:/app/models:ro" \
  -v "$(pwd)/audio:/app/audio" \
  qwen3-tts-minimal
```

好处：换权重不用重建镜像；多个容器共享一份权重；生成的 WAV 直接落宿主机 `audio/`。

### 换端口 / 限制核数 / 指定线程

```bash
docker run -d --name qwen3-tts -p 8080:3000 \
  --cpus=8 \
  -e OMP_NUM_THREADS=8 \
  qwen3-tts-minimal
```

`envconfig.py` 默认会读容器内的 `/sys/fs/cgroup/cpu.max` 自动定线程数，
所以 `--cpus=8` 时无需手动指定；显式设 `OMP_NUM_THREADS` 可覆盖。

> 注意：`--cpus` 是硬上限。开超过配额的线程数不会更快，反而增加上下文切换。
> 详见 [环境复现.md](环境复现.md#7-原理与性能基准)。

### 多实例

```bash
for p in 3001 3002 3003; do
  docker run -d --name qwen3-tts-$p -p $p:3000 --cpus=4 qwen3-tts-minimal
done
```

每个容器有独立的任务队列，CPU 配额之间互不干扰时吞吐接近线性。
若宿主机总配额本就只有 4 核，多实例只会互相拖慢（实测并发两请求会被饿死）。

### docker compose

新建 `compose.yaml`（仓库刻意不内置，保持最小）：

```yaml
services:
  tts:
    image: qwen3-tts-minimal:latest
    ports: ["3000:3000"]
    cpus: 8
    volumes:
      - ./audio:/app/audio
    restart: unless-stopped
```

```bash
docker compose up -d
docker compose logs -f
```

---

## 4. 容器内验证与调用

```bash
# 命令行生成一段自检音频
docker exec qwen3-tts python3 synth.py \
  --text "Docker 镜像内独立运行验证。" --speaker serena --out /app/audio/verify.wav
docker cp qwen3-tts:/app/audio/verify.wav ./verify.wav

# 走 HTTP
curl -s -X POST localhost:3000/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"text":"容器验证。","speaker":"dylan"}'
```

Windows 用户可以更简单：`make.bat verify` 会自动在容器里生成并导出 `audio\verify.wav`。

---

## 5. 迁移到别的机器

镜像与宿主机环境解耦，只要目标机器有 Docker：

```bash
# 机器 A
docker save qwen3-tts-minimal:latest | gzip > qwen3-tts.tar.gz

# 拷到机器 B
zcat qwen3-tts.tar.gz | docker load
docker run -p 3000:3000 qwen3-tts-minimal:latest
```

或者在目标机器上重新走一遍 `fetch_deps.py && docker build`（更省传输，因为只下权重不传镜像层）。

---

## 6. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `pip install` 报 `no matching distribution` | 没跑 `fetch_deps.py`，`wheels/` 是空的。先 `make deps` |
| 构建卡在 `pip install` 十几分钟 | 说明 Dockerfile 被改成在线安装了。恢复 `--no-index --find-links=wheels/` |
| `COPY models/ ...` 失败 | 同上，`models/` 只有 `.gitkeep`。先拉权重 |
| 容器起来了但 `/api/info` 是 `error` | `docker logs` 看具体错误；常见是权重损坏，重跑 `fetch_deps.py --check` 校验 |
| 拉取基础镜像慢 | 配置 Docker 镜像加速；`python:3.11-slim` 只需拉一次，之后命中缓存 |
| 容器里生成比宿主机慢 | 检查 `--cpus` 与 cgroup `cpu.max`；这是配额问题不是镜像问题 |
| 想让镜像更小 | 用卷挂载权重（第 3 节），或换 `python:3.11-alpine`（注意引擎 wheel 依赖 glibc，alpine 的 musl 不兼容，**不建议**） |
|  macOS / Windows 构建 | 依赖文件是一样的（都是 Linux wheel + GGUF），Docker Desktop 会构建 Linux 容器，流程完全相同 |

---

## 7. 为什么不用多阶段构建

试过评估：这个应用的依赖就是一个 numpy wheel 和一个 1 MB 的引擎 wheel，
编译产物不在镜像里（wheel 本身就是预编译好的），多阶段构建省不下体积，反而增加复杂度。
所以保持单阶段 —— 这也是"最小环境"的一部分。
