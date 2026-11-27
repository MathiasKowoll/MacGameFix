// mmdevapi.dll: an audio endpoint's container, asked of the driver. What engine patch 0003 does
// in the Wine modules' mmdevapi.dll, done here on CodeWeavers' own.
//
// A game finds a pad's audio output (the haptics) by DEVPKEY_Device_ContainerId: the endpoint's
// property store has to give the GUID the pad's HID device carries (container.c). CodeWeavers'
// mmdevapi.dll reads every property from the registry, where nothing puts that one, and its
// reader knows no GUID type: the store answers VT_EMPTY. The driver knows the answer: audio.c
// gives a USB output {location, 27F2-4948-9654-152804AF6378}.
//
// The store's GetValue is a COM method, in no export. It is found by what its table holds:
// IPropertyStore has eight methods, and in mmdevapi's the last three (GetValue, SetValue, Commit)
// return STG_E_ACCESSDENIED for a store opened the other way, which nothing else there does. The
// one run of eight pointers to code where the last three hold that constant and the first five
// do not is the table (one in CodeWeavers' 41073 and 41303 files, and in the Wine modules').
// More than one or none, and the module is left as it is.
//
// The table's GetValue is pointed at get_value() below, which the game's own threads then run as
// Windows code: on the game's stack and with the Windows thread block in gs, so it calls nothing
// of macOS, not even the C library, and keeps to memory it is handed. It asks the store as
// before; only when the container was asked for and the answer is empty, it asks the same store
// for the endpoint's GUID (which mmdevapi answers as text, in memory the caller frees), sends
// that through Wine's unix call dispatcher to audio.c (mmdevapi.h), and where audio.c knows a
// container gives the same memory back with the 16 bytes of it, as VT_CLSID.
//
// An mmdevapi.dll that already answers (the Wine modules') is asked first and its answer kept.
// Where winecoreaudio.so is MacGameFix's own there is nothing to ask, and nothing is.
//
// Not covered: this function has no Windows unwind data, so an exception raised inside
// mmdevapi's GetValue could not unwind through it. It raises none.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "mmdevapi.h"
#include "pad.h"
#include "pe.h"

#if defined(__x86_64__)
#define WINAPI __attribute__((ms_abi))
typedef int32_t (WINAPI *get_value_fn)(void *store, const struct property_key *key, struct prop_variant *value);
typedef int32_t (WINAPI *unix_call_fn)(uint64_t handle, uint32_t code, void *args);
typedef void (WINAPI *free_fn)(void *memory);

static get_value_fn real_get_value;
static unix_call_fn dispatcher;
// Two of mmdevapi's own imports, read when they are needed: the loader has bound them by then.
static uintptr_t *ntdll_import, *free_import;

static const struct property_key container_key = {{0x8c7ed206, 0x3f8a, 0x4827, {0xb3, 0xab, 0xae, 0x9e, 0x1f, 0xae, 0xfc, 0x6c}}, 2};
static const struct property_key endpoint_guid_key = {{0x1da5d803, 0xd492, 0x4edd, {0x8c, 0x23, 0xe0, 0xc0, 0xff, 0xee, 0x7f, 0x0e}}, 4};

// ---- Run as Windows code: nothing below calls out of this file, except through the pointers above.

static bool same_key(const struct property_key *a, const struct property_key *b) {
    const uint32_t *x = (const uint32_t *)a, *y = (const uint32_t *)b;
    return x[0] == y[0] && x[1] == y[1] && x[2] == y[2] && x[3] == y[3] && x[4] == y[4];
}

// Wine's unix call dispatcher: ntdll.dll exports a pointer to it, "__wine_unix_call_dispatcher".
// ntdll.dll is found from a function of it that mmdevapi imports: its image starts at the
// nearest 64 KB boundary below that holds a PE header.
static unix_call_fn find_dispatcher(void) {
    static const char wanted[] = "__wine_unix_call_dispatcher";
    const uint8_t *base = (const uint8_t *)(*ntdll_import & ~(uintptr_t)0xffff);
    for (unsigned i = 0;; i++, base -= 0x10000) {
        if (i == 0x200) return NULL;
        if (base[0] != 'M' || base[1] != 'Z') continue;
        uint32_t nt = *(const uint32_t *)(base + 0x3c);
        if (nt < 0x1000 - 0x108 && *(const uint32_t *)(base + nt) == 0x4550) break;
    }
    const uint8_t *opt = base + *(const uint32_t *)(base + 0x3c) + 24;
    const uint32_t *d = (const uint32_t *)(base + *(const uint32_t *)(opt + 112));
    // The export directory: the count of names at 24, then the arrays of functions, names, ordinals.
    uint32_t count = d[6];
    const uint32_t *functions = (const uint32_t *)(base + d[7]), *names = (const uint32_t *)(base + d[8]);
    const uint16_t *ordinals = (const uint16_t *)(base + d[9]);
    for (uint32_t i = 0; i < count; i++) {
        const char *name = (const char *)base + names[i];
        unsigned c = 0;
        while (wanted[c] && name[c] == wanted[c]) c++;
        if (wanted[c] || name[c]) continue;
        return *(unix_call_fn *)(base + functions[ordinals[i]]);
    }
    return NULL;
}

