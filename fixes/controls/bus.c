// The winebus part: CodeWeavers' own winebus.so, the DualSense driven as engine patches 0004,
// 0006, 0013, 0014, 0016 and 0030 drove it, from outside the file.
//
// winebus.so reaches a pad only through IOKit's HID calls, which it imports. This part takes
// those imports' places in winebus.so (each one's pointer, in the image's data), so it sees a
// DualSense as winebus does, and answers for it:
//   - a Bluetooth pad, with bluetooth=wired, is a USB pad: its transport, the wired pad's report
//     descriptor, and a USB interface for get_usb_device_info to read (interface 3, HID, as the
//     pad has on a cable); its input 0x31 is given as the wired 0x01, its output goes to the
//     pad's one writer (bt.c), and the wired client's "radio off" (feature 0x08, 2) is kept from
//     it;
//   - an Edge, with edge=dualsense, is the standard pad: its product id, name and descriptor,
//     and on a cable its 48-byte output padded to the Edge's 64;
//   - either pad, with pad_as=dualshock4, is a USB DualShock 4: its id, name, descriptor and
//     reports, translated both ways (dualshock4.h);
//   - with xinput=rumble or xinput=pad, the haptics collections Wine's xinput drives the motors
//     through are added to the descriptor, and what xinput writes there becomes the pad's motors;
//   - any DualSense or Edge: the trigger effects Game Feel chooses (triggers.c), the rumble
//     emulation of firmware 2.24, the motor power with motor_power=full, and the observed: lines
//     MacGameFix reads back.
// Everything else goes to IOKit unchanged.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include <dlfcn.h>
#include <mach-o/loader.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/usb/USBSpec.h>
#include "controls.h"
#include "../../app/notproton-plugins/notproton_plugin.h"

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct pad *pads;

static struct pad *pad_of(IOHIDDeviceRef device) {
    pthread_mutex_lock(&lock);
    struct pad *p = pads;
    while (p && p->device != device) p = p->next;
    pthread_mutex_unlock(&lock);
    return p;
}

// IOKit itself, for the calls this part answers.
static CFTypeRef (*real_get_property)(IOHIDDeviceRef, CFStringRef);
static IOReturn (*real_set_report)(IOHIDDeviceRef, IOHIDReportType, CFIndex, const uint8_t *, CFIndex);
static IOReturn (*real_get_report)(IOHIDDeviceRef, IOHIDReportType, CFIndex, uint8_t *, CFIndex *);
static void (*real_register_input)(IOHIDDeviceRef, uint8_t *, CFIndex, IOHIDReportCallback, void *);
static void (*real_register_matching)(IOHIDManagerRef, IOHIDDeviceCallback, void *);
static void (*real_register_removal)(IOHIDManagerRef, IOHIDDeviceCallback, void *);
static io_service_t (*real_get_service)(IOHIDDeviceRef);
static kern_return_t (*real_parent)(io_registry_entry_t, const io_name_t, io_registry_entry_t *);
static boolean_t (*real_conforms)(io_object_t, const io_name_t);
static CFTypeRef (*real_create_property)(io_registry_entry_t, CFStringRef, CFAllocatorRef, IOOptionBits);
static kern_return_t (*real_release)(io_object_t);

static uint32_t number(CFTypeRef value) {
    int n = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberIntType, &n);
    return (uint32_t)n;
}

static CFNumberRef cf_number(int value) {
    return CFNumberCreate(NULL, kCFNumberIntType, &value);
}

// XInput's vibration on a DualSense (xinput=rumble), and the pad as an XInput controller
// (xinput=pad). Wine's xinput drives a pad's motors through a HID haptics collection and through
// nothing else, and no descriptor Sony ships has one. Replacing the pad's descriptor, as the SDL
// bus does, costs the adaptive triggers, the haptics and Sony's own library. So the pad's
// descriptor is left as it is and one more top-level collection is added after it: a multi-axis
// controller with no axis and no button, and two haptics collections, rumble and buzz, winebus's
// own template (hid_device_add_haptics). hidclass makes it a device of its own and offers it to
// xinput only (patch 0007). What xinput writes to it becomes the pad's output report 0x02 with the
// motors.
//
// A multi-axis controller and not a gamepad, so that a game counting pads does not count it (Beast
// of Reincarnation lost half its frame rate to that, 2026-09-09); a byte on the vendor page so it
// has an input report, which no client reads as an axis; no button, since a button that is never
// pressed made Ghost of Tsushima drop a held L3. The ids are ones neither the DualSense's nor the
// Edge's descriptor uses.
//
// For a game that reads nothing but XInput, xinput=pad puts the two haptics collections inside
// the pad's own top-level collection instead, so that hidclass offers the pad itself to xinput,
// which reads its sticks and buttons (patch 0008 teaches it Sony's order) and drives its motors
// through the same reports. The pad's own report lengths do not move: the feature report added is
// 17 bytes and the output 5, under what the pad already declares.
#define XINPUT_OUTPUT_ID  0x03
#define XINPUT_FEATURE_ID 0x04
// A pad shown as a DualShock 4 declares feature 0x04 itself, so its collection for xinput takes
// 0x07, which the DualShock 4's descriptor leaves free.
#define XINPUT_FEATURE_ID_DS4 0x07
#define HID_USAGE_HAPTICS_WAVEFORM_BUZZ   0x1004
#define HID_USAGE_HAPTICS_WAVEFORM_RUMBLE 0x1005

