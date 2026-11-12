#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# 线程数由 envconfig.setup_threads() 按 CPU 配额自适应；
# 需要手动调优时：OMP_NUM_THREADS=8 ./start.sh 3000
export PYTHONUNBUFFERED=1
if [ -x .venv/bin/python ]; then PY=.venv/bin/python; else PY=python3; fi
exec "$PY" app.py "${1:-3000}"
