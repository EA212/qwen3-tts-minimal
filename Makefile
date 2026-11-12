# =============================================================================
# Qwen3-TTS 极简环境 —— Linux / macOS / WSL2 一键构建
#
#   make                 拉依赖 + 建虚拟环境 + 启动 Web 服务（默认，一站式）
#   make help            列出所有目标
#   make deps            只下载权重与 wheel（支持断点续传 / 缓存复用）
#   make venv            只创建虚拟环境并安装依赖
#   make setup           deps + venv（不启动服务）
#   make run             启动 Web 服务（前台，Ctrl+C 停止）
#   make verify          命令行生成一段音频，自检环境是否可用
#   make docker-build    构建 Docker 镜像（自动先拉依赖）
#   make docker-run      后台启动容器
#   make clean           清理生成物（不动已下载的环境）
#   make distclean       删除 .venv（保留权重与 wheel）
#
# 常用变量：
#   make PORT=8080            改服务端口
#   make deps CACHE=/old/dir  复用本机已有环境，跳过 821 MB 下载
#   make PY=python3.11        指定 Python 解释器
# =============================================================================

SHELL  := /bin/bash
PY     ?= python3
PORT   ?= 3000
CACHE  ?=
IMAGE  ?= qwen3-tts-minimal:latest
ROOT   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
VENV   := $(ROOT)/.venv
VPY    := $(VENV)/bin/python
VPIP   := $(VENV)/bin/pip

.DEFAULT_GOAL := all
.PHONY: all help deps venv setup run verify docker-build docker-run clean distclean info

all: setup run                       ## 一站式：拉取依赖并启动服务

help:
	@echo "Qwen3-TTS 极简环境 · 可用目标："
	@echo "  make              拉依赖 + 建环境 + 启动服务（默认）"
	@echo "  make deps         只下载权重与 wheel"
	@echo "  make setup        拉依赖 + 建环境（不启动）"
	@echo "  make run          启动 Web 服务（前台）"
	@echo "  make verify       生成一段自检音频"
	@echo "  make docker-build 构建镜像 / make docker-run 后台启动容器"
	@echo "  make clean        清理生成物 / make distclean 删除 .venv"
	@echo "变量：PORT=8080  PY=python3.11  CACHE=/已有环境目录"

deps:                               ## 下载 2 个 GGUF + 2 个 wheel
	$(PY) fetch_deps.py $(if $(CACHE),--cache-dir $(CACHE),)

venv:                               ## 创建 .venv 并离线安装依赖
	@test -x "$(VPY)" || $(PY) -m venv "$(VENV)"
	@echo ">> 安装 numpy（优先用本地 wheel，缺失时回退在线）"
	$(VPIP) install -q --no-index --find-links=wheels -r requirements.txt \
	  || $(VPIP) install -q -r requirements.txt
	@echo ">> 安装 GGML 引擎（--no-deps 跳过可选依赖）"
	$(VPIP) install -q --no-index --no-deps wheels/qwentts_cpp_python-*.whl
	@$(VPY) -c "import numpy, qwentts_cpp; print('   numpy', numpy.__version__, '| engine OK')"

setup: deps venv                     ## 完整环境，不启动服务
	@echo ">> 环境就绪：$(VENV)"

run:                                ## 启动 Web 服务
	@./start.sh $(PORT)

verify:                             ## 命令行自检：生成一段音频
	$(VPY) synth.py --text "环境复现成功，这是自检音频。" --out audio/verify.wav

docker-build: deps                  ## 构建镜像（先确保 wheels/ models/ 齐全）
	docker build -t $(IMAGE) .

docker-run:                         ## 后台启动容器
	docker rm -f qwen3-tts >/dev/null 2>&1 || true
	docker run -d --name qwen3-tts -p $(PORT):3000 $(IMAGE)
	@echo ">> http://localhost:$(PORT)  （查看日志：docker logs -f qwen3-tts）"

info:                               ## 打印当前环境信息
	@echo "项目目录: $(ROOT)"
	@echo "Python  : $(PY) -> $$($(PY) -V 2>&1)"
	@echo "虚拟环境: $(VENV)"; [ -x "$(VPY)" ] && $(VPY) -V || echo "  (尚未创建，执行 make setup)"
	@echo "权重    :"; ls -lh models/*.gguf 2>/dev/null || echo "  (尚未下载，执行 make deps)"

clean:                              ## 只删生成物
	rm -rf __pycache__ audio/*.wav

distclean: clean                    ## 删除虚拟环境（保留昂贵的权重）
	rm -rf "$(VENV)"