// winebus's templates, as Wine's psh_hid_macros.h writes them out (engine patch 0006).
static const uint8_t xinput_endpoint_head[] = {
    0x05, 0x01, 0x09, 0x08, 0xa1, 0x01, 0x85, 0x06, 0x06, 0x00, 0xff, 0x09,
    0x20, 0x15, 0x00, 0x26, 0xff, 0x00, 0x35, 0x00, 0x45, 0x00, 0x65, 0x00,
    0x55, 0x00, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02, 0x81, 0x03,
};
static const uint8_t xinput_haptics_collection[] = {
    0x06, 0x0e, 0x00, 0x09, 0x01, 0xa1, 0x02, 0x85, 0x04, 0x09, 0x10, 0xa1,
    0x04, 0x0b, 0x03, 0x00, 0x0a, 0x00, 0x75, 0x10, 0x95, 0x01, 0xb1, 0x42,
    0xc0, 0x09, 0x11, 0xa1, 0x04, 0x0b, 0x03, 0x00, 0x0a, 0x00, 0x75, 0x10,
    0x95, 0x01, 0xb1, 0x42, 0xc0, 0x09, 0x28, 0x66, 0x01, 0x10, 0x55, 0xfd,
    0x17, 0x00, 0x00, 0x00, 0x00, 0x27, 0xff, 0xff, 0xff, 0x7f, 0x75, 0x20,
    0x95, 0x01, 0xb1, 0x02, 0x65, 0x00, 0x55, 0x00, 0x85, 0x03, 0x09, 0x23,
    0x17, 0x00, 0x00, 0x00, 0x00, 0x27, 0xff, 0xff, 0x00, 0x00, 0x75, 0x10,
    0x95, 0x01, 0x91, 0x02, 0xc0,
};
static const uint8_t xinput_endpoint_tail[] = {0xc0};

// The descriptor the game is shown: the DualShock 4's, the wired pad's, or the pad's own, with
// xinput's collections where they go. NULL when it is the pad's own unchanged.
static CFDataRef shown_descriptor(struct pad *p) {
    CFDataRef own = real_get_property(p->device, CFSTR(kIOHIDReportDescriptorKey));
    const uint8_t *base = own ? CFDataGetBytePtr(own) : NULL;
    size_t size = own ? (size_t)CFDataGetLength(own) : 0, extra = 0;
    uint8_t *buffer;
    CFDataRef data;

    if (p->ds4) {
        base = ds4_usb_descriptor;
        size = sizeof(ds4_usb_descriptor);
    } else if (p->bt || p->as_standard) {
        bool edge = p->bt ? p->bt->edge : false;
        base = edge ? ds_edge_usb_descriptor : ds_usb_descriptor;
        size = edge ? ds_edge_usb_descriptor_size : ds_usb_descriptor_size;
    } else if (!p->xinput) return NULL;
    if (!base) return NULL;
    // Rumble first, then buzz: xinput tells them apart by the waveform the feature report names
    // for each (get_report).
    if (p->xinput == XINPUT_RUMBLE)
        extra = sizeof(xinput_endpoint_head) + 2 * sizeof(xinput_haptics_collection) + sizeof(xinput_endpoint_tail);
    else if (p->xinput == XINPUT_PAD)
        extra = 2 * sizeof(xinput_haptics_collection);
    if (!(buffer = malloc(size + extra))) return NULL;
    if (p->xinput == XINPUT_PAD) {
        // Before the item that closes the last top-level collection.
        size_t i = 0, depth = 0, close = size;
        while (i < size) {
            size_t item = 1 + ((base[i] & 3) == 3 ? 4 : (base[i] & 3));
            if ((base[i] & 0xfc) == 0xa0) depth++;
            else if ((base[i] & 0xfc) == 0xc0 && depth && !--depth) close = i;
            i += item;
        }
        if (close == size || i != size || depth) {
            pad_log("cannot place the haptics collections in the %s's descriptor\n", p->model);
            memcpy(buffer, base, size);
            extra = 0;
        } else {
            memcpy(buffer, base, close);
            memcpy(buffer + close, xinput_haptics_collection, sizeof(xinput_haptics_collection));
            memcpy(buffer + close + sizeof(xinput_haptics_collection), xinput_haptics_collection,
                   sizeof(xinput_haptics_collection));
            memcpy(buffer + close + extra, base + close, size - close);
        }
    } else {
        memcpy(buffer, base, size);
        if (extra) {
            uint8_t *at = buffer + size;
            memcpy(at, xinput_endpoint_head, sizeof(xinput_endpoint_head));
            at += sizeof(xinput_endpoint_head);
            memcpy(at, xinput_haptics_collection, sizeof(xinput_haptics_collection));
            at += sizeof(xinput_haptics_collection);
            memcpy(at, xinput_haptics_collection, sizeof(xinput_haptics_collection));
            at += sizeof(xinput_haptics_collection);
            memcpy(at, xinput_endpoint_tail, sizeof(xinput_endpoint_tail));
            if (p->ds4) {
                // The feature report id of both haptics collections, REPORT_ID(1, 0x04), found
                // item by item.
                for (size_t i = size; i + 1 < size + extra; i += 1 + ((buffer[i] & 3) == 3 ? 4 : (buffer[i] & 3)))
                    if (buffer[i] == 0x85 && buffer[i + 1] == XINPUT_FEATURE_ID) buffer[i + 1] = XINPUT_FEATURE_ID_DS4;
            }
        }
    }
    data = CFDataCreate(NULL, buffer, (CFIndex)(size + extra));
    free(buffer);
    return data;
}

