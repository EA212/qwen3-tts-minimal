#!/usr/bin/env python3
"""
Qwen3-TTS 极简服务 —— 零 Web 框架，只用 Python 标准库。

运行期依赖：numpy + qwentts-cpp-python（内含 GGML C++ 引擎预编译动态库）。
不需要 torch / transformers / modelscope / huggingface-hub / flask / ffmpeg。
"""
import os

# 必须在加载 GGML 动态库之前设定；线程数按 CPU 配额自适应，
# 需要手动调优时可在外部 export OMP_NUM_THREADS 覆盖。
from envconfig import setup_threads

THREADS = setup_threads()

import json
import queue
import sys
import threading
import time
import traceback
import uuid
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import numpy as np
from qwen_ggml import GGMLQwen3TTS

ROOT = Path(__file__).resolve().parent
TALKER = ROOT / "models" / "qwen-talker-0.6b-customvoice-Q4_K_M.gguf"
CODEC = ROOT / "models" / "qwen-tokenizer-12hz-Q4_K_M.gguf"
AUDIO = ROOT / "audio"
AUDIO.mkdir(exist_ok=True)

MAX_CHARS = 120
JOBS = {}
LOCK = threading.Lock()
TASKS = queue.Queue()
MODEL = None
SPEAKERS = []
MODEL_STATUS = "loading"
MODEL_ERROR = ""
MODEL_LOAD_SEC = 0


def load_model():
    global MODEL, SPEAKERS, MODEL_STATUS, MODEL_ERROR, MODEL_LOAD_SEC
    try:
        t = time.time()
        if not TALKER.exists() or not CODEC.exists():
            raise FileNotFoundError(f"缺少 GGUF 权重：{TALKER} / {CODEC}")
        MODEL = GGMLQwen3TTS.from_gguf(str(TALKER), str(CODEC), log_level="error")
        SPEAKERS = sorted(MODEL.get_supported_speakers())
        MODEL_LOAD_SEC = round(time.time() - t, 1)
        MODEL_STATUS = "ready"
        print(f"[ready] 加载 {MODEL_LOAD_SEC}s，音色 {len(SPEAKERS)} 个：{SPEAKERS}", flush=True)
    except Exception:
        MODEL_ERROR = traceback.format_exc()
        MODEL_STATUS = "error"
        print(MODEL_ERROR, flush=True)


def write_wav(path, audio, sr):
    x = np.clip(np.asarray(audio, dtype=np.float32).reshape(-1), -1.0, 1.0)
    pcm = (x * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(int(sr))
        f.writeframes(pcm.tobytes())
    return round(len(x) / sr, 2)


def worker():
    while True:
        jid = TASKS.get()
        with LOCK:
            job = JOBS[jid]
            job["state"] = "running"
            job["started"] = time.time()
        try:
            t = time.time()
            wavs, sr = MODEL.generate_custom_voice(
                text=job["text"],
                speaker=job["speaker"],
                language="Chinese",
                max_new_tokens=1024,
            )
            dur = write_wav(AUDIO / f"{jid}.wav", wavs[0], sr)
            with LOCK:
                job.update(state="done", elapsed=round(time.time() - t, 1),
                           duration=dur, wav=f"/audio/{jid}.wav")
            print(f"[{jid}] done {job['elapsed']}s / {dur}s 音频", flush=True)
        except Exception:
            with LOCK:
                job["state"] = "error"
                job["message"] = traceback.format_exc(limit=3)
            print(job["message"], flush=True)
        finally:
            TASKS.task_done()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        p = urlparse(self.path).path
        if p in ("/", "/index.html"):
            try:
                return self._send(200, (ROOT / "index.html").read_bytes(),
                                  "text/html; charset=utf-8")
            except Exception as e:
                return self._send(500, {"error": str(e)})
        if p == "/api/info":
            return self._send(200, {
                "status": MODEL_STATUS,
                "error": MODEL_ERROR[-800:] if MODEL_ERROR else "",
                "speakers": SPEAKERS,
                "engine": "qwentts.cpp / GGML",
                "quant": "Q4_K_M",
                "threads": THREADS,
                "load_sec": MODEL_LOAD_SEC,
                "queued": TASKS.qsize(),
                "max_chars": MAX_CHARS,
            })
        if p.startswith("/api/status/"):
            jid = p.rsplit("/", 1)[-1]
            with LOCK:
                snap = dict(JOBS[jid]) if jid in JOBS else None
            if snap is None:
                return self._send(404, {"error": "job not found"})
            if snap["state"] == "running":
                snap["elapsed"] = round(time.time() - snap["started"], 1)
                snap["eta"] = max(1, int(len(snap["text"]) * 1.6 - snap["elapsed"]))
            snap.pop("text", None)
            snap.pop("started", None)
            return self._send(200, snap)
        if p.startswith("/audio/") and p.endswith(".wav"):
            f = AUDIO / p.rsplit("/", 1)[-1]
            if not f.exists():
                return self._send(404, {"error": "not ready"})
            return self._send(200, f.read_bytes(), "audio/wav")
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if urlparse(self.path).path != "/api/generate":
            return self._send(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            return self._send(400, {"error": f"bad json: {e}"})
        if MODEL_STATUS != "ready":
            return self._send(503, {"error": "model not ready", "status": MODEL_STATUS})
        text = str(payload.get("text", "")).strip()
        if not text:
            return self._send(400, {"error": "text is empty"})
        text = text[:MAX_CHARS]
        speaker = str(payload.get("speaker") or (SPEAKERS[0] if SPEAKERS else ""))
        if SPEAKERS and speaker not in SPEAKERS:
            speaker = SPEAKERS[0]
        jid = uuid.uuid4().hex[:12]
        with LOCK:
            JOBS[jid] = {"job_id": jid, "state": "queued", "text": text,
                         "speaker": speaker, "submitted": time.time()}
            TASKS.put(jid)
        return self._send(200, {"job_id": jid, "state": "queued",
                               "position": TASKS.qsize()})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("PORT", "3000"))
    threading.Thread(target=load_model, daemon=True).start()
    threading.Thread(target=worker, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    srv.daemon_threads = True
    print(f"[boot] http://0.0.0.0:{port}  OMP_NUM_THREADS={os.environ['OMP_NUM_THREADS']}",
          flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
