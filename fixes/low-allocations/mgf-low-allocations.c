// Keep the game's memory low: engine patch 0038 as a NotProton plugin, for F1 25 alone.
//
// Wine 11.21 reserves 0x7ff000000000-0x7ff600000000 in a 64-bit process and searches its
// reserved areas bottom-up for an allocation with no address, so a program that has filled
// the low area gets addresses from 0x7ff000000000 up. Windows, and Wine 11.0, give it low
// ones. F1 25 (a 6.5 GB image) crashed on them some 30 s after start on CrossOver Preview
// 41303: a pointer to a low object came back with bit 47 set.
//
// Patch 0038 changes that order inside ntdll.so, for every game in the runner. This does the
// same from outside it, in the game's process only: an allocation or a section view the game
// asks for with no address, no upper limit, no zero bits and no MEM_TOP_DOWN is first asked for
// below the high area, through the same call with an address requirement; Wine then takes its
// low reserved area, then a free area below the limit. Only when that finds nothing does the
// game's own request go through as it was, which may land in the high area as before.
//
// It replaces the syscall table's entries for NtAllocateVirtualMemory(Ex) and
// NtMapViewOfSection(Ex), the way NotProton's Red Dead Online plugin does for
// NtDeviceIoControlFile, so NotProton's ntdll stays as it is. NotProton's plugin host
// (plugin-host.dylib) finds them; without it this loads and does nothing.
//
// F1 25's fix (install-f125-swofty.sh) puts the built library in NotProton's plugins folder
// with the row that loads it, "Keep the game's memory low", on that game's page alone.
// build-low-allocations.sh builds it.
//
// Played on 2026-11-24 (NotProton, CrossOver Preview 41303 on Rosetta): with 0038 switched off
// in the runner (WINE_LOW_ALLOCATIONS_FIRST=0) and this loaded, the plugin was armed in every
// process of the game, F1_25.exe's first such allocation landed at 0x170000, no request fell
// back, and a full race ran without the crash.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../../app/notproton-plugins/notproton_plugin.h"

#include <stdint.h>
#include <string.h>

#define TAG "low-allocations"

typedef int32_t NTSTATUS;
typedef void *HANDLE;

#define STATUS_SUCCESS 0
#define MEM_TOP_DOWN 0x00100000
#define MEM_EXTENDED_PARAMETER_ADDRESS_REQUIREMENTS 1
#define CURRENT_PROCESS ((HANDLE)(intptr_t)-1)

// Below the area Wine 11.21 reserves near the top of a 64-bit address space.
#define BELOW_HIGH_AREA ((void *)0x7fefffffffffULL)

typedef struct {
    void *lowest;
    void *highest;
    size_t alignment;
} mem_address_requirements;

typedef struct {
    uint64_t type_and_reserved; // Type is the low 8 bits
    union {
        uint64_t u64;
        void *pointer;
    };
} mem_extended_parameter;

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*alloc_fn)(HANDLE process, void **addr, uintptr_t zero_bits, size_t *size, uint32_t type,
                             uint32_t protect);
typedef NTSTATUS (*alloc_ex_fn)(HANDLE process, void **addr, size_t *size, uint32_t type, uint32_t protect,
                                mem_extended_parameter *params, uint32_t count);
typedef NTSTATUS (*map_fn)(HANDLE section, HANDLE process, void **addr, uintptr_t zero_bits, size_t commit,
                           const int64_t *offset, size_t *size, uint32_t inherit, uint32_t type, uint32_t protect);
typedef NTSTATUS (*query_section_fn)(HANDLE section, int info_class, void *info, size_t len, size_t *ret_len);
typedef NTSTATUS (*map_ex_fn)(HANDLE section, HANDLE process, void **addr, const int64_t *offset, size_t *size,
                              uint32_t type, uint32_t protect, mem_extended_parameter *params, uint32_t count);

static const struct np_plugin_api *api;
static alloc_fn real_alloc;
static alloc_ex_fn real_alloc_ex;
static map_fn real_map;
static map_ex_fn real_map_ex;
static query_section_fn query_section;
static int said_low, said_fell_back;

