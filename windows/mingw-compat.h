/*
 * mingw-w64 兼容补丁头（仅用于 Windows 交叉编译）
 *
 * 背景：ggml/src/ggml-cpu/ggml-cpu.c 用一段 `#if _WIN32_WINNT >= 0x0602`
 * 调用 Win10/11 的「线程功耗调节」API 来禁止系统把推理线程限速。
 * mingw-w64 的 winbase.h 已经声明了 SetThreadInformation 和
 * THREAD_INFORMATION_CLASS / ThreadPowerThrottling 枚举，libkernel32.a 里
 * 也有对应符号，唯独缺少下面这个结构体和两个常量宏（这些定义在新版
 * Windows SDK 的 winnt.h 中）。补齐后即可原样编译，不改动上游源码。
 *
 * 用法：交叉编译时给 C 编译器加  -include /path/to/mingw-compat.h
 */
#ifndef QWEN_MINGW_COMPAT_H
#define QWEN_MINGW_COMPAT_H

#ifdef _WIN32
#include <windows.h>

#ifndef THREAD_POWER_THROTTLING_CURRENT_VERSION
#define THREAD_POWER_THROTTLING_CURRENT_VERSION 1
#endif

#ifndef THREAD_POWER_THROTTLING_EXECUTION_SPEED
#define THREAD_POWER_THROTTLING_EXECUTION_SPEED 0x1
#endif

/* mingw-w64 未提供该结构体；与 Windows SDK winnt.h 定义保持一致 */
typedef struct _THREAD_POWER_THROTTLING_STATE {
    ULONG Version;
    ULONG ControlMask;
    ULONG StateMask;
} THREAD_POWER_THROTTLING_STATE;

#endif /* _WIN32 */
#endif /* QWEN_MINGW_COMPAT_H */
