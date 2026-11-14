#!/usr/bin/env bash
# 在 Linux (Ubuntu 22.04 / Debian) 上交叉编译出 Windows 单文件 exe。
# 需要提前安装： sudo apt-get install -y mingw-w64 cmake ninja-build curl
# 产物直接覆盖本目录下的 qwen-tts.exe / tts-server.exe。
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)          # <repo>/windows
UI="$HERE/index.html"
OUT="$HERE"
WORK=${WORK:-/tmp/qwentts-win-build}
mkdir -p "$WORK"; cd "$WORK"

# ---- 1. 源码（qwentts.cpp + ggml 子模块） ----
SRC=$(find "$WORK" -maxdepth 1 -type d -name "*qwentts.cpp*" | head -1 || true)
if [ -z "$SRC" ]; then
    echo "[1/6] 下载 qwentts.cpp ..."
    curl -sL -o src.tar.gz https://api.github.com/repos/ServeurpersoCom/qwentts.cpp/tarball/master
    tar xzf src.tar.gz
    SRC=$(find "$WORK" -maxdepth 1 -type d -name "*qwentts.cpp*" | head -1)
    echo "[1/6] 下载 ggml 子模块 ..."
    curl -sL -o ggml.tar.gz https://api.github.com/repos/ServeurpersoCom/ggml/tarball/master
    mkdir -p "$SRC/ggml"
    tar xzf ggml.tar.gz -C "$SRC/ggml" --strip-components=1
fi
echo "  源码: $SRC"

# ---- 2. 把 index.html 变成内嵌 UI 头文件 ----
echo "[2/6] 生成内嵌网页头文件 ..."
python3 - "$UI" "$SRC/src/embedded_ui.h" <<'PY'
import sys
html = open(sys.argv[1], encoding="utf-8").read()
assert ')QWENTTS_UI"' not in html, "raw string 分隔符冲突"
open(sys.argv[2], "w", encoding="utf-8").write(
    "// 由 windows/index.html 自动生成，勿手改\n#pragma once\n\n"
    "static const char k_qwen_ui_html[] = R\"QWENTTS_UI(" + html + ")QWENTTS_UI\";\n")
PY

# ---- 3. 给 tts-server.h 加 GET / 首页路由（幂等） ----
echo "[3/6] 注入首页路由 ..."
python3 - "$SRC/src/tts-server.h" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if '#include "embedded_ui.h"' not in s:
    i = s.find("#include")
    s = s[:i] + '#include "embedded_ui.h"\n' + s[i:]
anchor = '    svr.Get("/health", tts_handle_health);'
if 'svr.Get("/",' not in s:
    assert anchor in s, "找不到 health 路由锚点（上游改版？）"
    s = s.replace(anchor, anchor + '''
    svr.Get("/", [](const httplib::Request &, httplib::Response & res) {
        res.set_content(k_qwen_ui_html, "text/html; charset=utf-8");
    });''', 1)
open(p, "w", encoding="utf-8").write(s)
PY

