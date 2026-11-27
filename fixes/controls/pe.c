// See pe.h.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pe.h"
#include "nt.h"
#include "pad.h"
#include "../engine/mgf_hooks.h"

#define CURRENT_PROCESS ((HANDLE)(intptr_t)-1)
#define MEM_COMMIT 0x1000
#define MEM_RESERVE 0x2000
#define MEM_RELEASE 0x8000
#define PAGE_READWRITE 0x04
#define PAGE_EXECUTE_READ 0x20

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*map_fn)(HANDLE section, HANDLE process, void **addr, uintptr_t zero_bits, size_t commit,
                           const int64_t *offset, size_t *size, uint32_t inherit, mgf_stack_u32 type,
                           mgf_stack_u32 protect);
typedef NTSTATUS (*alloc_fn)(HANDLE process, void **addr, uintptr_t zero_bits, size_t *size, uint32_t type,
                             uint32_t protect);
typedef NTSTATUS (*protect_fn)(HANDLE process, void **addr, size_t *size, uint32_t prot, uint32_t *old);
typedef NTSTATUS (*free_fn)(HANDLE process, void **addr, size_t *size, uint32_t type);

static map_fn real_map;
static alloc_fn alloc;
static protect_fn protect;
static free_fn release;

static struct {
    const char *dll;
    pe_mapped_fn fn;
} wanted[24];
static unsigned wanted_count;

struct export_directory {
    uint32_t characteristics, time_date_stamp;
    uint16_t major, minor;
    uint32_t name, base, number_of_functions, number_of_names;
    uint32_t address_of_functions, address_of_names, address_of_name_ordinals;
};

void pe_on_map(const char *dll, pe_mapped_fn fn) {
    if (wanted_count == sizeof(wanted) / sizeof(*wanted)) return;
    wanted[wanted_count].dll = dll;
    wanted[wanted_count++].fn = fn;
}

// The export directory of a 64-bit image mapped as an image, with its size; NULL for anything else.
static struct export_directory *exports_of(uint8_t *base, size_t mapped, uint32_t *image_size, uint32_t *dir_size) {
    if (mapped < 0x1000 || base[0] != 'M' || base[1] != 'Z') return NULL;
    uint32_t nt = *(uint32_t *)(base + 0x3c);
    if (nt > 0x1000 - 0x108 || memcmp(base + nt, "PE\0\0", 4)) return NULL;
    uint8_t *opt = base + nt + 24;
    if (*(uint16_t *)opt != 0x20b) return NULL;     // PE32+
    if (*(uint32_t *)(opt + 108) < 1) return NULL;  // NumberOfRvaAndSizes
    uint32_t dir = *(uint32_t *)(opt + 112), size = *(uint32_t *)(opt + 116);
    *image_size = *(uint32_t *)(opt + 56);          // SizeOfImage
    // A file mapped as data has its sections where the file has them, not at their RVAs.
    if (mapped < *image_size) return NULL;
    if (!dir || size < sizeof(struct export_directory) || (uint64_t)dir + size > *image_size) return NULL;
    *dir_size = size;
    return (struct export_directory *)(base + dir);
}

static bool named(const struct pe_image *image, const struct export_directory *d, const char *want) {
    if (d->name >= image->size - 64) return false;
    const char *name = (const char *)image->base + d->name;
    for (; *want; name++, want++)
        if ((*name | 0x20) != (*want | 0x20)) return false;
    return !*name;
}

static struct export_directory *directory(const struct pe_image *image, uint32_t *dir_size) {
    uint32_t image_size;
    return exports_of(image->base, image->size, &image_size, dir_size);
}

// The function array's entry for an export by name.
static uint32_t *entry_of(const struct pe_image *image, const char *name, uint32_t *dir_size) {
    struct export_directory *d = directory(image, dir_size);
    if (!d) return NULL;
    uint64_t names_end = (uint64_t)d->address_of_names + (uint64_t)d->number_of_names * 4;
    uint64_t ordinals_end = (uint64_t)d->address_of_name_ordinals + (uint64_t)d->number_of_names * 2;
    uint64_t functions_end = (uint64_t)d->address_of_functions + (uint64_t)d->number_of_functions * 4;
    if (names_end > image->size || ordinals_end > image->size || functions_end > image->size) return NULL;
    const uint32_t *names = (const uint32_t *)(image->base + d->address_of_names);
    const uint16_t *ordinals = (const uint16_t *)(image->base + d->address_of_name_ordinals);
    uint32_t *functions = (uint32_t *)(image->base + d->address_of_functions);
    size_t length = strlen(name) + 1;
    for (uint32_t i = 0; i < d->number_of_names; i++) {
        if ((uint64_t)names[i] + length > image->size) continue;
        if (memcmp(image->base + names[i], name, length)) continue;
        return ordinals[i] < d->number_of_functions ? &functions[ordinals[i]] : NULL;
    }
    return NULL;
}

uint8_t *pe_export(const struct pe_image *image, const char *name) {
    uint32_t dir_size;
    uint32_t *entry = entry_of(image, name, &dir_size);
    if (!entry || !*entry || *entry >= image->size) return NULL;
    // An address inside the export directory is a forward to another module, not code.
    uint8_t *at = image->base + *entry, *d = (uint8_t *)directory(image, &dir_size);
    if (at >= d && at < d + dir_size) return NULL;
    return at;
}