// The pad's firmware version, bytes 44 and 45 of feature report 0x20, as SDL reads it; 0 when it
// cannot be read.
static unsigned pad_firmware(IOHIDDeviceRef device) {
    uint8_t data[80] = {0x20};
    CFIndex length = sizeof(data);

    if (IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x20, data, &length) || length < 46) return 0;
    return data[44] | (data[45] << 8);
}

// A Bluetooth pad shown as wired has no USB interface. winebus reads one for every USB device
// (get_usb_device_info): it gets the HID interface a DualSense has on a cable, number 3, through
// two stand-ins for IOKit's objects that only these calls know. Without one it would take the
// pad's USB bus type away again, and with it the container games find the haptics by.
#define FAKE_SERVICE   ((io_service_t)0x7ffffff1)
#define FAKE_INTERFACE ((io_service_t)0x7ffffff2)

static io_service_t get_service(IOHIDDeviceRef device) {
    struct pad *p = pad_of(device);
    return p && p->bt ? FAKE_SERVICE : real_get_service(device);
}

static kern_return_t parent(io_registry_entry_t entry, const io_name_t plane, io_registry_entry_t *out) {
    if (entry == FAKE_SERVICE) {
        *out = FAKE_INTERFACE;
        return KERN_SUCCESS;
    }
    if (entry == FAKE_INTERFACE) return KERN_INVALID_ARGUMENT;
    return real_parent(entry, plane, out);
}

static boolean_t conforms(io_object_t object, const io_name_t class_name) {
    if (object == FAKE_INTERFACE) return !strcmp(class_name, "IOUSBHostInterface");
    if (object == FAKE_SERVICE) return false;
    return real_conforms(object, class_name);
}

static CFTypeRef create_property(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    if (entry != FAKE_INTERFACE && entry != FAKE_SERVICE) return real_create_property(entry, key, allocator, options);
    int value = -1;
    if (entry == FAKE_INTERFACE) {
        if (!CFStringCompare(key, CFSTR(kUSBHostMatchingPropertyInterfaceClass), 0)) value = 3;
        else if (!CFStringCompare(key, CFSTR(kUSBHostMatchingPropertyInterfaceSubClass), 0)) value = 0;
        else if (!CFStringCompare(key, CFSTR(kUSBHostMatchingPropertyInterfaceProtocol), 0)) value = 0;
        else if (!CFStringCompare(key, CFSTR(kUSBHostMatchingPropertyInterfaceNumber), 0)) value = 3;
    }
    return value < 0 ? NULL : CFNumberCreate(allocator, kCFNumberIntType, &value);
}

static kern_return_t release(io_object_t object) {
    return object == FAKE_SERVICE || object == FAKE_INTERFACE ? KERN_SUCCESS : real_release(object);
}