# ---- 3b. 让 exe 双击即可运行（零参数自动找模型 + 自动开浏览器） ----
echo "[3b/6] 注入双击运行逻辑 ..."
python3 - "$SRC/tools/tts-server.cpp" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if 'QWEN_DOUBLE_CLICK_MODE' not in s:
    inc = '#include <vector>\n'
    assert inc in s, "找不到 include 锚点"
    s = s.replace(inc, inc + r'''
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#endif
#define QWEN_DOUBLE_CLICK_MODE 1
''', 1)

    old = r'''    if (!talker_path || !codec_path) {
        print_usage(argv[0]);
        return 1;
    }
'''
    new = r'''    // Double-click mode: with no --model/--codec, resolve the default GGUFs
    // from a models\ folder next to this exe and open the browser for the
    // embedded UI. Put the exe + models\ in one folder and that is the
    // entire install; no BAT, no command line, no Python.
    bool auto_open_browser = false;
    if (!talker_path && !codec_path) {
#ifdef _WIN32
        char exe_path[MAX_PATH] = { 0 };
        GetModuleFileNameA(NULL, exe_path, MAX_PATH);
        std::string dir(exe_path);
        const size_t slash = dir.find_last_of("\\/");
        dir = (slash == std::string::npos) ? std::string(".") : dir.substr(0, slash);
        static std::string auto_talker = dir + "\\models\\qwen-talker-0.6b-customvoice-Q4_K_M.gguf";
        static std::string auto_codec  = dir + "\\models\\qwen-tokenizer-12hz-Q4_K_M.gguf";
        talker_path = auto_talker.c_str();
        codec_path  = auto_codec.c_str();
        lang = "Chinese";
        auto_open_browser = true;

        auto file_exists = [](const char * p) -> bool {
            FILE * f = std::fopen(p, "rb");
            if (!f) return false;
            std::fclose(f);
            return true;
        };
        if (!file_exists(talker_path) || !file_exists(codec_path)) {
            std::fprintf(stderr, "\n[Qwen3-TTS] Model files not found.\n\n");
            std::fprintf(stderr, "  Put these two files in the models folder next to this exe:\n");
            std::fprintf(stderr, "    %s\n", auto_talker.c_str());
            std::fprintf(stderr, "    %s\n", auto_codec.c_str());
            std::fprintf(stderr, "\n  Run download-models.bat first, or copy them manually.\n");
            std::fprintf(stderr, "\nPress Enter to close...\n");
            std::getchar();
            return 1;
        }
#else
        print_usage(argv[0]);
        return 1;
#endif
    } else if (!talker_path || !codec_path) {
        print_usage(argv[0]);
        return 1;
    }
'''
    assert old in s, "找不到参数校验锚点（上游改版？）"
    s = s.replace(old, new, 1)

    old2 = '    int rc = tts_server_run(be, cfg);'
    new2 = r'''#ifdef _WIN32
    if (auto_open_browser) {
        char url[128];
        std::snprintf(url, sizeof(url), "http://%s:%d/", cfg.host.c_str(), cfg.port);
        // The embedded page auto-reconnects while the weights load, so
        // opening the browser slightly before listen() succeeds is fine.
        ShellExecuteA(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
    }
#endif
    int rc = tts_server_run(be, cfg);'''
    assert old2 in s, "找不到 server_run 调用点"
    s = s.replace(old2, new2, 1)
    open(p, "w", encoding="utf-8").write(s)
PY

# ---- 4. CMake 配置 ----
# -march=x86-64-v3 (AVX2/FMA/BMI2) 是通用基线，绝不能用 -march=native：
# 那会把编译机的 AVX-512 烧进 exe，在没有该指令集的用户机器上直接崩。
echo "[4/6] CMake 配置 ..."
BUILD="$SRC/build-win"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$HERE/mingw-toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_BLAS=OFF -DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="-O3 -march=x86-64-v3 -D_WIN32_WINNT=0x0A00 -DNOMINMAX -include $HERE/mingw-compat.h" \
  -DCMAKE_CXX_FLAGS="-O3 -march=x86-64-v3 -D_WIN32_WINNT=0x0A00 -DNOMINMAX" \
  -DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++ -lws2_32" \
  > /dev/null

# ---- 5. 修正 OpenMP 链接，保证真正零外部 DLL ----
# FindOpenMP 会把 libgomp.dll.a（DLL 导入库）以绝对路径写进 build.ninja，
# 导致 exe 依赖 libgomp-1.dll。删掉它，让 -fopenmp + -static 按 GCC spec
# 自动静态链接 libgomp.a（并自动带上 winpthread），即可得到纯单文件。
echo "[5/6] 修正 OpenMP 静态链接 ..."
GOMP_DLL=$(grep -oE '/[^ ]*/libgomp\.dll\.a' "$BUILD/build.ninja" | head -1 || true)
if [ -n "$GOMP_DLL" ]; then
    sed -i "s|$GOMP_DLL||g" "$BUILD/build.ninja"
fi
sed -i '/^  LINK_FLAGS = /{/fopenmp/!s/$/ -fopenmp/}' "$BUILD/build.ninja"

# ---- 6. 编译并交付 ----
echo "[6/6] 编译 ..."
ninja -C "$BUILD" qwen-tts tts-server -j "$(nproc)"
cp "$BUILD/qwen-tts.exe"   "$OUT/qwen-tts.exe"
cp "$BUILD/tts-server.exe" "$OUT/tts-server.exe"

echo
echo "完成。验证依赖（应只有 ADVAPI32/KERNEL32/msvcrt/WS2_32 等系统 DLL）："
for f in "$OUT"/*.exe; do
    echo "  $(basename "$f")  $(du -h "$f" | cut -f1)"
    x86_64-w64-mingw32-objdump -p "$f" | grep "DLL Name" | sed 's/^/    /'
done
