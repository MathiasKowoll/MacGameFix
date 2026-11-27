// A USB device's container, made from where it is plugged in. What engine patch 0001 does in the
// Wine modules' winebus.sys, done here for CodeWeavers' own.
//
// A game pairs a pad with its audio output (the haptics) by DEVPKEY_Device_ContainerId: both
// have to carry the same GUID, as two functions of one device do on Windows. The audio side gives
// an endpoint {location, 27F2-4948-9654-152804AF6378}, with the location id macOS keeps for the
// USB port (audio.c, engine patch 0002).
//
// CodeWeavers' winebus.sys answers a device's container from `parent_hash`, the SHA-1 of the
// bus's name, and its IOHID bus names itself "/bus/iohid" for every device: all of them get one
// container, {E06FEC9A-...}, which is no endpoint's, and two pads would share it. The same hash
// and the location are in the device's instance id, USB\VID_054C&PID_0CE6&MI_03\1&e06fec9a&0&
// 100000 (get_instance_id: "1&<parent_hash[0]>&0&<index>", the index being the location id).
//
// ntoskrnl stores the answer under the device's key, in the value "ContainerId"
// (SetupDiSetDeviceRegistryPropertyW with SPDRP_BASE_CONTAINERID), and gives a device's children,
// the HID collections games open, the value it reads back from there. So the one write is the
// place: this takes the syscall table's entry for NtSetValueKey (../engine/mgf_hooks.h, as
// mgf-engine's enumerator-name takes NtQueryValueKey), and when "ContainerId" is written under
// ...\Enum\USB\<device>\1&<hash>&0&<location> with a GUID that starts with that same hash, the
// location's container is written instead. Everything else goes to ntdll unchanged.
//
// The Wine modules' winebus.sys answers with the location's container already, which does not
// start with the hash: its writes pass untouched, so this needs no telling which file a runner
// has. A Bluetooth pad shown as wired gets its container the same way: bus.c gives it interface
// number 3, and CodeWeavers' winebus.sys answers for a device with an interface number.
//
// Holding this entry, the hook is also where the functions the game runs as Windows code reach
// the macOS side of the library: a value set on the key that is none (windows.h).
//
// Not covered: winebus.sys gives a second device at one location the index after it, so two HID
// interfaces of one USB device would get two containers. A DualSense has one.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include <stdint.h>
#include <string.h>
#include "pad.h"
#include "windows.h"
#include "../engine/mgf_hooks.h"

#define KeyNameInformation 3
#define GUID_CHARS 38  // {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*set_value_fn)(void *key, const struct unicode_string *name, uint32_t title_index, uint32_t type,
                                 const void *data, uint32_t count);
typedef NTSTATUS (*query_key_fn)(void *key, int info_class, void *info, uint32_t length, uint32_t *result_len);

static set_value_fn real_set_value;
static query_key_fn query_key;

static uint16_t lower(uint16_t c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }

static bool is(const uint16_t *s, unsigned chars, const char *ascii) {
    unsigned i;
    for (i = 0; i < chars && ascii[i]; i++)
        if (lower(s[i]) != (uint16_t)ascii[i]) return false;
    return i == chars && !ascii[i];
}

// `digits` hex digits at `s`, 1 to 8 of them.
static bool hex(const uint16_t *s, unsigned digits, uint32_t *value) {
    uint32_t v = 0;
    if (!digits || digits > 8) return false;
    for (unsigned i = 0; i < digits; i++) {
        uint16_t c = lower(s[i]);
        if (c >= '0' && c <= '9') v = v << 4 | (c - '0');
        else if (c >= 'a' && c <= 'f') v = v << 4 | (c - 'a' + 10);
        else return false;
    }
    *value = v;
    return true;
}

// The hash and the location of the USB device whose key this is: ...\Enum\USB\<device>\
// 1&<8 hex digits>&0&<location>. False for any other key.
static bool usb_instance(void *key, uint32_t *hash, uint32_t *location) {
    struct { uint32_t name_length; uint16_t name[512]; } info;
    uint32_t got = 0;
    unsigned chars, i, start = 0, parts = 0, bus_end = 0, instance = 0;

    if (query_key(key, KeyNameInformation, &info, sizeof(info), &got) != STATUS_SUCCESS) return false;
    chars = info.name_length / 2;
    if (chars > 512) return false;
    // After the last "\Enum\".
    for (i = 0; i + 6 <= chars; i++)
        if (info.name[i] == '\\' && is(info.name + i + 1, 4, "enum") && info.name[i + 5] == '\\') start = i + 6;
    if (!start) return false;
    for (i = start; i <= chars; i++) {
        if (i < chars && info.name[i] != '\\') continue;
        if (i == start || info.name[i - 1] == '\\') return false;  // an empty component
        if (!parts) bus_end = i;
        if (++parts == 2) instance = i + 1;
    }
    if (parts != 3 || !is(info.name + start, bus_end - start, "usb")) return false;
    // "1&" 8 digits "&0&" the location, to the end.
    if (chars - instance < 14 || info.name[instance] != '1' || info.name[instance + 1] != '&' ||
        !hex(info.name + instance + 2, 8, hash) || !is(info.name + instance + 10, 3, "&0&"))
        return false;
    return hex(info.name + instance + 13, chars - instance - 13, location) && *location;
}

static NTSTATUS set_value_hook(void *key, const struct unicode_string *name, uint32_t title_index, uint32_t type,
                               const void *data, uint32_t count) {
    static const char tail[] = "-27F2-4948-9654-152804AF6378}";
    static const char digits[] = "0123456789ABCDEF";
    static int told;
    const uint16_t *text = data;
    uint16_t ours[GUID_CHARS + 1];
    uint32_t first, hash, location;
    unsigned i;

    // A call for the library from a function run as Windows code (windows.h), not a value.
    if (key == MGF_CALL_KEY) return mgf_windows_call(type, (void *)data);
    if (type != REG_SZ || !name || !name->buffer || name->length != 11 * 2 || !is(name->buffer, 11, "containerid") ||
        !data || count < GUID_CHARS * 2 || count > (GUID_CHARS + 1) * 2 || text[0] != '{' || text[9] != '-' ||
        text[GUID_CHARS - 1] != '}' || !hex(text + 1, 8, &first))
        return real_set_value(key, name, title_index, type, data, count);
    if (!usb_instance(key, &hash, &location) || first != hash)
        return real_set_value(key, name, title_index, type, data, count);

    ours[0] = '{';
    for (i = 0; i < 8; i++) ours[1 + i] = digits[location >> (28 - 4 * i) & 15];
    for (i = 0; tail[i]; i++) ours[9 + i] = tail[i];
    ours[GUID_CHARS] = 0;
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        pad_log("controls: a USB device's container is made from its location, as its audio output's is "
                "(the first: %08x)\n", location);
    return real_set_value(key, name, title_index, type, ours, sizeof(ours));
}

void mgf_controls_container(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide) {
    uintptr_t old = 0, *slot = mgf_syscall_slot(api, mh, slide, "_NtSetValueKey", &old);
    query_key = (query_key_fn)api->symbol(mh, slide, "_NtQueryKey");
    if (!slot || !query_key) {
        pad_log("controls: no one syscall table entry for NtSetValueKey, or no NtQueryKey: a USB device's "
                "container is left as winebus.sys gives it\n");
        return;
    }
    real_set_value = (set_value_fn)old;
    if (!api->swap_pointer(slot, old, (uintptr_t)set_value_hook))
        pad_log("controls: the syscall table could not be written: a USB device's container is left as "
                "winebus.sys gives it\n");
}
