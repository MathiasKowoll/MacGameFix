// A device's enumerator name, answered as Windows answers it, in the game's process: for
// EA SPORTS FC 27.
//
// Windows knows every device's enumerator, the first component of its instance id ("HID" of
// HID\VID_845E&PID_0001\2&42fb4b8d&0&0000): CM_Get_DevNode_Registry_Property with
// CM_DRP_ENUMERATOR_NAME never fails for a device that exists. Wine 11.21's cfgmgr32
// (dlls/cfgmgr32/cfgmgr32.c, device_properties[]) reads it from a registry value
// "EnumeratorName" under the device's key in System\CurrentControlSet\Enum, which nothing
// writes: the question fails with CR_NO_SUCH_VALUE and the length comes back 0.
//
// EA SPORTS FC 27 1.0.143 (the title update of 2026-11-26) asks it of the parent of each raw
// input device when it sets its controllers up, and takes the length for good: with 0 it moves
// its heap with a negative count, about 140 MB of it. Other threads then fault on what was
// wiped, and all end in the game's own crash handler, which waits for good on a lock that was
// wiped too: the game looks hung, at a black window, a second after its input starts
// (RtlpWaitForCriticalSection "blocked by 0000" in the log).
//
// This answers the value from outside cfgmgr32, in the game's process only: it replaces the
// syscall table's entry for NtQueryValueKey (../mgf_hooks.h). Every query goes to ntdll first,
// unchanged. Only when one for "EnumeratorName" comes back STATUS_OBJECT_NAME_NOT_FOUND, and
// the key is a device's (...\Enum\<enumerator>\<device>\<instance>, by NtQueryKey), is it
// answered: a REG_SZ with the enumerator, the first of those three. A value a driver did write
// is still what is read. The same value written by hand into the prefix's registry let the game
// reach its menu (2026-11-26); the fix in Wine itself would be cfgmgr32 answering
// DEVPKEY_Device_EnumeratorName from the instance id.
//
// It is part of mgf-engine.dylib (../mgf-engine.c), which arms it in FC 27 alone.
// build-engine.sh builds it and runs its check (check.c): a Windows program that asks
// CM_DRP_ENUMERATOR_NAME of a device, under a runner with CodeWeavers' own files, with and
// without this fix armed.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../mgf_hooks.h"

#include <stdint.h>
#include <string.h>

#define TAG "enumerator-name"

typedef int32_t NTSTATUS;
#define STATUS_SUCCESS ((NTSTATUS)0)
#define STATUS_BUFFER_OVERFLOW ((NTSTATUS)0x80000005)
#define STATUS_BUFFER_TOO_SMALL ((NTSTATUS)0xC0000023)
#define STATUS_OBJECT_NAME_NOT_FOUND ((NTSTATUS)0xC0000034)

#define REG_SZ 1
enum { KeyValueBasicInformation, KeyValueFullInformation, KeyValuePartialInformation };
#define KeyNameInformation 3

struct unicode_string {
    uint16_t length, maximum_length;  // in bytes
    uint16_t *buffer;
};

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*query_value_fn)(void *key, const struct unicode_string *name, int info_class, void *info,
                                   uint32_t length, uint32_t *result_len);
typedef NTSTATUS (*query_key_fn)(void *key, int info_class, void *info, uint32_t length, uint32_t *result_len);

static const struct np_plugin_api *api;
static query_value_fn real_query_value;
static query_key_fn query_key;
static int told;

static uint16_t lower(uint16_t c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }

static int is(const uint16_t *s, unsigned chars, const char *ascii) {
    unsigned i;
    for (i = 0; i < chars && ascii[i]; i++)
        if (lower(s[i]) != (uint16_t)ascii[i]) return 0;
    return i == chars && !ascii[i];
}

