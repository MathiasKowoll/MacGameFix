// A Sony pad's own HID layout, turned into the one Wine's xinput reads. What engine patch 0008
// teaches the Wine modules' xinput; xinput.c applies it to what CodeWeavers' xinput asks of
// hid.dll. Kept apart so that build-controls.sh can test it on its own (checks/xinput_map.c).
//
// Wine's xinput reads the layout Wine's own winexinput driver makes:
//   axes      X, Y the left stick; Rx, Ry the right stick; Z, Rz the triggers; a Y grows upwards
//   buttons   1 A, 2 B, 3 X, 4 Y, 5 LB, 6 RB, 7 Back, 8 Start, 9 L3, 10 R3; Guide is any usage
//             on the vendor page
//   hat       1..8 clockwise from up, 0 for centred
// A DualSense's own descriptor (and a DualShock 4's) has:
//   axes      X, Y the left stick; Z, Rz the right stick; Rx, Ry the triggers; a Y grows downwards
//   buttons   1 Square, 2 Cross, 3 Circle, 4 Triangle, 5 L1, 6 R1, 7 L2, 8 R2, 9 Create,
//             10 Options, 11 L3, 12 R3, 13 PS, 14 touchpad, 15 mute; its vendor page is other data
//   hat       0..7 clockwise from up, 8 for centred
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_XINPUT_MAP_H
#define MGF_CONTROLS_XINPUT_MAP_H

#include <stdint.h>

#define HID_USAGE_X 0x30
#define HID_USAGE_Y 0x31
#define HID_USAGE_Z 0x32
#define HID_USAGE_RX 0x33
#define HID_USAGE_RY 0x34
#define HID_USAGE_RZ 0x35
#define HID_USAGE_HAT 0x39
#define SONY_BUTTON_PS 13

// The axis a Sony pad has where Wine's layout has `usage`, and the other way: Z and Rx change
// places, and Rz and Ry.
static inline uint16_t sony_axis(uint16_t usage) {
    switch (usage) {
    case HID_USAGE_Z: return HID_USAGE_RX;
    case HID_USAGE_RX: return HID_USAGE_Z;
    case HID_USAGE_RZ: return HID_USAGE_RY;
    case HID_USAGE_RY: return HID_USAGE_RZ;
    default: return usage;
    }
}

// Whether the axis Wine's layout calls `usage` is a stick's Y, which a Sony pad counts downwards.
static inline int sony_axis_turned(uint16_t usage) { return usage == HID_USAGE_Y || usage == HID_USAGE_RY; }

// A value counted the other way within its range.
static inline uint32_t sony_turned(uint32_t value, int32_t min, int32_t max) {
    return (int32_t)value < min || (int32_t)value > max ? value : (uint32_t)(min + max - (int32_t)value);
}

// The button Wine's layout has for a Sony pad's; 0 for one xinput has no button for (L2 and R2,
// which it reads as axes; PS, which is its Guide; the touchpad; mute).
static inline uint16_t sony_button(uint16_t button) {
    static const uint8_t wine[13] = {0, 3, 1, 2, 4, 5, 6, 0, 0, 7, 8, 9, 10};
    return button < 13 ? wine[button] : 0;
}

// The hat as Wine's layout counts it: from its own minimum, and centred outside its range.
static inline uint32_t sony_hat(uint32_t value, int32_t min, int32_t max) {
    return max > min && (int32_t)value >= min && (int32_t)value <= max ? value - (uint32_t)min + 1 : 0;
}

#endif