static void say_low(void *addr) {
    if (!__atomic_exchange_n(&said_low, 1, __ATOMIC_RELAXED))
        api->log(TAG, "first allocation with no address kept below the high area, at %p", addr);
}

static void say_fell_back(void) {
    if (!__atomic_exchange_n(&said_fell_back, 1, __ATOMIC_RELAXED))
        api->log(TAG, "nothing free below the high area once: that request went through as it was");
}

// The game's own request, with no address: worth asking low first.
static int wants_low(HANDLE process, void **addr, uint32_t type) {
    return process == CURRENT_PROCESS && addr && !*addr && !(type & MEM_TOP_DOWN);
}

// An image (an exe or a DLL) is placed by its own base address: it is left as it comes.
static int is_image(HANDLE section) {
    struct { void *base; uint32_t attributes; int64_t size; } info;
    if (!query_section || query_section(section, 0 /* SectionBasicInformation */, &info, sizeof(info), NULL))
        return 1;
    return (info.attributes & 0x1000000 /* SEC_IMAGE */) != 0;
}

// One address requirement asking for the low side, or 0 when the caller gave one already.
static uint32_t with_low_limit(const mem_extended_parameter *params, uint32_t count, mem_extended_parameter *out,
                               uint32_t max, mem_address_requirements *req) {
    if (count + 1 > max) return 0;
    for (uint32_t i = 0; i < count; i++)
        if ((params[i].type_and_reserved & 0xff) == MEM_EXTENDED_PARAMETER_ADDRESS_REQUIREMENTS) return 0;
    if (count) memcpy(out, params, count * sizeof(*out));
    memset(req, 0, sizeof(*req));
    req->highest = BELOW_HIGH_AREA;
    out[count].type_and_reserved = MEM_EXTENDED_PARAMETER_ADDRESS_REQUIREMENTS;
    out[count].pointer = req;
    return count + 1;
}

static NTSTATUS alloc_hook(HANDLE process, void **addr, uintptr_t zero_bits, size_t *size, uint32_t type,
                           uint32_t protect) {
    if (!zero_bits && wants_low(process, addr, type) && size) {
        mem_extended_parameter params[1];
        mem_address_requirements req;
        size_t want = *size;
        uint32_t n = with_low_limit(NULL, 0, params, 1, &req);
        NTSTATUS status = real_alloc_ex(process, addr, size, type, protect, params, n);
        if (status == STATUS_SUCCESS) {
            say_low(*addr);
            return status;
        }
        *addr = NULL;
        *size = want;
        say_fell_back();
    }
    return real_alloc(process, addr, zero_bits, size, type, protect);
}

static NTSTATUS alloc_ex_hook(HANDLE process, void **addr, size_t *size, uint32_t type, uint32_t protect,
                              mem_extended_parameter *params, uint32_t count) {
    if (wants_low(process, addr, type) && size && (count == 0 || params)) {
        mem_extended_parameter merged[8];
        mem_address_requirements req;
        size_t want = *size;
        uint32_t n = with_low_limit(params, count, merged, 8, &req);
        if (n) {
            NTSTATUS status = real_alloc_ex(process, addr, size, type, protect, merged, n);
            if (status == STATUS_SUCCESS) {
                say_low(*addr);
                return status;
            }
            *addr = NULL;
            *size = want;
            say_fell_back();
        }
    }
    return real_alloc_ex(process, addr, size, type, protect, params, count);
}

static NTSTATUS map_hook(HANDLE section, HANDLE process, void **addr, uintptr_t zero_bits, size_t commit,
                         const int64_t *offset, size_t *size, uint32_t inherit, uint32_t type, uint32_t protect) {
    // NtMapViewOfSectionEx has no commit size or inheritance: only a request that leaves both
    // at what it uses (none, and ViewShare = 1) is asked low through it.
    if (!zero_bits && !commit && inherit == 1 && wants_low(process, addr, type) && size && !is_image(section)) {
        mem_extended_parameter params[1];
        mem_address_requirements req;
        size_t want = *size;
        uint32_t n = with_low_limit(NULL, 0, params, 1, &req);
        NTSTATUS status = real_map_ex(section, process, addr, offset, size, type, protect, params, n);
        if (status >= 0) {
            say_low(*addr);
            return status;
        }
        *addr = NULL;
        *size = want;
        say_fell_back();
    }
    return real_map(section, process, addr, zero_bits, commit, offset, size, inherit, type, protect);
}

