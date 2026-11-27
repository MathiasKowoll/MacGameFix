// The function FC 27's activation asks for: engine patch 0041 as a NotProton plugin, for
// EA SPORTS FC 27 alone.
//
// Wine 11.21 has GetPackagesByPackageFamily, which says no package is installed, and left
// FindPackagesByPackageFamily out of kernel32. EA SPORTS FC 27 imports it, its activation
// logs "Missing DLL: KERNEL32.dll Function: FindPackagesByPackageFamily", and the game ends
// at "There is a problem with your game's setup. Please reinstall your game." (2026-11-23).
//
// Patch 0041 adds the function to kernelbase.dll and kernel32.dll in the runner, for every
// game. This adds it in memory, in the game's process only, to the kernel32.dll Wine maps
// there: NotProton's plugin host lets this replace the syscall table's entry for
// NtMapViewOfSection, which Wine's loader maps every DLL with, and once kernel32.dll is
// mapped its export table gets one more name. The function answers as 0041's does, and as
// GetPackagesByPackageFamily does: no packages, ERROR_SUCCESS.
//
// HOW THE NAME GOES IN. Wine finds an export by a binary search of the export directory's
// sorted names (loader.c, find_name_in_exports), and takes a function whose address falls
// inside the export directory for a forward to another DLL; most of kernel32's are forwards
// to kernelbase. So the directory stays where it is, with its size, and only its three
// arrays are replaced: copies with one more entry, the name in its sorted place, in memory
// allocated within 4 GB above the image so every address is still an RVA. The new function
// is a few x86-64 instructions in that memory, outside the directory, so it is not taken for
// a forward. The directory's page is made writable for the five fields and given its
// protection back. A kernel32.dll that already has the name (a runner with 0041) is left as
// it is.
//
// It is part of mgf-engine.dylib (../mgf-engine.c), which arms it in FC 27 alone; FC 27's fix
// (install-fc27-live-editor.sh) switches the engine row on for the game. build-engine.sh builds
// it, and runs the check (check.c): a Windows program that looks the function up and calls it,
// under the runner with and without this fix armed.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../mgf_hooks.h"

#include <stdint.h>
#include <string.h>

#define TAG "package-family"

typedef int32_t NTSTATUS;
typedef void *HANDLE;

#define CURRENT_PROCESS ((HANDLE)(intptr_t)-1)
#define MEM_COMMIT 0x1000
#define MEM_RESERVE 0x2000
#define MEM_RELEASE 0x8000
#define PAGE_READWRITE 0x04
#define PAGE_EXECUTE_READ 0x20

static const char NAME[] = "FindPackagesByPackageFamily";

// LONG FindPackagesByPackageFamily(const WCHAR *family, UINT32 filters, UINT32 *count,
//                                  WCHAR **full_names, UINT32 *buffer_len, WCHAR *buffer,
//                                  UINT32 *properties), the Windows x64 convention: count in
// r8, buffer_len the fifth argument, at [rsp+0x28] on entry. No count or no buffer_len is
// ERROR_INVALID_PARAMETER (87); otherwise both are 0 and the answer is ERROR_SUCCESS.
static const unsigned char FUNCTION[] = {
    0x4d, 0x85, 0xc0,                         //  0: test r8, r8
    0x74, 0x1a,                               //  3: jz   bad (31)
    0x48, 0x8b, 0x44, 0x24, 0x28,             //  5: mov  rax, [rsp+0x28]
    0x48, 0x85, 0xc0,                         // 10: test rax, rax
    0x74, 0x10,                               // 13: jz   bad (31)
    0x41, 0xc7, 0x00, 0x00, 0x00, 0x00, 0x00, // 15: mov  dword [r8], 0
    0xc7, 0x00, 0x00, 0x00, 0x00, 0x00,       // 22: mov  dword [rax], 0
    0x31, 0xc0,                               // 28: xor  eax, eax
    0xc3,                                     // 30: ret
    0xb8, 0x57, 0x00, 0x00, 0x00,             // 31: bad: mov eax, 87
    0xc3,                                     // 36: ret
};

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*map_fn)(HANDLE section, HANDLE process, void **addr, uintptr_t zero_bits, size_t commit,
                           const int64_t *offset, size_t *size, uint32_t inherit, mgf_stack_u32 type,
                           mgf_stack_u32 protect);