static CFTypeRef get_property(IOHIDDeviceRef device, CFStringRef key) {
    static CFNumberRef standard_pid, ds4_pid;
    struct pad *p = pad_of(device);

    if (p) {
        if (p->bt && !CFStringCompare(key, CFSTR(kIOHIDTransportKey), 0)) return CFSTR(kIOHIDTransportUSBValue);
        if (p->descriptor && !CFStringCompare(key, CFSTR(kIOHIDReportDescriptorKey), 0)) return p->descriptor;
        if (!CFStringCompare(key, CFSTR(kIOHIDProductKey), 0)) {
            if (p->ds4) return CFSTR("Wireless Controller");
            if (p->as_standard) return CFSTR("DualSense Wireless Controller");
        }
        if (!CFStringCompare(key, CFSTR(kIOHIDProductIDKey), 0)) {
            if (!standard_pid) standard_pid = cf_number(DUALSENSE_PID);
            if (!ds4_pid) ds4_pid = cf_number(DS4_PID);
            if (p->ds4) return ds4_pid;
            if (p->as_standard) return standard_pid;
        }
    }
    return real_get_property(device, key);
}

// A DualSense or Edge winebus has found: what it is, how the game is shown it, and the writer of
// a Bluetooth pad.
static void pad_found(IOHIDDeviceRef device) {
    uint32_t vid = number(real_get_property(device, CFSTR(kIOHIDVendorIDKey)));
    uint32_t pid = number(real_get_property(device, CFSTR(kIOHIDProductIDKey)));
    CFTypeRef transport = real_get_property(device, CFSTR(kIOHIDTransportKey));
    bool string = transport && CFGetTypeID(transport) == CFStringGetTypeID();
    bool bluetooth = string && (!CFStringCompare(transport, CFSTR(kIOHIDTransportBluetoothValue), 0) ||
                                !CFStringCompare(transport, CFSTR(kIOHIDTransportBluetoothLowEnergyValue), 0));
    bool usb = string && !CFStringCompare(transport, CFSTR(kIOHIDTransportUSBValue), 0);
    struct pad *p;

    if (vid != SONY_VID || (pid != DUALSENSE_PID && pid != DS_EDGE_PID)) return;
    if (!(p = calloc(1, sizeof(*p)))) return;
    p->device = device;
    p->edge = pid == DS_EDGE_PID;
    p->location = number(real_get_property(device, CFSTR(kIOHIDLocationIDKey)));
    bool wired = bluetooth && pad_option("bluetooth=wired");

    // With pad_as=dualshock4 either pad is a USB DualShock 4 to the game, on a cable or over
    // Bluetooth shown as wired: for titles whose Sony code knows only that pad. Never a Bluetooth
    // bus type: Wine would then expect the DualShock 4's Bluetooth reports from it. It wins over
    // edge=dualsense.
    p->ds4 = (wired || usb) && pad_option("pad_as=dualshock4");
    if (bluetooth && !wired && pad_option("pad_as=dualshock4"))
        pad_log("pad_as=dualshock4 is not applied to the Bluetooth %s at location %08x: it needs a cable, or "
                "bluetooth=wired\n", p->edge ? "DualSense Edge" : "DualSense", p->location);
    // With edge=dualsense an Edge is the standard pad to the game, on a cable or over Bluetooth
    // shown as wired: its product id, name, descriptor and output size, as PR #90's bridge offered
    // for titles whose Sony library does not know the Edge.
    p->as_standard = !p->ds4 && p->edge && (wired || usb) && pad_option("edge=dualsense");
    p->model = p->ds4 ? (p->edge ? "DualSense Edge (shown as a DualShock 4)" : "DualSense (shown as a DualShock 4)")
             : p->as_standard ? "DualSense Edge (shown as a DualSense)" : p->edge ? "DualSense Edge" : "DualSense";
    if (wired) {
        uint32_t shown = p->ds4 ? DS4_PID : p->edge && !p->as_standard ? DS_EDGE_PID : DUALSENSE_PID;
        if ((p->bt = bt_pad_create(device, shown, p->location, p->edge))) p->bt->no_haptics = p->ds4;
    }
    // A pad shown as a DualShock 4 takes XInput's motors (xinput=rumble) from the game's own
    // settings only, as a game that reads its pad through Sony's code and rumbles through XInput
    // needs (Crysis 2 Remastered, 2026-10-22); never the pad itself as an XInput controller: the
    // game would read it twice. Every game's xinput=rumble would give each DualShock 4 game the
    // second collection, and the pad's id "&Col01", which Mortal Kombat 11 was measured without.
    p->xinput = p->ds4 ? (pad_game_option("xinput=rumble") ? XINPUT_RUMBLE : 0)
              : pad_option("xinput=rumble") ? XINPUT_RUMBLE : pad_option("xinput=pad") ? XINPUT_PAD : 0;
    p->descriptor = shown_descriptor(p);
    if (p->xinput) {
        // For hidclass.c: which product id carries xinput's collections, and where they are.
        uint16_t product = p->ds4 ? DS4_PID : p->edge && !p->as_standard ? DS_EDGE_PID : DUALSENSE_PID;
        for (unsigned i = 0; i < COUNT_OF(mgf_xinput_pads); i++)
            if (!mgf_xinput_pads[i].product || mgf_xinput_pads[i].product == product) {
                mgf_xinput_pads[i].mode = (uint8_t)p->xinput;
                mgf_xinput_pads[i].product = product;
                break;
            }
    }

    if (p->bt) pad_log("the Bluetooth %s at location %08x is shown as wired\n", p->model, p->location);
    if (p->ds4)
        pad_log("the %s at location %08x is shown to the game as a USB DualShock 4 (054C:%04X)\n", p->model,
                p->location, DS4_PID);
    if (p->ds4 && pad_option("xinput=pad"))
        pad_log("xinput=pad is not applied to the %s: a pad shown as a DualShock 4 takes XInput's rumble at most\n",
                p->model);
    else if (p->ds4 && !p->xinput && pad_option("xinput=rumble"))
        pad_log("every game's xinput=rumble is not applied to the %s: a pad shown as a DualShock 4 takes it only "
                "from the game's own settings\n", p->model);
    if (p->xinput == XINPUT_RUMBLE) pad_log("XInput's vibration goes to the %s's motors\n", p->model);
    if (p->xinput == XINPUT_PAD) pad_log("the %s is an XInput controller, its vibration on the motors\n", p->model);

    pthread_mutex_lock(&lock);
    p->next = pads;
    pads = p;
    pthread_mutex_unlock(&lock);
}

