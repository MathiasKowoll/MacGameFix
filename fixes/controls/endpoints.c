// An audio endpoint listed in SetupAPI, as Windows lists it. What engine patch 0009 does in the
// Wine modules' mmdevapi.dll, done here from the macOS side, for CodeWeavers' own.
//
// Windows has a software device for every audio endpoint, SWD\MMDEVAPI\<endpoint id>, of the
// AudioEndpoint class, with the audio render or capture interface, linked while the endpoint is
// there. A game that looks for a pad's audio output through SetupAPI, matching its container
// (SPDRP_BASE_CONTAINERID) against the pad's HID device, finds it there: Nioh 3 does, and stops
// at the first endpoint without a container. Wine's mmdevapi.dll makes no such device.
//
// SetupAPI reads all of this from the registry, so it is written there, with ntdll.so's own
// registry calls, when mmdevapi asks the driver about an endpoint (audio.c: it asks one question
// of each endpoint every time it lists them):
//   Enum\SWD\MMDEVAPI\<id>: ClassGUID, and ContainerId: the USB output's (audio.c), or the
//     computer's, {00000000-0000-0000-FFFF-FFFFFFFFFFFF}, which Windows gives an endpoint that is
//     part of no other device;
//   Control\DeviceClasses\<interface>\##?#SWD#MMDEVAPI#<id>#<interface>: DeviceInstance; under
//     "#", SymbolicLink, \\?\SWD#MMDEVAPI#<id>#<interface> (a path ActivateAudioInterfaceAsync
//     takes); under "#\Control", Linked = 1.
// "#\Control" is made volatile, as ntoskrnl makes a device's: the link is gone with the
// wineserver. Links an earlier session left (the Wine modules' mmdevapi.dll kept them in the
// prefix) are unlinked once a session, by whichever process lists endpoints first: it is the one
// that makes the volatile key Control\MacGameFix endpoints.
//
// Not covered: an endpoint that goes away while the session lasts stays linked until the
// wineserver ends.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include <stdio.h>
#include <string.h>
#include "mmdevapi.h"
#include "pad.h"
#include "../../app/notproton-plugins/notproton_plugin.h"

typedef int32_t NTSTATUS;
typedef void *HANDLE;

#define KEY_ALL_ACCESS 0xf003f
#define OBJ_CASE_INSENSITIVE 0x40
#define REG_OPTION_VOLATILE 1
#define REG_CREATED_NEW_KEY 1
#define REG_SZ 1
#define REG_DWORD 4
#define KeyBasicInformation 0

struct unicode_string {
    uint16_t length, maximum_length;  // in bytes
    uint16_t *buffer;
};
struct object_attributes {
    uint32_t length;
    HANDLE root;
    struct unicode_string *name;
    uint32_t attributes;
    void *security_descriptor, *security_quality_of_service;
};

// ntdll.so is built for the host ABI, not ms_abi.
static NTSTATUS (*create_key)(HANDLE *key, uint32_t access, const struct object_attributes *attr, uint32_t title_index,
                              const struct unicode_string *class, uint32_t options, uint32_t *disposition);
static NTSTATUS (*set_value)(HANDLE key, const struct unicode_string *name, uint32_t title_index, uint32_t type,
                             const void *data, uint32_t count);
static NTSTATUS (*enumerate_key)(HANDLE key, uint32_t index, int info_class, void *info, uint32_t length,
                                 uint32_t *result_len);
static NTSTATUS (*close_handle)(HANDLE handle);

static const char control_set[] = "\\Registry\\Machine\\System\\CurrentControlSet";
static const char endpoint_class[] = "{c166523c-fe0c-4a94-a586-f1a80cfbbf3e}";
static const char *const interface_class[2] = {
    "{e6327cad-dcec-4949-ae8a-991e976a79d2}",  // render
    "{2eef81be-33fa-4800-9670-1cd474972c3f}",  // capture
};

static unsigned wide(uint16_t *to, unsigned max, const char *from) {
    unsigned n = 0;
    for (; from[n] && n + 1 < max; n++) to[n] = (uint8_t)from[n];
    to[n] = 0;
    return n;
}

// The key at `path` under `root` (or at the whole path, with no root), made level by level:
// NtCreateKey makes the last component only. `options` are for a key this makes.
static HANDLE key_at(HANDLE root, const char *path, uint32_t options, bool *made) {
    HANDLE key = root;
    if (made) *made = false;
    // A whole path starts with "\Registry\Machine", which is one name to open, not two to make.
    const char *at = path, *end;
    bool first = !root;
    while (*at) {
        uint16_t name[300];
        struct unicode_string text = {0, 0, name};
        struct object_attributes attr = {sizeof(attr), key, &text, OBJ_CASE_INSENSITIVE, NULL, NULL};
        uint32_t disposition = 0;
        HANDLE next = NULL;
        char part[300];
        size_t length;

        if (first) end = strstr(at, "\\System");
        else end = strchr(at, '\\');
        if (!end) end = at + strlen(at);
        length = (size_t)(end - at);
        if (!length || length >= sizeof(part)) break;
        memcpy(part, at, length);
        part[length] = 0;
        text.length = (uint16_t)(wide(name, 300, part) * 2);
        text.maximum_length = text.length + 2;
        NTSTATUS status = create_key(&next, KEY_ALL_ACCESS, &attr, 0, NULL, options, &disposition);
        if (key != root) close_handle(key);
        if (status) return NULL;
        key = next;
        if (made) *made = disposition == REG_CREATED_NEW_KEY;
        first = false;
        at = *end ? end + 1 : end;
    }
    return key == root ? NULL : key;
}