uint8_t *pe_room(const struct pe_image *image, size_t size) {
    uintptr_t at = ((uintptr_t)image->base + image->size + 0xffff) & ~(uintptr_t)0xffff;
    uintptr_t last = (uintptr_t)image->base + 0xffff0000u - size;
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

bool pe_runs(uint8_t *room, size_t size) {
    void *addr = room;
    uint32_t old;
    return !protect(CURRENT_PROCESS, &addr, &size, PAGE_EXECUTE_READ, &old);
}

bool pe_point_export(const struct pe_image *image, const char *name, const uint8_t *target) {
    uint32_t dir_size, old;
    uint32_t *entry = entry_of(image, name, &dir_size);
    if (!entry || target < image->base || (uint64_t)(target - image->base) > 0xffffffffu) return false;
    void *addr = entry;
    size_t len = sizeof(*entry);
    if (protect(CURRENT_PROCESS, &addr, &len, PAGE_READWRITE, &old)) return false;
    *entry = (uint32_t)(target - image->base);
    addr = entry;
    len = sizeof(*entry);
    protect(CURRENT_PROCESS, &addr, &len, old, &old);
    return true;
}

// The optional header of the image and its section table; false for anything but a PE32+ image.
static bool headers(const struct pe_image *image, uint8_t **opt, uint8_t **sections, unsigned *count) {
    uint8_t *base = image->base;
    if (image->size < 0x1000 || base[0] != 'M' || base[1] != 'Z') return false;
    uint32_t nt = *(uint32_t *)(base + 0x3c);
    if (nt > 0x1000 - 0x108 || memcmp(base + nt, "PE\0\0", 4)) return false;
    *opt = base + nt + 24;
    if (*(uint16_t *)*opt != 0x20b) return false;
    *count = *(uint16_t *)(base + nt + 6);
    *sections = *opt + *(uint16_t *)(base + nt + 20);
    return (uint64_t)(*sections - base) + (uint64_t)*count * 40 <= 0x1000;
}

bool pe_section(const struct pe_image *image, unsigned index, uint8_t **start, uint32_t *size, bool *code) {
    uint8_t *opt, *sections;
    unsigned count;
    if (!headers(image, &opt, &sections, &count) || index >= count) return false;
    const uint8_t *s = sections + index * 40;
    uint32_t virtual_size = *(uint32_t *)(s + 8), rva = *(uint32_t *)(s + 12);
    *start = image->base + rva;
    *size = (uint64_t)rva + virtual_size <= image->size ? virtual_size : 0;
    *code = *(uint32_t *)(s + 36) & 0x20000000;  // IMAGE_SCN_MEM_EXECUTE
    return true;
}

uint32_t pe_code(const struct pe_image *image, const uint8_t *at) {
    uint8_t *start;
    uint32_t size;
    bool code;
    for (unsigned i = 0; pe_section(image, i, &start, &size, &code); i++)
        if (code && at >= start && at < start + size) return (uint32_t)(start + size - at);
    return 0;
}

bool pe_has_text(const struct pe_image *image, const char *text) {
    uint8_t *start;
    uint32_t size;
    bool code;
    for (unsigned i = 0; pe_section(image, i, &start, &size, &code); i++)
        if (!code && size && memmem(start, size, text, strlen(text))) return true;
    return false;
}

bool pe_take_export(const struct pe_image *image, const char *name, const void *with, void **real) {
    // mov rax, <with>; jmp rax
    uint8_t jump[12] = {0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xe0};
    uint8_t *was = pe_export(image, name), *room;
    if (!was || !(room = pe_room(image, sizeof(jump)))) return false;
    memcpy(jump + 2, &with, 8);
    memcpy(room, jump, sizeof(jump));
    *real = was;
    return pe_runs(room, sizeof(jump)) && pe_point_export(image, name, room);
}

bool pe_write_pointer(uintptr_t *slot, uintptr_t value) {
    void *addr = slot;
    size_t len = sizeof(*slot);
    uint32_t old;
    if (protect(CURRENT_PROCESS, &addr, &len, PAGE_READWRITE, &old)) return false;
    *slot = value;
    addr = slot;
    len = sizeof(*slot);
    protect(CURRENT_PROCESS, &addr, &len, old, &old);
    return true;
}

static NTSTATUS map_hook(HANDLE section, HANDLE process, void **addr, uintptr_t zero_bits, size_t commit,
                         const int64_t *offset, size_t *size, uint32_t inherit, mgf_stack_u32 type,
                         mgf_stack_u32 protect_) {
    NTSTATUS status = real_map(section, process, addr, zero_bits, commit, offset, size, inherit, type, protect_);
    if (status >= 0 && process == CURRENT_PROCESS && addr && *addr && size) {
        struct pe_image image = {.base = *addr};
        uint32_t dir_size;
        struct export_directory *d = exports_of(image.base, *size, &image.size, &dir_size);
        if (d)
            for (unsigned i = 0; i < wanted_count; i++)
                if (named(&image, d, wanted[i].dll)) wanted[i].fn(&image);
    }
    return status;
}

void pe_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide) {
    uintptr_t map = 0;
    uintptr_t *slot;
    if (!wanted_count) return;
    alloc = (alloc_fn)api->symbol(mh, slide, "_NtAllocateVirtualMemory");
    protect = (protect_fn)api->symbol(mh, slide, "_NtProtectVirtualMemory");
    release = (free_fn)api->symbol(mh, slide, "_NtFreeVirtualMemory");
    if (!alloc || !protect || !release) {
        pad_log("controls: ntdll.so lacks a memory function, the Windows modules are left as they are\n");
        return;
    }
    // What the entry holds: the function, or the thunk to it (FEX side), which the hook chains to.
    if (!(slot = mgf_syscall_slot(api, mh, slide, "_NtMapViewOfSection", &map))) {
        pad_log("controls: no one syscall table entry for NtMapViewOfSection, the Windows modules are left as they are\n");
        return;
    }
    real_map = (map_fn)map;
    if (!api->swap_pointer(slot, map, (uintptr_t)map_hook))
        pad_log("controls: the syscall table could not be written, the Windows modules are left as they are\n");
}
