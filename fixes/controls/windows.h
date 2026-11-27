// For the functions of this library that the game runs as Windows code: a COM method or an
// export pointed at a function here (mmdevapi.c, xaudio2.c).
//
// Such a function runs on one of the game's own threads, on its stack, and on some of Wine's
// builds with the Windows thread block in gs, where macOS keeps its own thread data. So it calls
// nothing of macOS, not even the C library: it keeps to memory it is handed and to Windows functions, reached through pointers
// (WINAPI is their calling convention). These helpers are all it has; they only read memory.
//
// They have no Windows unwind data, as nothing here has: an exception raised in a Windows
// function called from one of them could not unwind through it.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_WINDOWS_H
#define MGF_CONTROLS_WINDOWS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "mmdevapi.h"

#if defined(__x86_64__)
#define WINAPI __attribute__((ms_abi))

// The image an address is in: it starts at the nearest 64 KB boundary below that holds a PE
// header. NULL when none is found within 32 MB.
static inline const uint8_t *win_image_of(uintptr_t address) {
    const uint8_t *base = (const uint8_t *)(address & ~(uintptr_t)0xffff);
    for (unsigned i = 0; i < 0x200; i++, base -= 0x10000) {
        if (base[0] != 'M' || base[1] != 'Z') continue;
        uint32_t nt = *(const uint32_t *)(base + 0x3c);
        if (nt < 0x1000 - 0x108 && *(const uint32_t *)(base + nt) == 0x4550) return base;
    }
    return NULL;
}

// Where an image's export is, by name: code or data. NULL when it has none by that name, or
// forwards it to another module.
static inline void *win_export(const uint8_t *base, const char *wanted) {
    if (!base) return NULL;
    const uint8_t *opt = base + *(const uint32_t *)(base + 0x3c) + 24;
    uint32_t rva = *(const uint32_t *)(opt + 112), size = *(const uint32_t *)(opt + 116);
    if (!rva) return NULL;
    // The export directory: the count of names at 24, then the arrays of functions, names, ordinals.
    const uint32_t *d = (const uint32_t *)(base + rva);
    const uint32_t *functions = (const uint32_t *)(base + d[7]), *names = (const uint32_t *)(base + d[8]);
    const uint16_t *ordinals = (const uint16_t *)(base + d[9]);
    for (uint32_t i = 0; i < d[6]; i++) {
        const char *name = (const char *)base + names[i];
        unsigned c = 0;
        while (wanted[c] && name[c] == wanted[c]) c++;
        if (wanted[c] || name[c]) continue;
        uint32_t at = functions[ordinals[i]];
        return at >= rva && at < rva + size ? NULL : (void *)(base + at);
    }
    return NULL;
}

// The calling thread's id, from its thread block. The block is reached through its own address,
// which it keeps at 0x30, as Windows code reaches it: that one slot holds whether gs is the block
// itself or macOS's thread data with the block's address put there (CodeWeavers' Wine under
// Rosetta, where reading 0x48 from gs directly gave 0, 2026-11-27).
static inline uint32_t win_thread(void) {
    const uint8_t *block;
    __asm__("movq %%gs:0x30, %0" : "=r"(block));
    return *(const uint32_t *)(block + 0x48);
}

// A line for pad.log: sent through Wine's unix call dispatcher, which ntdll.dll exports a pointer
// to, to audio.c (mmdevapi.h). `ntdll` is any address inside ntdll.dll. Nothing is written where
// audio.c has not taken winecoreaudio.so's calls.
typedef int32_t (WINAPI *win_unix_call_fn)(uint64_t handle, uint32_t code, void *args);
static inline win_unix_call_fn win_dispatcher(uintptr_t ntdll) {
    win_unix_call_fn *exported = win_export(win_image_of(ntdll), "__wine_unix_call_dispatcher");
    return exported ? *exported : NULL;
}
static inline void win_log(uintptr_t ntdll, const char *text, uint64_t value) {
    struct mgf_log_request line = {&mgf_log_request_tag, text, value};
    win_unix_call_fn dispatcher = mgf_audio_unix_handle ? win_dispatcher(ntdll) : NULL;
    if (dispatcher) dispatcher(mgf_audio_unix_handle, UNIX_GET_PROP_VALUE, &line);
}

// A pointer in a page that may be read-only, written with ntdll.dll's NtProtectVirtualMemory.
typedef int32_t (WINAPI *win_protect_fn)(void *process, void **address, size_t *size, uint32_t protection, uint32_t *old);
static inline bool win_write_pointer(win_protect_fn protect, uintptr_t *slot, uintptr_t value) {
    void *address = slot;
    size_t size = sizeof(*slot);
    uint32_t old;
    if (!protect || protect((void *)(intptr_t)-1, &address, &size, 0x04 /* PAGE_READWRITE */, &old)) return false;
    *slot = value;
    address = slot;
    size = sizeof(*slot);
    protect((void *)(intptr_t)-1, &address, &size, old, &old);
    return true;
}
#endif

#endif
