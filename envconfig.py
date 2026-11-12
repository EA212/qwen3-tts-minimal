"""运行时环境自适应（纯标准库，零第三方依赖）。

必须在 import numpy / qwentts_cpp / qwen_ggml **之前**调用 setup_threads()，
因为 OpenMP 线程数在 GGML 动态库加载时就固定了。

取值优先级：
  1. 外部显式设置的 OMP_NUM_THREADS（完全尊重，便于手动调优）
  2. cgroup v2 cpu.max 配额 / cgroup v1 CFS 配额（容器、受限沙箱）
  3. os.process_cpu_count() / os.cpu_count()

这样在 4 核配额的容器里不会开出 32 个多余线程互相抢调度，
在用户自己的 32 核机器上也不会只用到 4 核。
"""
from __future__ import annotations

import os
from pathlib import Path


def cpu_budget() -> int:
    """返回当前进程实际可用的 CPU 核数。"""
    # cgroup v2：cpu.max 形如 "400000 100000" 或 "max 100000"
    try:
        q, p = Path("/sys/fs/cgroup/cpu.max").read_text().split()
        if q != "max" and int(p) > 0:
            return max(1, -(-int(q) // int(p)))  # 向上取整
    except (OSError, ValueError):
        pass
    # cgroup v1
    try:
        q = int(Path("/sys/fs/cgroup/cpu/cpu.cfs_quota_us").read_text())
        p = int(Path("/sys/fs/cgroup/cpu/cpu.cfs_period_us").read_text())
        if q > 0 and p > 0:
            return max(1, -(-q // p))
    except (OSError, ValueError):
        pass
    # 进程亲和性比 os.cpu_count() 更准确（taskset / cpuset 场景）
    try:
        return max(1, len(os.sched_getaffinity(0)))  # type: ignore[attr-defined]
    except (AttributeError, OSError):
        pass
    n = getattr(os, "process_cpu_count", None)
    return max(1, (n() if n else os.cpu_count()) or 4)


def setup_threads() -> int:
    """设定 OpenMP 系列环境变量，返回最终线程数。"""
    n = int(os.environ.get("OMP_NUM_THREADS") or cpu_budget())
    for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS",
                "MKL_NUM_THREADS", "GGML_NUM_THREADS"):
        os.environ.setdefault(key, str(n))
    return n