static IOHIDDeviceCallback winebus_matching, winebus_removal;
static void *winebus_matching_context, *winebus_removal_context;

static void matching(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)context;
    if (result == kIOReturnSuccess && !pad_of(device)) pad_found(device);
    winebus_matching(winebus_matching_context, result, sender, device);
}

static void removal(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)context;
    winebus_removal(winebus_removal_context, result, sender, device);
    // The record stays: winebus may still stop the device later, and finds it stopped.
}

static void register_matching(IOHIDManagerRef manager, IOHIDDeviceCallback callback, void *context) {
    winebus_matching = callback;
    winebus_matching_context = context;
    real_register_matching(manager, callback ? matching : NULL, NULL);
}

static void register_removal(IOHIDManagerRef manager, IOHIDDeviceCallback callback, void *context) {
    winebus_removal = callback;
    winebus_removal_context = context;
    real_register_removal(manager, callback ? removal : NULL, NULL);
}

// The pad's input, as the game is shown the pad: a Bluetooth pad's 0x31 is the wired 0x01 (the
// short report a pad sends before its calibration is read has no wired counterpart), and shown as
// a DualShock 4 the full report becomes that pad's, after the triggers have read it in the pad's
// own layout.
static void input(void *context, IOReturn result, void *sender, IOHIDReportType type, uint32_t id,
                  uint8_t *report, CFIndex length) {
    struct pad *p = context;
    uint8_t usb[64], ds4[DS4_INPUT_SIZE];

    if (p->bt && result == kIOReturnSuccess) {
        if (id == 0x01) return;
        if (id == 0x31 && length >= 66) {
            p->bt->input_at = mach_absolute_time();
            usb[0] = 0x01;
            memcpy(usb + 1, report + 2, 63);
            report = usb;
            length = sizeof(usb);
            id = 0x01;
        }
    }
    if (result == kIOReturnSuccess) pad_triggers_follow(p, report, (unsigned)length);
    if (p->ds4) {
        if (result != kIOReturnSuccess || length < 64 || report[0] != 0x01) return;
        ds4_input_from_dualsense(report, ds4, p->ds4_counter++);
        p->callback(p->context, result, sender, type, DS4_INPUT_ID, ds4, sizeof(ds4));
        return;
    }
    p->callback(p->context, result, sender, type, id, report, length);
}

