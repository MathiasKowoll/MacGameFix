// xinput: a Sony pad's own descriptor read in Sony's axis and button order. What engine patch
// 0008 does in the Wine modules' six xinput DLLs, done here for CodeWeavers' own.
//
// With xinput=pad the pad itself is an XInput controller (bus.c puts xinput's haptics collections
// in its descriptor, and hidclass.c offers it to xinput), and xinput reads its sticks and buttons
// with its descriptor as it is, in Sony's order. Wine's xinput knows one order, that of Wine's own
// winexinput driver: a DualSense's right stick would be its triggers, Cross would be B, and a
// stick pushed up would read down (xinput_map.h has both layouts).
//
// xinput reads everything about a pad through hid.dll. So nothing inside an xinput DLL is
// changed: five of hid.dll's exports are pointed at functions here (run as Windows code,
// windows.h), which answer as before unless the caller is an xinput DLL and the pad is a Sony one
// with its own descriptor, and then translate:
//   HidD_GetPreparsedData   the pad is noted when xinput opens it: Sony's vendor id and an X axis
//                           that starts at 0 (Wine's own descriptors have it signed), as 0008 tells
//   HidD_FreePreparsedData  and forgotten
//   HidP_GetValueCaps       the axes are given under the usages Wine's xinput looks for
//   HidP_GetUsageValue      an axis is read from where Sony has it, a stick's Y turned over, the
//                           hat counted as Wine counts it
//   HidP_GetUsages          the buttons renumbered; for the vendor page, which Wine's xinput takes
//                           for the Guide button, the PS button alone
// Which module is calling is told by the return address: the six DLLs' places are kept as they
// are mapped. Every other caller, a game reading the pad through HID itself among them, gets
// hid.dll's own answers.
//
// The Wine modules' xinput reads Sony's order itself and must not be translated for: it is told
// by the text of the trace 0008 added, "Sony's axis and button order", which CodeWeavers' has not.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pad.h"
#include "pe.h"
#include "windows.h"
#include "xinput_map.h"

#if defined(__x86_64__)
#define HIDP_STATUS_SUCCESS 0x00110000
#define HIDP_INPUT 0
#define PAGE_GENERIC 0x01
#define PAGE_BUTTON 0x09
#define PAGE_VENDOR 0xff00
#define SONY_VENDOR 0x054c

// HIDP_VALUE_CAPS, as much of it as is read here: 72 bytes.
struct value_caps {
    uint16_t usage_page;
    uint8_t before_range[10];
    uint8_t is_range;
    uint8_t before_limits[27];
    int32_t logical_min, logical_max, physical_min, physical_max;
    uint16_t usage_min, usage_max;
    uint16_t rest[6];
};
_Static_assert(sizeof(struct value_caps) == 72 && offsetof(struct value_caps, logical_min) == 40 &&
               offsetof(struct value_caps, usage_min) == 56 && offsetof(struct value_caps, is_range) == 12,
               "HIDP_VALUE_CAPS");
struct attributes { uint32_t size; uint16_t vendor, product, version; };

typedef uint8_t (WINAPI *get_preparsed_fn)(void *device, void **preparsed);
typedef uint8_t (WINAPI *free_preparsed_fn)(void *preparsed);
typedef uint8_t (WINAPI *get_attributes_fn)(void *device, struct attributes *attributes);
typedef int32_t (WINAPI *value_caps_fn)(int type, struct value_caps *caps, uint16_t *count, void *preparsed);
typedef int32_t (WINAPI *specific_caps_fn)(int type, uint16_t page, uint16_t collection, uint16_t usage,
                                           struct value_caps *caps, uint16_t *count, void *preparsed);
typedef int32_t (WINAPI *usage_value_fn)(int type, uint16_t page, uint16_t collection, uint16_t usage, uint32_t *value,
                                         void *preparsed, char *report, uint32_t length);
typedef int32_t (WINAPI *usages_fn)(int type, uint16_t page, uint16_t collection, uint16_t *usages, uint32_t *count,
                                    void *preparsed, char *report, uint32_t length);

static get_preparsed_fn real_get_preparsed;
static free_preparsed_fn real_free_preparsed;
static get_attributes_fn get_attributes;
static value_caps_fn real_value_caps;
static specific_caps_fn specific_caps;
static usage_value_fn real_usage_value;
static usages_fn real_usages;

// Where the xinput DLLs are mapped, written on the macOS side as each is.
static struct { uintptr_t start, end; } xinput_images[8];

// The Sony pads xinput has open, by their parsed descriptor, with the ranges translating needs.
static struct sony_pad {
    void *preparsed;  // NULL: free
    int32_t y_min, y_max, rz_min, rz_max, hat_min, hat_max;
} sony_pads[8];

