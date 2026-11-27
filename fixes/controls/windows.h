// For the functions of this library that the game runs as Windows code: a COM method or an
// export pointed at a function here (mmdevapi.c, xaudio2.c, xinput.c, hidclass.c).
//
// Such a function runs on one of the game's own threads, on its stack, and on some of Wine's
// builds with the Windows thread block in gs, where macOS keeps its own thread data. So it calls
// nothing of macOS, not even the C library: it keeps to memory it is handed and to Windows
// functions, reached through pointers (WINAPI is their calling convention). These helpers are all
// it has. They only read memory, but for win_call, which is how such a function reaches the macOS
// side of the library when it needs it.
//
// None of this has Windows unwind data: an exception raised in a Windows function called from
// one of these could not unwind through it.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_WINDOWS_H
#define MGF_CONTROLS_WINDOWS_H

#include <stdbool.h>
#include <stddef.h>
#include "nt.h"

// What win_call asks of the macOS side, each with what `data` points at (mgf-controls.c answers).
#define MGF_CALL_LOG 1        // struct mgf_log_line: a line for pad.log
#define MGF_CALL_CONTAINER 2  // struct mgf_container_request: an audio endpoint's container (audio.c)
struct mgf_log_line {
    const char *text;
    uint64_t value;  // printed after the text, in hexadecimal
};
struct mgf_container_request {
    uint16_t *endpoint;  // the endpoint's GUID as text, "{...}"; when found, its container instead: 16 bytes
    int found;
};
// The registry key no key is: a call to set a value of it is a call for this library, which
// container.c, holding NtSetValueKey's entry, hands to mgf_windows_call.
#define MGF_CALL_KEY ((HANDLE)(uintptr_t)0x4d474643)
NTSTATUS mgf_windows_call(uint32_t kind, void *data);

#if defined(__x86_64__)
#define WINAPI __attribute__((ms_abi))

// The calling thread's block. It is reached through its own address, which it keeps at 0x30, as
// Windows code reaches it: that one slot holds whether gs is the block itself or macOS's thread
// data with the block's address put there (CodeWeavers' Wine under Rosetta, where reading the
// thread id from gs directly gave 0, 2026-11-27).
static inline const uint8_t *win_thread_block(void) {
    const uint8_t *block;
    __asm__("movq %%gs:0x30, %0" : "=r"(block));
    return block;
}

static inline uint32_t win_thread(void) { return *(const uint32_t *)(win_thread_block() + 0x48); }

// A module the process has loaded, by its file's name ("ntdll.dll"), from the loader's own list:
// where its image starts, or NULL.
static inline const uint8_t *win_module(const char *name) {
    const uint8_t *peb = *(const uint8_t *const *)(win_thread_block() + 0x60);
    const uint8_t *loader = *(const uint8_t *const *)(peb + 0x18);
    const uint8_t *head = loader + 0x10, *entry = *(const uint8_t *const *)head;
    // Each entry: the list's links, the image's start at 0x30, its file's name at 0x58.
    for (unsigned i = 0; i < 1024 && entry && entry != head; i++, entry = *(const uint8_t *const *)entry) {
        const struct unicode_string *base_name = (const struct unicode_string *)(entry + 0x58);
        unsigned chars = base_name->length / 2, c = 0;
        while (c < chars && name[c] && (base_name->buffer[c] | 0x20) == (uint16_t)(name[c] | 0x20)) c++;
        if (c == chars && !name[c]) return *(const uint8_t *const *)(entry + 0x30);
    }
    return NULL;
}

// Where a module's export is, by name: code or data. NULL when it has none by that name, or
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

// The macOS side of the library asked for something (MGF_CALL_...): through ntdll.dll's
// NtSetValueKey, a system call like any other, with the key that is none.
static inline void win_call(uint32_t kind, void *data) {
    NTSTATUS (WINAPI *set_value)(HANDLE key, void *name, uint32_t index, uint32_t type, const void *data,
                                 uint32_t count) = win_export(win_module("ntdll.dll"), "NtSetValueKey");
    if (set_value) set_value(MGF_CALL_KEY, NULL, 0, kind, data, 0);
}

static inline void win_log(const char *text, uint64_t value) {
    struct mgf_log_line line = {text, value};
    win_call(MGF_CALL_LOG, &line);
}

// A pointer in a page that may be read-only, written with ntdll.dll's NtProtectVirtualMemory.
static inline bool win_write_pointer(uintptr_t *slot, uintptr_t value) {
    NTSTATUS (WINAPI *protect)(HANDLE process, void **address, size_t *size, uint32_t protection, uint32_t *old) =
        win_export(win_module("ntdll.dll"), "NtProtectVirtualMemory");
    void *address = slot;
    size_t size = sizeof(*slot);
    uint32_t old;
    if (!protect || protect((HANDLE)(intptr_t)-1, &address, &size, 0x04 /* PAGE_READWRITE */, &old)) return false;
    *slot = value;
    address = slot;
    size = sizeof(*slot);
    protect((HANDLE)(intptr_t)-1, &address, &size, old, &old);
    return true;
}
#endif

#endif