static void register_input(IOHIDDeviceRef device, uint8_t *buffer, CFIndex length, IOHIDReportCallback callback,
                           void *context) {
    struct pad *p = pad_of(device);

    if (!p) {
        real_register_input(device, buffer, length, callback, context);
        return;
    }
    if (!callback) {
        pad_triggers_release(p);
        real_register_input(device, NULL, 0, NULL, NULL);
        if (p->bt) bt_pad_stop(p->bt);
        return;
    }
    // A DualSense takes the improved rumble emulation from firmware 2.24 on, and every Edge does.
    p->rumble_improved = p->edge || pad_firmware(device) >= 0x0224;
    if (p->bt) p->bt->rumble_improved = p->rumble_improved;
    // What the DualShock 4's feature reports 0x02, 0x12 and 0x81 are answered from, read once from
    // the pad itself: its calibration (0x05, 41 bytes) and its address (0x09, 20 bytes), each with
    // its id at byte 0.
    if (p->ds4) {
        p->ds4_calibration[0] = 0x05;
        p->ds4_calibration_length = 41;
        if (IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x05, p->ds4_calibration, &p->ds4_calibration_length) ||
            p->ds4_calibration[0] != 0x05)
            p->ds4_calibration_length = 0;
        p->ds4_pairing[0] = 0x09;
        p->ds4_pairing_length = 20;
        if (IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x09, p->ds4_pairing, &p->ds4_pairing_length) ||
            p->ds4_pairing[0] != 0x09)
            p->ds4_pairing_length = 0;
        pad_log("the %s's calibration %s and its address %s, for the DualShock 4's feature reports\n", p->model,
                p->ds4_calibration_length ? "read" : "not read (a DualShock 4's stands in)",
                p->ds4_pairing_length ? "read" : "not read (a fixed one stands in)");
    }
    p->callback = callback;
    p->context = context;
    if (p->bt) {
        // The Bluetooth report is larger than the wired one winebus made its buffer for.
        CFIndex size = number(real_get_property(device, CFSTR(kIOHIDMaxInputReportSizeKey)));
        if (size < 78) size = 78;
        if (!p->buffer) p->buffer = malloc(size);
        real_register_input(device, p->buffer, size, input, p);
        bt_pad_start(p->bt);
    } else real_register_input(device, buffer, length, input, p);
    pad_triggers(p);
}

// The rumble emulation, the improved kind. A pad emulates a rumble motor on its actuators either
// the old way (bit 0x01 of the first flag byte, byte 1) or the improved way of firmware 2.24 (bit
// 0x04 of the third, byte 39), the one a PS4 game's rumble gets on a PS5 and SDL 3 asks for. SDL
// 2, 2.32 included, compares an Edge's own firmware number with 0x0224 and asks it for the old way
// at half strength: Mortal Kombat 1, SDL 2.32, never wrote above 0x7f. A write in the old way is
// given the improved one; to an Edge the game is shown as an Edge, at twice what it wrote, up to
// 0xff. Sony's library writes the old way at full strength, and writes to an Edge only when it is
// shown as the standard pad, which keeps its strength; so does XInput's rumble (from_game false).
static uint8_t *rumble_improved(struct pad *p, uint8_t *report, unsigned length, uint8_t *copy, bool from_game) {
    if (!p->rumble_improved || length < 40 || !(report[1] & 0x01) || (report[39] & 0x04)) return report;
    if (report != copy) memcpy(copy, report, length);
    copy[1] = (copy[1] & ~0x01) | 0x02;
    copy[39] |= 0x04;
    if (from_game && p->edge && !p->as_standard && !p->ds4)
        for (unsigned i = 3; i <= 4; i++) copy[i] = copy[i] >= 0x80 ? 0xff : copy[i] * 2;
    return copy;
}

// How the game drives the pad, said once each, for MacGameFix's list of what each game does.
static void observe(struct pad *p, const uint8_t *report) {
    if (!p->told_motors && (report[1] & 0x03) && (report[3] || report[4])) {
        p->told_motors = true;
        pad_log("observed: the game rumbles the %s's motors\n", p->model);
    }
    if (!p->told_triggers && (((report[1] & 0x04) && report[11] && report[11] != 0x05) ||
                              ((report[1] & 0x08) && report[22] && report[22] != 0x05))) {
        p->told_triggers = true;
        pad_log("observed: the game sets trigger effects on the %s\n", p->model);
    }
    if (!p->told_power && (report[2] & 0x40)) {
        p->told_power = true;
        pad_log("observed: the game claims the %s's motor power (0x%02x)\n", p->model, report[37]);
    }
}

