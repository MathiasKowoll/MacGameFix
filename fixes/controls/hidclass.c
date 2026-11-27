// hidclass.sys: a pad's collection with motors offered to xinput. What engine patch 0007 does in
// the Wine modules' hidclass.sys, done here for CodeWeavers' own.
//
// Wine's xinput finds its controllers through one device interface, WINEXINPUT, which only
// winexinput's own devices carry. bus.c gives a DualSense the haptics collections xinput drives a
// pad's motors through, in one of two places (xinput= in Game Feel's settings):
//   xinput=rumble  a second top-level collection that carries motors and nothing else, which
//                  hidclass makes a device of its own, "...&COL02". It has to be offered to xinput
//                  and to nobody else: it has the pad's vendor and product ids, so a client that
//                  finds its controller by walking the HID interface would see the pad twice, and
//                  Sony's library does exactly that.
//   xinput=pad     inside the pad's own collection: the pad itself is offered to xinput as well
//                  as to everyone else (xinput.c lets xinput read it).
//
// hidclass registers and switches a device's interface with two of ntoskrnl.exe's exports, and
// announces the device to raw input through one of win32u.dll's. When hidclass.sys is mapped,
// those three exports are pointed at functions here (run as Windows code, windows.h), so that
// hidclass.sys, and the drivers loaded after it, are bound to them; they act for hidclass.sys
// alone, told by the return address:
//   IoRegisterDeviceInterface  after the HID interface of a collection that is one of the two
//                              above, the WINEXINPUT one is registered for the same device
//   IoSetDeviceInterfaceState  and switched with it; the motors-only collection's HID interface
//                              is never switched on
//   NtUserCallHwndParam        the arrival and removal of the motors-only collection are not
//                              sent to raw input (hidclass.sys calls it for nothing but sending
//                              input: usage 8 on page 1, a multi-axis controller, is that
//                              collection's and no other device winebus opens has it)
// Which collection is which is told by the interface's name, which has the device's ids and
// collection, and by what bus.c did to that pad (mgf_xinput_pads): hidclass.sys reads the
// descriptor for it, which nothing here can reach.
//
// The Wine modules' hidclass.sys does all this itself: it is told by the text of the trace 0007
// added, "offered to xinput", and left alone.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pad.h"
#include "pe.h"
#include "windows.h"

// The pads bus.c gave xinput's collections, by the product id they are shown with.
struct mgf_xinput_pad mgf_xinput_pads[8];

#if defined(__x86_64__)
static const wine_guid hid_interface = {0x4d1e55b2, 0xf16f, 0x11cf, {0x88, 0xcb, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30}};
static const wine_guid winexinput_interface = {0x6c53d5fd, 0x6480, 0x440f, {0xb6, 0x18, 0x47, 0x67, 0x50, 0xc5, 0xe1, 0xa6}};

// What NtUserSendHardwareInput hands NtUserCallHwndParam (include/ntuser.h).
struct hardware_input {
    uint32_t flags;
    const struct { uint32_t type, padding, message; } *input;  // an INPUT: its type, and a HARDWAREINPUT's message
    const struct { uint32_t device, usage, count, length; } *hid;
};
#define INPUT_HARDWARE 2
#define WM_INPUT_DEVICE_CHANGE 0x00fe
#define MULTI_AXIS_CONTROLLER ((1u << 16) | 8)  // usage 8 on the generic desktop page

typedef int32_t (WINAPI *register_fn)(void *device, const wine_guid *class, struct unicode_string *reference,
                                      struct unicode_string *link);
typedef int32_t (WINAPI *set_state_fn)(struct unicode_string *link, uint8_t enable);
typedef uintptr_t (WINAPI *hwnd_param_fn)(void *window, uintptr_t param, uint32_t code);
typedef void (WINAPI *free_string_fn)(struct unicode_string *string);

static register_fn real_register;
static set_state_fn real_set_state;
static hwnd_param_fn real_hwnd_param;
static uintptr_t hidclass_start, hidclass_end;

