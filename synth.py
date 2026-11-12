#!/usr/bin/env python3
"""命令行最小推理：验证环境 / 批量生成 / 测流式首包延迟。"""
import os

from envconfig import setup_threads

setup_threads()

import argparse
import time
import wave
from pathlib import Path

import numpy as np
from qwen_ggml import GGMLQwen3TTS

ROOT = Path(__file__).resolve().parent


def save(path, audio, sr):
    x = np.clip(np.asarray(audio, dtype=np.float32).reshape(-1), -1.0, 1.0)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(int(sr))
        f.writeframes((x * 32767.0).astype("<i2").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", default="你好，这是千问三语音合成的最小化部署。")
    ap.add_argument("--speaker", default="serena")
    ap.add_argument("--out", default="out.wav")
    ap.add_argument("--stream", action="store_true", help="流式生成并报告首包延迟")
    a = ap.parse_args()

    m = GGMLQwen3TTS.from_gguf(
        ROOT / "models" / "qwen-talker-0.6b-customvoice-Q4_K_M.gguf",
        ROOT / "models" / "qwen-tokenizer-12hz-Q4_K_M.gguf",
        log_level="error",
    )
    print("可用音色：", m.get_supported_speakers(), flush=True)

    t = time.time()
    if a.stream:
        chunks = []
        for i, item in enumerate(m.generate_custom_voice_streaming(
                text=a.text, speaker=a.speaker, language="Chinese", chunk_size=12)):
            if i == 0:
                print(f"首包出声：{time.time() - t:.2f}s", flush=True)
            c = item[0] if isinstance(item, tuple) else item
            chunks.append(np.asarray(c).reshape(-1))
        wav = np.concatenate(chunks)
        sr = 24000
    else:
        wavs, sr = m.generate_custom_voice(text=a.text, speaker=a.speaker,
                                           language="Chinese")
        wav = wavs[0]
    cost = time.time() - t
    save(a.out, wav, sr)
    dur = len(wav) / sr
    print(f"总耗时 {cost:.2f}s | 音频 {dur:.2f}s | RTF {cost / dur:.2f} | -> {a.out}")


if __name__ == "__main__":
    main()
