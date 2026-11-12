#!/usr/bin/env python3
"""一键拉取运行所需依赖 —— 只用 Python 标准库，Linux / Windows / macOS 通用。

下载内容：
  models/*.gguf   Qwen3-TTS 0.6B CustomVoice 主模型 + 12Hz tokenizer（Q4_K_M 量化）
  wheels/*.whl    numpy + qwentts-cpp-python（GGML CPU 引擎预编译包）

特性：
  - 断点续传（HTTP Range），中断后重跑不会从头下载
  - 多源自动回退（魔搭 / hf-mirror / PyPI）
  - 文件大小 + SHA-256 双重校验，损坏文件自动重下
  - 已完成的自动跳过，可反复执行
  - --cache-dir 复用本机已有的依赖目录（离线复现 / 省流量）
  - --check 只校验不下载，用于自检

用法：
  python fetch_deps.py                     # 下载全部
  python fetch_deps.py --only wheels      # 只下 wheel
  python fetch_deps.py --check            # 只校验
  python fetch_deps.py --cache-dir /path/to/old/qwen3-tts-minimal
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
HEADERS = {"User-Agent": "qwen3-tts-minimal/1.0"}
TIMEOUT = 60

MODELSCOPE = "https://www.modelscope.cn"
HF_MIRROR = "https://hf-mirror.com"

# 权重与 wheel 的固定版本 / 大小 / 校验值，保证任何机器上复现出完全相同的环境。
FILES = [
    {
        "group": "models",
        "path": "models/qwen-talker-0.6b-customvoice-Q4_K_M.gguf",
        "size": 604878080,
        "sha256": "b3a7e6613d80f8a703c06267fc1e94d48ce91932ab82ab6e31c50f4ca4868e1e",
        "urls": [
            f"{MODELSCOPE}/models/tardigrade4ai/Qwen3-TTS-GGUF/resolve/master/qwen-talker-0.6b-customvoice-Q4_K_M.gguf",
            f"{MODELSCOPE}/api/v1/models/tardigrade4ai/Qwen3-TTS-GGUF/repo?Revision=master&FilePath=qwen-talker-0.6b-customvoice-Q4_K_M.gguf",
        ],
    },
    {
        "group": "models",
        "path": "models/qwen-tokenizer-12hz-Q4_K_M.gguf",
        "size": 254974752,
        "sha256": "cf3788b4d50aaa665fb6e57c170396aae03a3555fea52d2b5d0cda902d658039",
        "urls": [
            f"{MODELSCOPE}/models/tardigrade4ai/Qwen3-TTS-GGUF/resolve/master/qwen-tokenizer-12hz-Q4_K_M.gguf",
            f"{MODELSCOPE}/api/v1/models/tardigrade4ai/Qwen3-TTS-GGUF/repo?Revision=master&FilePath=qwen-tokenizer-12hz-Q4_K_M.gguf",
        ],
    },
    {
        "group": "wheels",
        "path": "wheels/qwentts_cpp_python-0.5.0+cpu-py3-none-manylinux_2_35_x86_64.whl",
        "size": 1065378,
        "sha256": "71aefbc34908503cef086dfef2e2549a03d9a0303c50a82562308019e3a9a77d",
        "urls": [
            f"{HF_MIRROR}/datasets/andito/qwentts-cpp-python-wheels/resolve/main/whl/cpu/qwentts_cpp_python-0.5.0%2Bcpu-py3-none-manylinux_2_35_x86_64.whl",
            "https://huggingface.co/datasets/andito/qwentts-cpp-python-wheels/resolve/main/whl/cpu/qwentts_cpp_python-0.5.0%2Bcpu-py3-none-manylinux_2_35_x86_64.whl",
        ],
    },
    {
        "group": "wheels",
        "path": "wheels/numpy-2.4.6-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl",
        "size": 16918164,
        "sha256": "89cd468399cfd2504718f0ba50e410dca55a170b61a02ad92bb18c8a65186e93",
        "urls": [
            "https://files.pythonhosted.org/packages/02/03/74fe2a4cb3817d94d86402f2506554130a2f01414e299b5a843e5a8a957f/numpy-2.4.6-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl",
        ],
    },
]


def log(msg: str) -> None:
    print(msg, flush=True)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(4 << 20), b""):
            h.update(block)
    return h.hexdigest()


def valid(path: Path, item: dict) -> bool:
    if not path.is_file() or path.stat().st_size != item["size"]:
        return False
    return sha256_of(path) == item["sha256"]


def human(n: int) -> str:
    return f"{n / 1e6:.1f} MB" if n < 1e9 else f"{n / 1e9:.2f} GB"


def from_cache(dst: Path, item: dict, cache: Path | None) -> bool:
    """从本机已有环境复用文件，避免重复下载 800 MB。"""
    if cache is None:
        return False
    src = cache / item["path"]
    if not valid(src, item):
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(src, dst)  # 同分区零拷贝
    except OSError:
        shutil.copy2(src, dst)
    log(f"  [缓存] {src} -> {dst.name}")
    return True


def download_one(url: str, dst: Path, item: dict) -> bool:
    """带断点续传的单源下载；成功返回 True。"""
    part = dst.with_suffix(dst.suffix + ".part")
    start = part.stat().st_size if part.is_file() else 0
    if start > item["size"]:
        part.unlink()
        start = 0

    headers = dict(HEADERS)
    if start:
        headers["Range"] = f"bytes={start}-"
        log(f"  [续传] 已有 {human(start)}，从断点继续")
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            # 服务端忽略 Range 时返回 200，需从头覆盖写
            if start and r.status == 200:
                start = 0
                mode = "wb"
            else:
                mode = "ab" if start else "wb"
            total = item["size"]
            with part.open(mode) as f:
                done, last, t0 = start, 0, time.time()
                while True:
                    buf = r.read(1 << 20)
                    if not buf:
                        break
                    f.write(buf)
                    done += len(buf)
                    if done - last >= 32 << 20 or done >= total:
                        last = done
                        pct = min(100, done / total * 100)
                        log(f"\r  {pct:5.1f}%  {human(done)} / {human(total)}   ", end="")
                        sys.stdout.flush()
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        log(f"\n  [失败] {type(e).__name__}: {e}")
        return False
    log("")
    if part.stat().st_size != item["size"]:
        log(f"  [大小不符] {part.stat().st_size} != {item['size']}")
        return False
    if sha256_of(part) != item["sha256"]:
        log("  [校验失败] SHA-256 不匹配，删除重试")
        part.unlink(missing_ok=True)
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    part.replace(dst)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description="Qwen3-TTS 极简环境依赖拉取器")
    ap.add_argument("--only", choices=["all", "models", "wheels"], default="all")
    ap.add_argument("--cache-dir", default=None, help="复用本机已有环境的目录（离线/省流量）")
    ap.add_argument("--check", action="store_true", help="只校验，不下载")
    a = ap.parse_args()
    cache = Path(a.cache_dir).resolve() if a.cache_dir else None
    items = [f for f in FILES if a.only == "all" or f["group"] == a.only]

    log(f"目标目录：{ROOT}")
    log(f"待处理 {len(items)} 个文件，合计 {human(sum(i['size'] for i in items))}\n")
    failed = []
    for item in items:
        dst = ROOT / item["path"]
        if valid(dst, item):
            log(f"[跳过] {item['path']}  ({human(item['size'])}) 已完整")
            continue
        if a.check:
            log(f"[缺失] {item['path']}")
            failed.append(item["path"])
            continue
        log(f"[下载] {item['path']}  ({human(item['size'])})")
        if from_cache(dst, item, cache) and valid(dst, item):
            continue
        ok = False
        for url in item["urls"]:
            log(f"  源：{url.split('/')[2]}")
            if download_one(url, dst, item):
                ok = True
                break
        if not ok:
            failed.append(item["path"])
            log(f"  [错误] 所有源均失败：{item['path']}")

    if failed:
        log("\n未完成：" + ", ".join(failed))
        log("可稍后重跑（支持断点续传），或检查网络后指定 --cache-dir。")
        return 1
    log("\n全部依赖就绪。下一步：make setup（Linux）或 make.bat（Windows / Docker）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