// The collections offered to xinput: the HID interface's name, and the WINEXINPUT one made for it.
static struct offered {
    int used;
    bool motors_only;
    uint16_t name[200];
    struct unicode_string xinput;
} offered[8];

// ---- Run as Windows code (windows.h).

static bool from_hidclass(uintptr_t caller) { return caller >= hidclass_start && caller < hidclass_end; }

static uint16_t upper(uint16_t c) { return c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c; }

// Where `text` is in the name, without regard to case; -1 when it is not.
static int find(const struct unicode_string *name, const char *text) {
    unsigned chars = name->length / 2, length = 0;
    while (text[length]) length++;
    for (unsigned i = 0; i + length <= chars; i++) {
        unsigned c = 0;
        while (c < length && upper(name->buffer[i + c]) == (uint8_t)text[c]) c++;
        if (c == length) return (int)(i + length);
    }
    return -1;
}

static bool hex4(const struct unicode_string *name, int at, uint32_t *value) {
    *value = 0;
    if (at < 0 || (unsigned)at + 4 > name->length / 2u) return false;
    for (int i = 0; i < 4; i++) {
        uint16_t c = upper(name->buffer[at + i]);
        if (c >= '0' && c <= '9') *value = *value << 4 | (c - '0');
        else if (c >= 'A' && c <= 'F') *value = *value << 4 | (c - 'A' + 10);
        else return false;
    }
    return true;
}

// What a HID interface of this name is to xinput: 0 nothing, XINPUT_PAD the pad itself,
// XINPUT_RUMBLE the collection that carries motors and nothing else.
static int kind_of(const struct unicode_string *name) {
    uint32_t vendor, product;
    int collection = find(name, "&COL");
    if (!hex4(name, find(name, "VID_"), &vendor) || !hex4(name, find(name, "PID_"), &product) || vendor != SONY_VID)
        return 0;
    for (unsigned i = 0; i < COUNT_OF(mgf_xinput_pads); i++) {
        if (mgf_xinput_pads[i].product != product) continue;
        if (mgf_xinput_pads[i].mode == XINPUT_PAD && collection < 0) return XINPUT_PAD;
        if (mgf_xinput_pads[i].mode == XINPUT_RUMBLE && collection >= 0 && (unsigned)collection + 2 <= name->length / 2u &&
            name->buffer[collection] == '0' && name->buffer[collection + 1] == '2')
            return XINPUT_RUMBLE;
    }
    return 0;
}

static struct offered *offered_as(const struct unicode_string *name) {
    for (unsigned i = 0; i < COUNT_OF(offered); i++) {
        unsigned chars = name->length / 2, c = 0;
        if (offered[i].used != 2 || chars >= COUNT_OF(offered[i].name)) continue;
        while (c < chars && offered[i].name[c] == name->buffer[c]) c++;
        if (c == chars && !offered[i].name[c]) return &offered[i];
    }
    return NULL;
}