typedef NTSTATUS (*alloc_fn)(HANDLE process, void **addr, uintptr_t zero_bits, size_t *size, uint32_t type,
                             uint32_t protect);
typedef NTSTATUS (*protect_fn)(HANDLE process, void **addr, size_t *size, uint32_t prot, uint32_t *old);
typedef NTSTATUS (*free_fn)(HANDLE process, void **addr, size_t *size, uint32_t type);

static const struct np_plugin_api *api;
static map_fn real_map;
static alloc_fn alloc;
static protect_fn protect;
static free_fn release;
static int done;

// The parts of a PE image this reads, by their offsets.
struct export_directory {
    uint32_t characteristics, time_date_stamp;
    uint16_t major, minor;
    uint32_t name, base, number_of_functions, number_of_names;
    uint32_t address_of_functions, address_of_names, address_of_name_ordinals;
};

static void *rva(uint8_t *base, uint32_t r) { return base + r; }

// The image's export directory and its size when it is a 64-bit PE, else NULL.
static struct export_directory *exports_of(uint8_t *base, uint32_t *image_size, uint32_t *dir_size) {
    if (base[0] != 'M' || base[1] != 'Z') return NULL;
    uint32_t nt = *(uint32_t *)(base + 0x3c);
    if (nt > 0x1000 || memcmp(base + nt, "PE\0\0", 4)) return NULL;
    uint8_t *opt = base + nt + 24;
    if (*(uint16_t *)opt != 0x20b) return NULL;                // PE32+
    if (*(uint32_t *)(opt + 108) < 1) return NULL;             // NumberOfRvaAndSizes
    uint32_t dir = *(uint32_t *)(opt + 112), size = *(uint32_t *)(opt + 116);
    *image_size = *(uint32_t *)(opt + 56);                     // SizeOfImage
    if (!dir || size < sizeof(struct export_directory) || dir >= *image_size) return NULL;
    *dir_size = size;
    return rva(base, dir);
}

static int named(uint8_t *base, struct export_directory *d, const char *want) {
    const char *name = rva(base, d->name);
    for (; *want; name++, want++)
        if ((*name | 0x20) != (*want | 0x20)) return 0;
    return !*name;
}

// Memory for the new arrays and the function, between the image's end and 4 GB above its base.
static uint8_t *room_near(uint8_t *base, uint32_t image_size, size_t size) {
    uintptr_t at = ((uintptr_t)base + image_size + 0xffff) & ~(uintptr_t)0xffff;
    uintptr_t last = (uintptr_t)base + 0xffff0000u - size;
    for (; at <= last; at += 0x10000) {
        void *addr = (void *)at;
        size_t len = size;
        if (!alloc(CURRENT_PROCESS, &addr, 0, &len, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE)) {
            if (addr == (void *)at) return addr;
            len = 0;
            release(CURRENT_PROCESS, &addr, &len, MEM_RELEASE);
        }
    }
    return NULL;
}

