// What the winebus part knows of each DualSense or Edge winebus opens (bus.c, triggers.c).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_CONTROLS_H
#define MGF_CONTROLS_CONTROLS_H

#include "bt.h"
#include "pad.h"
#include "dualshock4.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))


struct pad {
    struct pad *next;
    IOHIDDeviceRef device;
    struct bt_pad *bt;     // over Bluetooth, shown as wired
    bool edge;             // a DualSense Edge, however it is shown
    bool as_standard;      // an Edge shown as the standard pad (edge=dualsense)
    bool ds4;              // either pad shown as a DualShock 4 (pad_as=dualshock4): see dualshock4.h
    int xinput;            // XINPUT_RUMBLE or XINPUT_PAD
    bool rumble_improved;  // the pad takes the improved rumble emulation
    unsigned location;
    const char *model;
    CFDataRef descriptor;  // the descriptor the game is shown, when it is not the pad's own
    IOHIDReportCallback callback;  // winebus's input callback, and what it is given
    void *context;
    uint8_t *buffer;
    bool told_motors, told_triggers, told_power, told_xinput, told_ds4_output, told_ds4_blink;
    // pad_as=dualshock4: the DualShock 4's report counter, the motors it keeps, and the pad's own
    // calibration (feature 0x05) and address (0x09), read once, that its feature reports are
    // answered from
    uint8_t ds4_counter;
    struct ds4_output_state ds4_output;
    uint8_t ds4_calibration[64], ds4_pairing[64];
    CFIndex ds4_calibration_length, ds4_pairing_length;
    // the chosen trigger effects: R2, L2 (triggers.c)
    uint8_t trigger_kind[2], trigger_strength[2], trigger_step[2];
    uint8_t trigger_kind2[2], trigger_strength2[2];  // while the other is pressed
    bool trigger_game[2], trigger_held[2], trigger_pressed[2];
    bool trigger_replace[2];    // the chosen effect takes the place of the game's, on its timing
    bool trigger_following[2];  // the game has set its own effect on a side that replaces it
    bool trigger_game_on[2];    // and that effect of the game's is on now
    uint64_t settings_checked;  // when Game Feel's files were last looked at
    long long settings_stamp;   // their modification times then
    uint64_t trigger_at[2];
};

void pad_triggers(struct pad *p);
void pad_triggers_follow(struct pad *p, const uint8_t *input, unsigned length);
uint8_t *pad_triggers_merge(struct pad *p, uint8_t *report, unsigned length, uint8_t copy[64], bool from_game);
void pad_triggers_release(struct pad *p);

#endif
