# Qwen3-TTS 极简 CPU 镜像：无 PyTorch / CUDA / transformers / ModelScope / Web 框架
#
# 构建前必须先拉取依赖（仓库不含大文件）：
#   python fetch_deps.py      # 或 make deps
#   docker build -t qwen3-tts-minimal .
# 运行：docker run -p 3000:3000 qwen3-tts-minimal
#
# 仅基础镜像 python:3.11-slim 需联网拉取一次；所有 Python 依赖从 wheels/ 离线安装。
FROM python:3.11-slim

# 线程数由 envconfig.py 按容器 CPU 配额自适应，不再硬编码。
# 手动调优：docker run -e OMP_NUM_THREADS=8 ...
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# 1) 依赖：全部从本地 wheels/ 离线安装，构建阶段不访问 PyPI。
#    --no-deps 跳过 qwentts-cpp-python 声明的可选 huggingface-hub。
COPY requirements.txt ./
COPY wheels/ ./wheels/
RUN pip install --no-cache-dir --no-index --find-links=wheels/ -r requirements.txt \
 && pip install --no-cache-dir --no-index --no-deps --find-links=wheels/ wheels/qwentts_cpp_python-*.whl \
 && rm -rf wheels

# 2) 应用代码（标准库 Web 服务 + 抽出的 GGML 后端 + 自适应线程配置）
COPY envconfig.py qwen_ggml.py app.py synth.py index.html ./

# 3) 量化权重 Q4_K_M（约 821 MB）。
#    若想让镜像更小，删掉下一行并改用卷挂载：
#    docker run -p 3000:3000 -v "$(pwd)/models:/app/models" qwen3-tts-minimal
COPY models/ ./models/

RUN mkdir -p audio
EXPOSE 3000
CMD ["python3", "app.py", "3000"]