// The enumerator of the device whose key this is, in `out` (chars, no terminator); 0 when the
// key is not ...\Enum\<enumerator>\<device>\<instance>.
static unsigned enumerator_of(void *key, uint16_t *out, unsigned max) {
    struct { uint32_t name_length; uint16_t name[512]; } info;
    uint32_t got = 0;
    unsigned chars, i, start = 0, parts = 0, first_end = 0;

    if (query_key(key, KeyNameInformation, &info, sizeof(info), &got) != STATUS_SUCCESS) return 0;
    chars = info.name_length / 2;
    if (chars > 512) return 0;
    // After the last "\Enum\".
    for (i = 0; i + 6 <= chars; i++)
        if (info.name[i] == '\\' && is(info.name + i + 1, 4, "enum") && info.name[i + 5] == '\\') start = i + 6;
    if (!start) return 0;
    for (i = start; i <= chars; i++) {
        if (i < chars && info.name[i] != '\\') continue;
        if (i == start || (i > start && info.name[i - 1] == '\\')) return 0;  // an empty component
        if (!parts++) first_end = i;
    }
    if (parts != 3 || first_end - start > max) return 0;
    memcpy(out, info.name + start, (first_end - start) * 2);
    return first_end - start;
}

static NTSTATUS query_value_hook(void *key, const struct unicode_string *name, int info_class, void *info,
                                 uint32_t length, uint32_t *result_len) {
    static const uint16_t value_name[] = {'E','n','u','m','e','r','a','t','o','r','N','a','m','e'};
    NTSTATUS status = real_query_value(key, name, info_class, info, length, result_len);
    uint16_t data[64];
    uint32_t data_size, name_size = sizeof(value_name), fixed, total, *head = info;
    unsigned chars;

    if (status != STATUS_OBJECT_NAME_NOT_FOUND || !name || !name->buffer || name->length != sizeof(value_name) ||
        !is(name->buffer, 14, "enumeratorname"))
        return status;
    if (info_class < KeyValueBasicInformation || info_class > KeyValuePartialInformation) return status;
    if (!(chars = enumerator_of(key, data, 63))) return status;
    data[chars] = 0;
    data_size = (chars + 1) * 2;

    // KEY_VALUE_BASIC_INFORMATION: TitleIndex, Type, NameLength, Name.
    // KEY_VALUE_FULL_INFORMATION: TitleIndex, Type, DataOffset, DataLength, NameLength, Name; the data.
    // KEY_VALUE_PARTIAL_INFORMATION: TitleIndex, Type, DataLength, Data.
    fixed = info_class == KeyValueFullInformation ? 20 : 12;
    total = info_class == KeyValueBasicInformation ? fixed + name_size
          : info_class == KeyValueFullInformation ? fixed + name_size + data_size
          : fixed + data_size;
    if (result_len) *result_len = total;
    if (!info || length < fixed) return STATUS_BUFFER_TOO_SMALL;
    head[0] = 0;
    head[1] = REG_SZ;
    if (info_class == KeyValueBasicInformation) {
        head[2] = name_size;
        memcpy(head + 3, value_name, length - fixed < name_size ? length - fixed : name_size);
    } else if (info_class == KeyValueFullInformation) {
        head[2] = fixed + name_size;
        head[3] = data_size;
        head[4] = name_size;
        memcpy(head + 5, value_name, length - fixed < name_size ? length - fixed : name_size);
        if (length > fixed + name_size)
            memcpy((char *)info + fixed + name_size, data,
                   length - fixed - name_size < data_size ? length - fixed - name_size : data_size);
    } else {
        head[2] = data_size;
        memcpy(head + 3, data, length - fixed < data_size ? length - fixed : data_size);
    }
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        api->log(TAG, "a device's enumerator name is answered from its key's path (the first one asked: %d characters)",
                 (int)chars);
    return length < total ? STATUS_BUFFER_OVERFLOW : STATUS_SUCCESS;
}

static void arm(const struct mach_header_64 *mh, intptr_t slide) {
    uintptr_t old, *slot = mgf_syscall_slot(api, mh, slide, "_NtQueryValueKey", &old);
    query_key = (query_key_fn)api->symbol(mh, slide, "_NtQueryKey");
    if (!slot || !query_key) {
        api->log(TAG, "no one syscall table entry for NtQueryValueKey, or no NtQueryKey, not armed");
        return;
    }
    real_query_value = (query_value_fn)old;
    if (!api->swap_pointer(slot, old, (uintptr_t)query_value_hook)) {
        api->log(TAG, "the syscall table could not be written, not armed");
        return;
    }
    api->log(TAG, "a device's EnumeratorName, which Wine reads from a value nothing writes, is answered");
}

// mgf-engine.dylib (../mgf-engine.c) arms this for the games that need it.
void mgf_enumerator_name_arm(const struct np_plugin_api *with, const struct mach_header_64 *mh, intptr_t slide) {
    api = with;
    arm(mh, slide);
}