// ---- Run as Windows code: nothing below calls out of this file, except through pointers.

static bool from_xinput(uintptr_t caller) {
    for (unsigned i = 0; i < 8; i++)
        if (caller >= xinput_images[i].start && caller < xinput_images[i].end) return true;
    return false;
}

static const struct sony_pad *sony_pad_of(void *preparsed, uintptr_t caller) {
    if (!preparsed || !from_xinput(caller)) return NULL;
    for (unsigned i = 0; i < 8; i++)
        if (sony_pads[i].preparsed == preparsed) return &sony_pads[i];
    return NULL;
}

static bool range_of(void *preparsed, uint16_t usage, int32_t *min, int32_t *max) {
    struct value_caps caps;
    uint16_t count = 1;
    if (specific_caps(HIDP_INPUT, PAGE_GENERIC, 0, usage, &caps, &count, preparsed) != HIDP_STATUS_SUCCESS || !count)
        return false;
    *min = caps.logical_min;
    *max = caps.logical_max;
    return true;
}

static WINAPI uint8_t get_preparsed(void *device, void **preparsed) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    uint8_t got = real_get_preparsed(device, preparsed);
    struct attributes attributes = {sizeof(attributes), 0, 0, 0};
    struct sony_pad pad = {0};
    int32_t x_min, x_max;

    if (!got || !from_xinput(caller) || !get_attributes(device, &attributes) || attributes.vendor != SONY_VENDOR ||
        !range_of(*preparsed, HID_USAGE_X, &x_min, &x_max) || x_min < 0)
        return got;
    // Read where Sony has them: the left stick's Y, the right stick's (Rz), the hat.
    if (!range_of(*preparsed, HID_USAGE_Y, &pad.y_min, &pad.y_max) ||
        !range_of(*preparsed, HID_USAGE_RZ, &pad.rz_min, &pad.rz_max))
        return got;
    range_of(*preparsed, HID_USAGE_HAT, &pad.hat_min, &pad.hat_max);
    for (unsigned i = 0; i < 8; i++) {
        void *none = NULL;
        if (__atomic_compare_exchange_n(&sony_pads[i].preparsed, &none, (void *)1, false, __ATOMIC_SEQ_CST,
                                        __ATOMIC_SEQ_CST)) {
            pad.preparsed = *preparsed;
            sony_pads[i] = pad;
            break;
        }
    }
    return got;
}

static WINAPI uint8_t free_preparsed(void *preparsed) {
    for (unsigned i = 0; i < 8 && preparsed; i++)
        if (sony_pads[i].preparsed == preparsed) __atomic_store_n(&sony_pads[i].preparsed, NULL, __ATOMIC_SEQ_CST);
    return real_free_preparsed(preparsed);
}

static WINAPI int32_t value_caps(int type, struct value_caps *caps, uint16_t *count, void *preparsed) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    int32_t status = real_value_caps(type, caps, count, preparsed);
    if (status != HIDP_STATUS_SUCCESS || type != HIDP_INPUT || !sony_pad_of(preparsed, caller)) return status;
    for (unsigned i = 0; i < *count; i++) {
        if (caps[i].usage_page != PAGE_GENERIC || caps[i].is_range) continue;
        uint16_t usage = sony_axis(caps[i].usage_min);
        if (caps[i].usage_max == caps[i].usage_min) caps[i].usage_max = usage;
        caps[i].usage_min = usage;
    }
    return status;
}

static WINAPI int32_t usage_value(int type, uint16_t page, uint16_t collection, uint16_t usage, uint32_t *value,
                                  void *preparsed, char *report, uint32_t length) {
    const struct sony_pad *pad = sony_pad_of(preparsed, (uintptr_t)__builtin_return_address(0));
    int32_t status;
    if (!pad || type != HIDP_INPUT || page != PAGE_GENERIC)
        return real_usage_value(type, page, collection, usage, value, preparsed, report, length);
    status = real_usage_value(type, page, collection, sony_axis(usage), value, preparsed, report, length);
    if (status != HIDP_STATUS_SUCCESS) return status;
    if (usage == HID_USAGE_HAT) *value = sony_hat(*value, pad->hat_min, pad->hat_max);
    else if (usage == HID_USAGE_Y) *value = sony_turned(*value, pad->y_min, pad->y_max);
    else if (usage == HID_USAGE_RY) *value = sony_turned(*value, pad->rz_min, pad->rz_max);
    return status;
}