static NTSTATUS map_ex_hook(HANDLE section, HANDLE process, void **addr, const int64_t *offset, size_t *size,
                            uint32_t type, uint32_t protect, mem_extended_parameter *params, uint32_t count) {
    if (wants_low(process, addr, type) && size && (count == 0 || params) && !is_image(section)) {
        mem_extended_parameter merged[8];
        mem_address_requirements req;
        size_t want = *size;
        uint32_t n = with_low_limit(params, count, merged, 8, &req);
        if (n) {
            NTSTATUS status = real_map_ex(section, process, addr, offset, size, type, protect, merged, n);
            if (status >= 0) {
                say_low(*addr);
                return status;
            }
            *addr = NULL;
            *size = want;
            say_fell_back();
        }
    }
    return real_map_ex(section, process, addr, offset, size, type, protect, params, count);
}

// The syscall table's one entry for a function, or NULL.
static uintptr_t *entry(const struct mach_header_64 *mh, intptr_t slide, const char *name, uintptr_t *fn) {
    uintptr_t *slot = NULL;
    *fn = api->symbol(mh, slide, name);
    if (!*fn) {
        api->log(TAG, "ntdll.so has no %s, not armed", name);
        return NULL;
    }
    int refs = api->count_pointers(mh, slide, *fn, &slot);
    if (refs != 1) {
        api->log(TAG, "%d syscall table entries point at %s instead of 1, not armed", refs, name);
        return NULL;
    }
    return slot;
}

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    (void)image;
    uintptr_t alloc, alloc_ex, map, map_ex;
    uintptr_t *alloc_slot = entry(mh, slide, "_NtAllocateVirtualMemory", &alloc);
    uintptr_t *alloc_ex_slot = entry(mh, slide, "_NtAllocateVirtualMemoryEx", &alloc_ex);
    uintptr_t *map_slot = entry(mh, slide, "_NtMapViewOfSection", &map);
    uintptr_t *map_ex_slot = entry(mh, slide, "_NtMapViewOfSectionEx", &map_ex);
    if (!alloc_slot || !alloc_ex_slot || !map_slot || !map_ex_slot) return;
    real_alloc = (alloc_fn)alloc;
    real_alloc_ex = (alloc_ex_fn)alloc_ex;
    real_map = (map_fn)map;
    real_map_ex = (map_ex_fn)map_ex;
    query_section = (query_section_fn)api->symbol(mh, slide, "_NtQuerySection");
    // All four or none: the Ex calls are what the others ask through.
    if (!api->swap_pointer(alloc_ex_slot, alloc_ex, (uintptr_t)alloc_ex_hook)) {
        api->log(TAG, "the syscall table could not be written, not armed");
        return;
    }
    if (!api->swap_pointer(map_ex_slot, map_ex, (uintptr_t)map_ex_hook)
        || !api->swap_pointer(alloc_slot, alloc, (uintptr_t)alloc_hook)
        || !api->swap_pointer(map_slot, map, (uintptr_t)map_hook)) {
        api->log(TAG, "only part of the syscall table could be written; what was written stays");
        return;
    }
    api->log(TAG, "allocations with no address are asked below 0x7ff000000000 first");
}

#ifndef NP_PLUGIN_TEST
__attribute__((constructor))
#endif
static void low_allocations_init(void) {
    if (!(api = np_plugin_api())) {
        fprintf(stderr, TAG ": plugin-host.dylib isn't loaded, not armed\n");
        return;
    }
    api->on_first_image("ntdll.so", "-unix/", arm);
}