static IOReturn set_output(struct pad *p, CFIndex id, const uint8_t *data, CFIndex size) {
    uint8_t *report = (uint8_t *)data, copy[64], motors[64], translated[64];
    unsigned length = (unsigned)size;

    // A game that sees a DualShock 4 writes its output 0x05, the only one that pad declares: it
    // becomes the pad's own 0x02, and from here on goes as any 0x02 the game writes.
    if (p->ds4 && !(p->xinput && id == XINPUT_OUTPUT_ID)) {
        if (id != DS4_OUTPUT_ID || length < 2 || report[0] != DS4_OUTPUT_ID) return kIOReturnSuccess;
        if (ds4_output_to_dualsense(report, length, translated, p->edge ? 64 : 48, &p->ds4_output) && !p->told_ds4_blink) {
            p->told_ds4_blink = true;
            pad_log("observed: the game blinks the %s's light bar (on %u, off %u, in 10 ms); a DualSense cannot, "
                    "so it stays lit\n", p->model, length > 10 ? report[9] : 0, length > 10 ? report[10] : 0);
        }
        if (!p->told_ds4_output) {
            p->told_ds4_output = true;
            pad_log("observed: the game writes to the %s as a DualShock 4 (output 0x05, flags 0x%02x)\n", p->model, report[1]);
        }
        report = translated;
        length = p->edge ? 64 : 48;
    }
    // What xinput writes to the collection added for it: the rumble and the buzz intensity, 16
    // bits each, which become the pad's output report 0x02 with only the motors valid. The heavy
    // motor is byte 4, the light one byte 3.
    if (p->xinput && id == XINPUT_OUTPUT_ID && length >= 5 && report[0] == XINPUT_OUTPUT_ID) {
        unsigned rumble = report[1] | (report[2] << 8), buzz = report[3] | (report[4] << 8);

        if (!p->told_xinput && (rumble || buzz)) {
            p->told_xinput = true;
            pad_log("observed: the game rumbles the %s through XInput\n", p->model);
        }
        memset(motors, 0, sizeof(motors));
        motors[0] = 0x02;
        motors[1] = 0x03;
        motors[3] = buzz >> 8;
        motors[4] = rumble >> 8;
        // Shown as a DualShock 4, the game's own 0x05 resends the motors it last set with every
        // light bar write: they are XInput's from now on, so the two do not undo each other.
        if (p->ds4) {
            p->ds4_output.motors[0] = motors[3];
            p->ds4_output.motors[1] = motors[4];
            p->ds4_output.motors_set = 1;
        }
        report = motors;
        length = p->edge && !p->as_standard ? 64 : 48;
    }
    bool output = length >= 48 && report[0] == 0x02 && (id == 0x02 || report == motors || report == translated);
    bool from_game = report != motors;

    if (output) observe(p, report);
    if (output && length <= sizeof(copy)) {
        // An Edge shown as the standard pad on a cable: the game writes the standard pad's 48
        // bytes, the Edge takes 64.
        if (p->as_standard && !p->bt && length < sizeof(copy)) {
            memset(copy, 0, sizeof(copy));
            memcpy(copy, report, length);
            report = copy;
            length = sizeof(copy);
        }
        report = rumble_improved(p, report, length, copy, from_game);
        // The motor power (bit 0x40 of the second flag byte, byte 37) lowers the haptics and the
        // rumble, and the pad keeps it until something else is written. Sony's library claims it
        // at 0x00 in every report for a standard DualSense and never for an Edge, which then stays
        // at its own stored reduction. With motor_power=full an Edge gets the standard pad's 0x00
        // in every report (over Bluetooth, the writer claims it in every report it sends), and a
        // lower value a game writes is replaced. A pad shown as a DualShock 4 gets it too: the
        // game's output 0x05 has no motor power, so nothing else would claim it on a cable.
        if (pad_option("motor_power=full") && (p->edge || p->ds4 || (report[2] & 0x40))) {
            if (report != copy) memcpy(copy, report, length);
            if ((p->edge || p->ds4) && !p->bt) copy[2] |= 0x40;
            copy[37] = 0;
            report = copy;
        }
        report = pad_triggers_merge(p, report, length, copy, from_game);
    }
    if (p->bt && output) {
        bt_queue_output(p->bt, report);
        return kIOReturnSuccess;
    }
    return real_set_report(p->device, kIOHIDReportTypeOutput, output ? 0x02 : id, report, length);
}

static IOReturn set_report(IOHIDDeviceRef device, IOHIDReportType type, CFIndex id, const uint8_t *report, CFIndex length) {
    struct pad *p = pad_of(device);

    if (!p) return real_set_report(device, type, id, report, length);
    if (type == kIOHIDReportTypeOutput) return set_output(p, id, report, length);
    if (type == kIOHIDReportTypeFeature) {
        // What a game sets in a DualShock 4 is acknowledged and kept from the pad, whose same ids
        // mean other things: 0x08 is where a DualSense's radio is turned off.
        if (p->ds4 && !(p->xinput && id == XINPUT_FEATURE_ID_DS4)) return kIOReturnSuccess;
        // The collection added for xinput keeps nothing.
        if (p->xinput && id == (p->ds4 ? XINPUT_FEATURE_ID_DS4 : XINPUT_FEATURE_ID)) return kIOReturnSuccess;
        // A wired client turns the pad's radio off once it has the pad on the cable (feature 0x08,
        // subcommand 2). Here the radio is the cable.
        if (p->bt && id == 0x08 && length == 48 && report[0] == 0x08 && report[1] == 0x02) {
            CFIndex i = 2;
            while (i < 48 && !report[i]) i++;
            if (i == 48) return kIOReturnSuccess;
        }
    }
    return real_set_report(device, type, id, report, length);
}