static WINAPI int32_t usages(int type, uint16_t page, uint16_t collection, uint16_t *out, uint32_t *count,
                             void *preparsed, char *report, uint32_t length) {
    const struct sony_pad *pad = sony_pad_of(preparsed, (uintptr_t)__builtin_return_address(0));
    uint16_t pressed[32];
    uint32_t held = 32, given = 0;
    int32_t status;

    if (!pad || type != HIDP_INPUT || (page != PAGE_BUTTON && page != PAGE_VENDOR) || !out || !count)
        return real_usages(type, page, collection, out, count, preparsed, report, length);
    status = real_usages(type, PAGE_BUTTON, collection, pressed, &held, preparsed, report, length);
    if (status != HIDP_STATUS_SUCCESS) {
        *count = 0;
        return status;
    }
    for (uint32_t i = 0; i < held && given < *count; i++) {
        uint16_t button = page == PAGE_BUTTON ? sony_button(pressed[i]) : pressed[i] == SONY_BUTTON_PS;
        if (button) out[given++] = button;
    }
    *count = given;
    return HIDP_STATUS_SUCCESS;
}

// ---- Run on the macOS side, as the modules are mapped.

static bool has_text(const struct pe_image *image, const char *text) {
    uint8_t *start;
    uint32_t size;
    bool code;
    for (unsigned i = 0; pe_section(image, i, &start, &size, &code); i++)
        if (!code && size && memmem(start, size, text, strlen(text))) return true;
    return false;
}

static void xinput_mapped(const struct pe_image *image) {
    if (has_text(image, "Sony's axis and button order")) {
        pad_log("controls: this xinput is MacGameFix's own, which reads a Sony pad itself: not translated for\n");
        return;
    }
    for (unsigned i = 0; i < 8; i++) {
        if (xinput_images[i].start == (uintptr_t)image->base) return;
        if (xinput_images[i].start) continue;
        xinput_images[i].end = (uintptr_t)image->base + image->size;
        xinput_images[i].start = (uintptr_t)image->base;
        return;
    }
}

static void hid_mapped(const struct pe_image *image) {
    static const struct { const char *name; void *with; void **real; } taken[] = {
        {"HidD_GetPreparsedData", get_preparsed, (void **)&real_get_preparsed},
        {"HidD_FreePreparsedData", free_preparsed, (void **)&real_free_preparsed},
        {"HidP_GetValueCaps", value_caps, (void **)&real_value_caps},
        {"HidP_GetUsageValue", usage_value, (void **)&real_usage_value},
        {"HidP_GetUsages", usages, (void **)&real_usages},
    };
    enum { COUNT = sizeof(taken) / sizeof(taken[0]), JUMP = 12 };
    static int told;
    uint8_t *found[COUNT], *room;

    get_attributes = (get_attributes_fn)pe_export(image, "HidD_GetAttributes");
    specific_caps = (specific_caps_fn)pe_export(image, "HidP_GetSpecificValueCaps");
    for (unsigned i = 0; i < COUNT; i++) found[i] = pe_export(image, taken[i].name);
    for (unsigned i = 0; i < COUNT; i++)
        if (!found[i] || !get_attributes || !specific_caps) {
            pad_log("controls: hid.dll lacks an export xinput's translation needs, left as it is\n");
            return;
        }
    if (!(room = pe_room(image, COUNT * JUMP))) {
        pad_log("controls: no memory free within 4 GB above hid.dll, left as it is\n");
        return;
    }
    // An export's entry reaches 4 GB above the image, so each goes through a jump in memory there:
    // mov rax, <the function here>; jmp rax.
    for (unsigned i = 0; i < COUNT; i++) {
        uint8_t jump[JUMP] = {0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xe0};
        memcpy(jump + 2, &taken[i].with, 8);
        memcpy(room + i * JUMP, jump, JUMP);
        *taken[i].real = found[i];
    }
    if (!pe_runs(room, COUNT * JUMP)) {
        pad_log("controls: hid.dll could not be written, left as it is\n");
        return;
    }
    for (unsigned i = 0; i < COUNT; i++)
        if (!pe_point_export(image, taken[i].name, room + i * JUMP)) {
            pad_log("controls: hid.dll's %s could not be pointed elsewhere\n", taken[i].name);
            return;
        }
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        pad_log("controls: hid.dll answers xinput about a Sony pad in the order xinput reads\n");
}
#endif

void mgf_controls_xinput(void) {
#if defined(__x86_64__)
    static const char *const dlls[] = {"xinput1_1.dll", "xinput1_2.dll", "xinput1_3.dll",
                                       "xinput1_4.dll", "xinput9_1_0.dll", "xinputuap.dll"};
    if (pad_part_off("xinput")) return;
    for (unsigned i = 0; i < sizeof(dlls) / sizeof(dlls[0]); i++) pe_on_map(dlls[i], xinput_mapped);
    pe_on_map("hid.dll", hid_mapped);
#endif
}