static void set_text(HANDLE key, const char *name, const char *value) {
    uint16_t wide_name[64], wide_value[400];
    struct unicode_string text = {(uint16_t)(wide(wide_name, 64, name) * 2), 0, wide_name};
    unsigned chars = wide(wide_value, 400, value);
    set_value(key, &text, 0, REG_SZ, wide_value, (chars + 1) * 2);
}

static void set_linked(HANDLE link, uint32_t linked) {
    uint16_t name[] = {'L', 'i', 'n', 'k', 'e', 'd'};
    struct unicode_string text = {sizeof(name), sizeof(name), name};
    HANDLE control = key_at(link, "#\\Control", REG_OPTION_VOLATILE, NULL);
    if (!control) return;
    set_value(control, &text, 0, REG_DWORD, &linked, sizeof(linked));
    close_handle(control);
}

// The links an earlier session left: unlinked, once a session.
static void unlink_stale(void) {
    char path[160];
    bool first;
    HANDLE marker;

    snprintf(path, sizeof(path), "%s\\Control\\MacGameFix endpoints", control_set);
    marker = key_at(NULL, path, REG_OPTION_VOLATILE, &first);
    if (marker) close_handle(marker);
    if (!marker || !first) return;
    for (unsigned flow = 0; flow < 2; flow++) {
        struct { int64_t last_write; uint32_t title_index, name_length; uint16_t name[256]; } info;
        uint32_t got;
        HANDLE class_key;

        snprintf(path, sizeof(path), "%s\\Control\\DeviceClasses\\%s", control_set, interface_class[flow]);
        if (!(class_key = key_at(NULL, path, 0, NULL))) continue;
        for (uint32_t i = 0; !enumerate_key(class_key, i, KeyBasicInformation, &info, sizeof(info) - 2, &got); i++) {
            static const char ours[] = "##?#SWD#MMDEVAPI#";
            char name[257];
            unsigned chars = info.name_length / 2, c;
            HANDLE link;

            for (c = 0; c < chars && c < 256; c++) name[c] = info.name[c] < 0x80 ? (char)info.name[c] : '?';
            name[c] = 0;
            if (strncasecmp(name, ours, sizeof(ours) - 1)) continue;
            if (!(link = key_at(class_key, name, 0, NULL))) continue;
            set_linked(link, 0);
            close_handle(link);
        }
        close_handle(class_key);
    }
}

void mgf_endpoint_listed(const wine_guid *guid, int flow, const wine_guid *container) {
    static int unlinked;
    char id[80], instance[120], symlink[200], path[400], text[40];
    HANDLE key;

    if (!create_key || flow < 0 || flow > 1) return;
    if (!__atomic_exchange_n(&unlinked, 1, __ATOMIC_RELAXED)) unlink_stale();

    snprintf(id, sizeof(id), "{0.0.%d.00000000}.{%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}", flow, guid->Data1,
             guid->Data2, guid->Data3, guid->Data4[0], guid->Data4[1], guid->Data4[2], guid->Data4[3], guid->Data4[4],
             guid->Data4[5], guid->Data4[6], guid->Data4[7]);
    snprintf(instance, sizeof(instance), "SWD\\MMDEVAPI\\%s", id);
    snprintf(symlink, sizeof(symlink), "\\\\?\\SWD#MMDEVAPI#%s#%s", id, interface_class[flow]);

    snprintf(path, sizeof(path), "%s\\Enum\\%s", control_set, instance);
    if ((key = key_at(NULL, path, 0, NULL))) {
        if (container)
            snprintf(text, sizeof(text), "{%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}", container->Data1,
                     container->Data2, container->Data3, container->Data4[0], container->Data4[1], container->Data4[2],
                     container->Data4[3], container->Data4[4], container->Data4[5], container->Data4[6],
                     container->Data4[7]);
        else
            snprintf(text, sizeof(text), "{00000000-0000-0000-FFFF-FFFFFFFFFFFF}");
        set_text(key, "ClassGUID", endpoint_class);
        set_text(key, "ContainerId", text);
        close_handle(key);
    }

    snprintf(path, sizeof(path), "%s\\Control\\DeviceClasses\\%s\\##?#SWD#MMDEVAPI#%s#%s", control_set,
             interface_class[flow], id, interface_class[flow]);
    if ((key = key_at(NULL, path, 0, NULL))) {
        HANDLE reference;
        set_text(key, "DeviceInstance", instance);
        if ((reference = key_at(key, "#", 0, NULL))) {
            set_text(reference, "SymbolicLink", symlink);
            close_handle(reference);
        }
        set_linked(key, 1);
        close_handle(key);
    }
}

// Called with ntdll.so, when it has loaded.
void mgf_controls_endpoints_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide) {
    void *create = (void *)api->symbol(mh, slide, "_NtCreateKey"), *set = (void *)api->symbol(mh, slide, "_NtSetValueKey");
    void *enumerate = (void *)api->symbol(mh, slide, "_NtEnumerateKey"), *close = (void *)api->symbol(mh, slide, "_NtClose");
    if (!create || !set || !enumerate || !close) {
        pad_log("controls: ntdll.so lacks a registry call, audio endpoints are not listed in SetupAPI\n");
        return;
    }
    set_value = set;
    enumerate_key = enumerate;
    close_handle = close;
    create_key = create;
}