static WINAPI int32_t get_value(void *store, const struct property_key *key, struct prop_variant *value) {
    struct mgf_container_request request;
    int32_t result = real_get_value(store, key, value);

    if (result || value->vt != VT_EMPTY || !same_key(key, &container_key) || !mgf_audio_unix_handle) return result;
    if (!dispatcher && !(dispatcher = find_dispatcher())) return result;
    if (real_get_value(store, &endpoint_guid_key, value) || value->vt != VT_LPWSTR || !value->pointer) {
        value->vt = VT_EMPTY;
        value->pointer = NULL;
        return result;
    }
    request.tag = &mgf_container_request_tag;
    request.endpoint = value->pointer;
    request.found = 0;
    dispatcher(mgf_audio_unix_handle, UNIX_GET_PROP_VALUE, &request);
    if (request.found) {
        value->vt = VT_CLSID;
        return result;
    }
    if (*free_import) ((free_fn)*free_import)(value->pointer);
    value->vt = VT_EMPTY;
    value->pointer = NULL;
    return result;
}

// ---- Run on the macOS side, when mmdevapi.dll has just been mapped.

#define STG_E_ACCESSDENIED "\x05\x00\x03\x80"

// Whether the constant is in the first `within` bytes of the function at `fn`.
static bool denies_access(const struct pe_image *image, uintptr_t fn, uint32_t within) {
    uint32_t left = pe_code(image, (const uint8_t *)fn);
    if (left < within) within = left;
    return within >= 4 && memmem((const void *)fn, within, STG_E_ACCESSDENIED, 4);
}

static bool store_table(const struct pe_image *image, uintptr_t *table) {
    for (unsigned i = 0; i < 8; i++)
        if (!pe_code(image, (const uint8_t *)table[i])) return false;
    for (unsigned i = 0; i < 5; i++)
        if (denies_access(image, table[i], 128)) return false;
    for (unsigned i = 5; i < 8; i++)
        if (!denies_access(image, table[i], 512)) return false;
    return true;
}

static void mapped(const struct pe_image *image) {
    static int told;
    uintptr_t *table = NULL;
    uint8_t *start;
    uint32_t size;
    unsigned found = 0;
    bool code;

    for (unsigned i = 0; pe_section(image, i, &start, &size, &code); i++) {
        if (code) continue;
        for (uint32_t at = 0; at + 64 <= size; at += 8)
            if (store_table(image, (uintptr_t *)(start + at))) {
                table = (uintptr_t *)(start + at);
                found++;
            }
    }
    if (found != 1) {
        pad_log("controls: mmdevapi.dll has %u tables that look like its property store's, not one: left as it is\n",
                found);
        return;
    }
    ntdll_import = pe_import_slot(image, "ntdll.dll", "NtQueryVirtualMemory");
    free_import = pe_import_slot(image, "ole32.dll", "CoTaskMemFree");
    if (!ntdll_import || !free_import) {
        pad_log("controls: mmdevapi.dll does not import what the container's answer needs, left as it is\n");
        return;
    }
    if (table[5] == (uintptr_t)get_value) return;  // mapped again where it was
    real_get_value = (get_value_fn)table[5];
    if (!pe_write_pointer(&table[5], (uintptr_t)get_value)) {
        pad_log("controls: mmdevapi.dll could not be written, left as it is\n");
        return;
    }
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        pad_log("controls: mmdevapi.dll asks the driver for an audio endpoint's container\n");
}
#endif

void mgf_controls_mmdevapi(void) {
#if defined(__x86_64__)
    pe_on_map("mmdevapi.dll", mapped);
#endif
}