static IOReturn get_report(IOHIDDeviceRef device, IOHIDReportType type, CFIndex id, uint8_t *report, CFIndex *length) {
    struct pad *p = pad_of(device);

    if (!p || type != kIOHIDReportTypeFeature) return real_get_report(device, type, id, report, length);
    // A DualShock 4's feature reports are answered here, never by the pad: its ids mean other
    // things to a DualSense (see ds4_feature_reply).
    if (p->ds4 && !(p->xinput && id == XINPUT_FEATURE_ID_DS4)) {
        uint8_t reply[64];
        unsigned size = ds4_feature_reply((uint8_t)id, p->ds4_calibration, p->ds4_calibration_length, p->ds4_pairing,
                                          p->ds4_pairing_length, reply, sizeof(reply));
        if (!size || size > sizeof(reply)) return kIOReturnUnsupported;
        if (*length < (CFIndex)size) return kIOReturnNoSpace;
        memcpy(report, reply, size);
        *length = size;
        return kIOReturnSuccess;
    }
    // The waveforms of the collection added for xinput: rumble, then buzz, each with its duration
    // (0: until changed, as XInputSetState means it) and a cutoff of a second, as winebus answers
    // for its own pads.
    if (p->xinput && id == (p->ds4 ? XINPUT_FEATURE_ID_DS4 : XINPUT_FEATURE_ID)) {
        static const uint16_t waveforms[2] = {HID_USAGE_HAPTICS_WAVEFORM_RUMBLE, HID_USAGE_HAPTICS_WAVEFORM_BUZZ};
        if (*length < 17) return kIOReturnNoSpace;
        memset(report, 0, 17);
        report[0] = (uint8_t)id;
        for (unsigned i = 0; i < 2; i++) {
            uint8_t *entry = report + 1 + 8 * i;
            entry[0] = waveforms[i] & 0xff;
            entry[1] = waveforms[i] >> 8;
            entry[4] = 1000 & 0xff;
            entry[5] = 1000 >> 8;
        }
        *length = 17;
        return kIOReturnSuccess;
    }
    return real_get_report(device, type, id, report, length);
}

// Each import winebus.so has of these, and what takes its place.
struct hook {
    const char *name;
    void *replacement;
    void **real;
};

static const struct hook hooks[] = {
    {"IOHIDDeviceGetProperty", get_property, (void **)&real_get_property},
    {"IOHIDDeviceSetReport", set_report, (void **)&real_set_report},
    {"IOHIDDeviceGetReport", get_report, (void **)&real_get_report},
    {"IOHIDDeviceRegisterInputReportCallback", register_input, (void **)&real_register_input},
    {"IOHIDManagerRegisterDeviceMatchingCallback", register_matching, (void **)&real_register_matching},
    {"IOHIDManagerRegisterDeviceRemovalCallback", register_removal, (void **)&real_register_removal},
    {"IOHIDDeviceGetService", get_service, (void **)&real_get_service},
    {"IORegistryEntryGetParentEntry", parent, (void **)&real_parent},
    {"IOObjectConformsTo", conforms, (void **)&real_conforms},
    {"IORegistryEntryCreateCFProperty", create_property, (void **)&real_create_property},
    {"IOObjectRelease", release, (void **)&real_release},
};

void mgf_controls_bus_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide) {
    enum { COUNT = COUNT_OF(hooks) };
    uintptr_t fns[COUNT], *slots[COUNT];

    // All of them or none: a Bluetooth pad that is USB to some of winebus's calls and Bluetooth
    // to others would lose its bus type, and the game the pad.
    for (unsigned i = 0; i < COUNT; i++) {
        int n = -1;
        fns[i] = (uintptr_t)dlsym(RTLD_DEFAULT, hooks[i].name);
        slots[i] = NULL;
        if (!fns[i] || (n = api->count_pointers(mh, slide, fns[i], &slots[i])) != 1) {
            pad_log("controls: winebus.so's %s cannot be taken (%d pointers to it), so none is\n", hooks[i].name, n);
            return;
        }
        *hooks[i].real = (void *)fns[i];
    }
    for (unsigned i = 0; i < COUNT; i++)
        if (!api->swap_pointer(slots[i], fns[i], (uintptr_t)hooks[i].replacement)) {
            pad_log("controls: winebus.so's %s could not be written, %u of %u taken\n", hooks[i].name, i, (unsigned)COUNT);
            return;
        }
    pad_log("controls: winebus.so's %u IOKit calls taken\n", (unsigned)COUNT);
}