static void add_name(uint8_t *base, uint32_t image_size, struct export_directory *d) {
    const uint32_t *names = rva(base, d->address_of_names);
    const uint16_t *ordinals = rva(base, d->address_of_name_ordinals);
    const uint32_t *functions = rva(base, d->address_of_functions);
    uint32_t n = d->number_of_names, f = d->number_of_functions, at = 0;

    // Where the name goes in the sorted list; nothing to do when it is there already.
    while (at < n) {
        int c = strcmp(rva(base, names[at]), NAME);
        if (!c) {
            api->log(TAG, "kernel32.dll already has %s, left as it is", NAME);
            return;
        }
        if (c > 0) break;
        at++;
    }
    if (f >= 0xffff) {
        api->log(TAG, "kernel32.dll has %u functions, no ordinal left for one more, not added", f);
        return;
    }

    size_t code = (sizeof(FUNCTION) + 15) & ~(size_t)15;
    size_t size = code + (f + 1) * 4 + (n + 1) * 4 + (n + 1) * 2 + sizeof(NAME);
    uint8_t *room = room_near(base, image_size, size);
    if (!room) {
        api->log(TAG, "no memory free within 4 GB above kernel32.dll, %s not added", NAME);
        return;
    }
    uint8_t *p = room;
    memcpy(p, FUNCTION, sizeof(FUNCTION));
    uint32_t *new_functions = (uint32_t *)(p += code);
    uint32_t *new_names = (uint32_t *)(p += (f + 1) * 4);
    uint16_t *new_ordinals = (uint16_t *)(p += (n + 1) * 4);
    char *name = (char *)(p += (n + 1) * 2);
    memcpy(name, NAME, sizeof(NAME));
    #define RVA_OF(x) ((uint32_t)((uint8_t *)(x) - base))

    memcpy(new_functions, functions, f * 4);
    new_functions[f] = RVA_OF(room);
    memcpy(new_names, names, at * 4);
    memcpy(new_ordinals, ordinals, at * 2);
    new_names[at] = RVA_OF(name);
    new_ordinals[at] = (uint16_t)f;
    memcpy(new_names + at + 1, names + at, (n - at) * 4);
    memcpy(new_ordinals + at + 1, ordinals + at, (n - at) * 2);

    // The function's page runs; the arrays on it are only read.
    void *addr = room;
    size_t len = size;
    uint32_t old;
    if (protect(CURRENT_PROCESS, &addr, &len, PAGE_EXECUTE_READ, &old)) {
        api->log(TAG, "the new function's memory could not be made executable, %s not added", NAME);
        return;
    }

    addr = d;
    len = sizeof(*d);
    if (protect(CURRENT_PROCESS, &addr, &len, PAGE_READWRITE, &old)) {
        api->log(TAG, "kernel32.dll's export directory could not be written, %s not added", NAME);
        return;
    }
    d->address_of_functions = RVA_OF(new_functions);
    d->address_of_name_ordinals = RVA_OF(new_ordinals);
    d->address_of_names = RVA_OF(new_names);
    d->number_of_functions = f + 1;
    d->number_of_names = n + 1;
    addr = d;
    len = sizeof(*d);
    protect(CURRENT_PROCESS, &addr, &len, old, &old);
    #undef RVA_OF
    api->log(TAG, "kernel32.dll at %p: %s added, ordinal %u, the function at %p", (void *)base, NAME,
             d->base + f, (void *)room);
}

static NTSTATUS map_hook(HANDLE section, HANDLE process, void **addr, uintptr_t zero_bits, size_t commit,
                         const int64_t *offset, size_t *size, uint32_t inherit, mgf_stack_u32 type,
                         mgf_stack_u32 protect_) {
    NTSTATUS status = real_map(section, process, addr, zero_bits, commit, offset, size, inherit, type, protect_);
    if (status >= 0 && process == CURRENT_PROCESS && addr && *addr && !__atomic_load_n(&done, __ATOMIC_RELAXED)) {
        uint32_t image_size, dir_size;
        struct export_directory *d = exports_of(*addr, &image_size, &dir_size);
        if (d && d->name < image_size && named(*addr, d, "kernel32.dll")
            && !__atomic_exchange_n(&done, 1, __ATOMIC_RELAXED))
            add_name(*addr, image_size, d);
    }
    return status;
}

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    (void)image;
    uintptr_t map;
    uintptr_t *slot = NULL;
    if (!(map = api->symbol(mh, slide, "_NtMapViewOfSection"))) {
        api->log(TAG, "ntdll.so has no NtMapViewOfSection, not armed");
        return;
    }
    alloc = (alloc_fn)api->symbol(mh, slide, "_NtAllocateVirtualMemory");
    protect = (protect_fn)api->symbol(mh, slide, "_NtProtectVirtualMemory");
    release = (free_fn)api->symbol(mh, slide, "_NtFreeVirtualMemory");
    if (!alloc || !protect || !release) {
        api->log(TAG, "ntdll.so lacks a memory function this uses, not armed");
        return;
    }
    // What the entry holds: the function, or the thunk to it (FEX side), which the hook chains to.
    if (!(slot = mgf_syscall_slot(api, mh, slide, "_NtMapViewOfSection", &map))) {
        api->log(TAG, "no one syscall table entry for NtMapViewOfSection, not armed");
        return;
    }
    real_map = (map_fn)map;
    if (!api->swap_pointer(slot, map, (uintptr_t)map_hook)) {
        api->log(TAG, "the syscall table could not be written, not armed");
        return;
    }
    api->log(TAG, "kernel32.dll gets %s when it is mapped", NAME);
}

// mgf-engine.dylib (../mgf-engine.c) arms this for the games that need it.
void mgf_package_family_arm(const struct np_plugin_api *with, const struct mach_header_64 *mh, intptr_t slide) {
    api = with;
    arm(mh, slide, NULL);
}
