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
// Windows code (windows.h). It asks the store as before; only when the container was asked for
// and the answer is empty, it asks the same store for the endpoint's GUID (which mmdevapi answers
// as text, in memory the caller frees), asks audio.c for that endpoint's container (win_call),
// and where audio.c knows one gives the same memory back with the 16 bytes of it, as VT_CLSID.
//
// An mmdevapi.dll that already answers (the Wine modules') is asked first and its answer kept.
// Where winecoreaudio.so is MacGameFix's own, audio.c has taken nothing and knows no endpoint.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pad.h"
#include "pe.h"
#include "windows.h"

#if defined(__x86_64__)
typedef int32_t (WINAPI *get_value_fn)(void *store, const struct property_key *key, struct prop_variant *value);
typedef void (WINAPI *free_fn)(void *memory);

static get_value_fn real_get_value;

static const struct property_key container_key = {{0x8c7ed206, 0x3f8a, 0x4827, {0xb3, 0xab, 0xae, 0x9e, 0x1f, 0xae, 0xfc, 0x6c}}, 2};
static const struct property_key endpoint_guid_key = {{0x1da5d803, 0xd492, 0x4edd, {0x8c, 0x23, 0xe0, 0xc0, 0xff, 0xee, 0x7f, 0x0e}}, 4};

// ---- Run as Windows code (windows.h).

static bool same_key(const struct property_key *a, const struct property_key *b) {
    const uint32_t *x = (const uint32_t *)a, *y = (const uint32_t *)b;
    return x[0] == y[0] && x[1] == y[1] && x[2] == y[2] && x[3] == y[3] && x[4] == y[4];
}

static WINAPI int32_t get_value(void *store, const struct property_key *key, struct prop_variant *value) {
    struct mgf_container_request request = {NULL, 0};
    int32_t result = real_get_value(store, key, value);
    free_fn free_memory;

    if (result || value->vt != VT_EMPTY || !same_key(key, &container_key)) return result;
    if (real_get_value(store, &endpoint_guid_key, value) || value->vt != VT_LPWSTR || !value->pointer) {
        value->vt = VT_EMPTY;
        value->pointer = NULL;
        return result;
    }
    request.endpoint = value->pointer;
    win_call(MGF_CALL_CONTAINER, &request);
    if (request.found) {
        value->vt = VT_CLSID;
        return result;
    }
    if ((free_memory = win_export(win_module("combase.dll"), "CoTaskMemFree"))) free_memory(value->pointer);
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
    if (!pad_part_off("mmdevapi")) pe_on_map("mmdevapi.dll", mapped);
#endif
}
