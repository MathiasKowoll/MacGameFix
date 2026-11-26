// The Bluetooth DualSense shown as wired: its writer, and the wired pads' descriptors (bt.c).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_BT_H
#define MGF_CONTROLS_BT_H

#include <IOKit/hid/IOHIDLib.h>
#include "pad.h"

struct bt_pad
{
    IOHIDDeviceRef device;
    bool edge;           /* shown to the game as an Edge */
    bool physical_edge;  /* an Edge, however it is shown */
    bool no_haptics;     /* shown as a pad that has none, a DualShock 4: see bt_pad_start */
    uint32_t location;
    pthread_t writer, receiver;
    pthread_mutex_t lock;
    semaphore_t wake;
    bool running, quit, dirty;
    uint8_t pending[47];  /* bytes 1-47 of the game's USB output report 0x02, merged */
    uint8_t motors[2];    /* the game's last rumble values, right and left */
    uint8_t seq;
    int sock;
    char path[104];
    signed char fifo[256][2];  /* haptics at 3 kHz, channels 3 and 4: BT_QUEUE_LIMIT fits */
    unsigned int fifo_head, fifo_count;
    uint64_t input_at, audio_at, nonzero_at;
    bool synth;                /* rumble=haptics: see bt_synth */
    bool rumble_improved;      /* the rumble with the improved emulation: see pad_rumble_improved */
    float synth_gain;          /* its strength: the haptics' over Bluetooth for this pad */
    double synth_phase[2];
    float synth_level[2];
    uint64_t synth_at;
    uint8_t control_last[78];     /* the last report 0x31 written, to skip its copies */
    bool control_known;
};

extern const uint8_t ds_usb_descriptor[], ds_edge_usb_descriptor[];
extern const size_t ds_usb_descriptor_size, ds_edge_usb_descriptor_size;

struct bt_pad *bt_pad_create(IOHIDDeviceRef device, uint32_t pid, uint32_t location, bool physical_edge);
void bt_pad_start(struct bt_pad *pad);
void bt_pad_stop(struct bt_pad *pad);
void bt_queue_output(struct bt_pad *pad, const uint8_t *usb);

#endif