static WINAPI int32_t register_interface(void *device, const wine_guid *class, struct unicode_string *reference,
                                         struct unicode_string *link) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    int32_t status = real_register(device, class, reference, link);
    const uint64_t *asked = (const uint64_t *)class, *hid = (const uint64_t *)&hid_interface;
    struct offered *entry = NULL;
    int kind;

    if (status || !from_hidclass(caller) || !class || asked[0] != hid[0] || asked[1] != hid[1] || !link ||
        !link->buffer || link->length / 2u >= COUNT_OF(offered[0].name) || !(kind = kind_of(link)))
        return status;
    for (unsigned i = 0; i < COUNT_OF(offered) && !entry; i++) {
        int none = 0;
        if (__atomic_compare_exchange_n(&offered[i].used, &none, 1, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
            entry = &offered[i];
    }
    if (!entry) return status;
    if (real_register(device, &winexinput_interface, NULL, &entry->xinput)) {
        __atomic_store_n(&entry->used, 0, __ATOMIC_SEQ_CST);
        return status;
    }
    for (unsigned c = 0; c < link->length / 2u; c++) entry->name[c] = link->buffer[c];
    entry->name[link->length / 2] = 0;
    entry->motors_only = kind == XINPUT_RUMBLE;
    __atomic_store_n(&entry->used, 2, __ATOMIC_SEQ_CST);
    win_log(entry->motors_only ? "hidclass: the collection with motors alone is offered to xinput, and to nobody else"
                               : "hidclass: the pad is offered to xinput too", 0);
    return status;
}

static WINAPI int32_t set_state(struct unicode_string *link, uint8_t enable) {
    struct offered *entry = link && link->buffer && from_hidclass((uintptr_t)__builtin_return_address(0))
                                ? offered_as(link) : NULL;
    int32_t status;

    if (!entry) return real_set_state(link, enable);
    status = entry->motors_only ? 0 : real_set_state(link, enable);
    real_set_state(&entry->xinput, enable);
    if (!enable) {
        free_string_fn free_string = win_export(win_module("ntdll.dll"), "RtlFreeUnicodeString");
        if (free_string) free_string(&entry->xinput);
        __atomic_store_n(&entry->used, 0, __ATOMIC_SEQ_CST);
    }
    return status;
}

static WINAPI uintptr_t hwnd_param(void *window, uintptr_t param, uint32_t code) {
    const struct hardware_input *sent = (const struct hardware_input *)param;
    if (from_hidclass((uintptr_t)__builtin_return_address(0)) && sent && sent->input && sent->hid &&
        sent->input->type == INPUT_HARDWARE && sent->input->message == WM_INPUT_DEVICE_CHANGE &&
        sent->hid->usage == MULTI_AXIS_CONTROLLER) {
        for (unsigned i = 0; i < COUNT_OF(mgf_xinput_pads); i++)
            if (mgf_xinput_pads[i].mode == XINPUT_RUMBLE) return 1;
    }
    return real_hwnd_param(window, param, code);
}

// ---- Run on the macOS side, as the modules are mapped.

static struct pe_image ntoskrnl, win32u;

static void ntoskrnl_mapped(const struct pe_image *image) { ntoskrnl = *image; }
static void win32u_mapped(const struct pe_image *image) { win32u = *image; }

static void hidclass_mapped(const struct pe_image *image) {
    static int told;

    if (pe_has_text(image, "offered to xinput")) {
        pad_log("controls: hidclass.sys is MacGameFix's own here, which does this itself: left alone\n");
        return;
    }
    if (!real_register) {
        if (!ntoskrnl.base || !win32u.base) {
            pad_log("controls: ntoskrnl.exe or win32u.dll was not seen before hidclass.sys, it is left as it is\n");
            return;
        }
        if (!pe_take_export(&ntoskrnl, "IoRegisterDeviceInterface", register_interface, (void **)&real_register) ||
            !pe_take_export(&ntoskrnl, "IoSetDeviceInterfaceState", set_state, (void **)&real_set_state) ||
            !pe_take_export(&win32u, "NtUserCallHwndParam", hwnd_param, (void **)&real_hwnd_param)) {
            pad_log("controls: an export hidclass.sys calls could not be pointed elsewhere, xinput may not find the pad\n");
            return;
        }
    }
    hidclass_end = (uintptr_t)image->base + image->size;
    hidclass_start = (uintptr_t)image->base;
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        pad_log("controls: hidclass.sys offers a pad's collection with motors to xinput\n");
}
#endif

void mgf_controls_hidclass(void) {
#if defined(__x86_64__)
    if (pad_part_off("hidclass")) return;
    pe_on_map("ntoskrnl.exe", ntoskrnl_mapped);
    pe_on_map("win32u.dll", win32u_mapped);
    pe_on_map("hidclass.sys", hidclass_mapped);
#endif
}
