/*
 * MacGameFix: a DualSense or DualSense Edge shown to a game as a USB DualShock 4
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 *
 * The DualShock 4's report descriptor and its canned feature reports 0x02,
 * 0x12 and 0xa3 below are ViGEmBus's (sys/Ds4Pdo.cpp), which carries this
 * notice:
 *
 *   Virtual Gamepad Emulation Framework - Windows kernel-mode bus driver
 *
 *   BSD 3-Clause License
 *
 *   Copyright (c) 2018-2022, Nefarius Software Solutions e.U. and Contributors
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions are met:
 *
 *   1. Redistributions of source code must retain the above copyright notice, this
 *      list of conditions and the following disclaimer.
 *
 *   2. Redistributions in binary form must reproduce the above copyright notice,
 *      this list of conditions and the following disclaimer in the documentation
 *      and/or other materials provided with the distribution.
 *
 *   3. Neither the name of the copyright holder nor the names of its
 *      contributors may be used to endorse or promote products derived from
 *      this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 *   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *   DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 *   FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 *   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 *   CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 *   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* Some games' Sony code knows only the DualShock 4: Mortal Kombat 11's 2017
 * libScePad opens a USB DualShock 4 (054C:05C4 or 09CC) and nothing else, and
 * that is where the game sends its rumble. With pad_as=dualshock4 a DualSense
 * or an Edge is shown to such a game as a USB DualShock 4, and its reports are
 * translated both ways here: the pad's input 0x01 becomes the DualShock 4's
 * 0x01, the game's output 0x05 becomes the pad's 0x02, and the DualShock 4's
 * feature reports are answered from what the pad says of itself.
 *
 * The layouts are Linux's, drivers/hid/hid-playstation.c (struct
 * dualsense_input_report, dualsense_output_report_common,
 * dualshock4_input_report_common, dualshock4_input_report_usb,
 * dualshock4_touch_report and dualshock4_output_report_common, and the
 * DS_* and DS4_* report ids and sizes). Byte offsets below count the report
 * id as byte 0.
 *
 * Plain C, with no Wine types, so that a host test can compile it alone
 * (engine/tests/dualshock4 takes it out of patch 0013). */

#ifndef __MACGAMEFIX_DUALSHOCK4_H
#define __MACGAMEFIX_DUALSHOCK4_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define DS4_PID            0x05c4  /* DualShock 4 [CUH-ZCT1x]: every title whose code was read accepts it */
#define DS4_INPUT_ID       0x01
#define DS4_INPUT_SIZE     64
#define DS4_OUTPUT_ID      0x05
#define DS4_OUTPUT_SIZE    32
#define DS4_TOUCHPAD_HEIGHT 942    /* the DualSense's is 1080; both are 1920 wide */
#define DS_TOUCHPAD_HEIGHT  1080

/* What ds4_output_to_dualsense found in the game's report that a DualSense
 * cannot do. */
#define DS4_OUTPUT_BLINK   0x01

/* ViGEmBus's DualShock 4 descriptor, 467 bytes, the one its virtual 054C:05C4
 * hands Windows: input 0x01 of 64 bytes (X, Y, Z, Rz sticks, a hat, 14
 * buttons, a 6-bit counter, Rx and Ry triggers and 54 vendor bytes), output
 * 0x05 of 32 and the DualShock 4's feature reports. It has what Mortal Kombat
 * 11's libScePad checks a descriptor for, as read from its code: input 64
 * bytes, feature 0xa3 of 49, no Bluetooth feature 0x06, an unsigned X axis. */
static const uint8_t ds4_usb_descriptor[] =
{
    0x05, 0x01, 0x09, 0x05, 0xa1, 0x01, 0x85, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xff, 0x00, 0x75, 0x08, 0x95,
    0x04, 0x81, 0x02, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46,
    0x3b, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42, 0x65, 0x00,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0e, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01,
    0x95, 0x0e, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x20, 0x75, 0x06, 0x95,
    0x01, 0x15, 0x00, 0x25, 0x7f, 0x81, 0x02, 0x05, 0x01, 0x09, 0x33, 0x09,
    0x34, 0x15, 0x00, 0x26, 0xff, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
    0x06, 0x00, 0xff, 0x09, 0x21, 0x95, 0x36, 0x81, 0x02, 0x85, 0x05, 0x09,
    0x22, 0x95, 0x1f, 0x91, 0x02, 0x85, 0x04, 0x09, 0x23, 0x95, 0x24, 0xb1,
    0x02, 0x85, 0x02, 0x09, 0x24, 0x95, 0x24, 0xb1, 0x02, 0x85, 0x08, 0x09,
    0x25, 0x95, 0x03, 0xb1, 0x02, 0x85, 0x10, 0x09, 0x26, 0x95, 0x04, 0xb1,
    0x02, 0x85, 0x11, 0x09, 0x27, 0x95, 0x02, 0xb1, 0x02, 0x85, 0x12, 0x06,
    0x02, 0xff, 0x09, 0x21, 0x95, 0x0f, 0xb1, 0x02, 0x85, 0x13, 0x09, 0x22,
    0x95, 0x16, 0xb1, 0x02, 0x85, 0x14, 0x06, 0x05, 0xff, 0x09, 0x20, 0x95,
    0x10, 0xb1, 0x02, 0x85, 0x15, 0x09, 0x21, 0x95, 0x2c, 0xb1, 0x02, 0x06,
    0x80, 0xff, 0x85, 0x80, 0x09, 0x20, 0x95, 0x06, 0xb1, 0x02, 0x85, 0x81,
    0x09, 0x21, 0x95, 0x06, 0xb1, 0x02, 0x85, 0x82, 0x09, 0x22, 0x95, 0x05,
    0xb1, 0x02, 0x85, 0x83, 0x09, 0x23, 0x95, 0x01, 0xb1, 0x02, 0x85, 0x84,
    0x09, 0x24, 0x95, 0x04, 0xb1, 0x02, 0x85, 0x85, 0x09, 0x25, 0x95, 0x06,
    0xb1, 0x02, 0x85, 0x86, 0x09, 0x26, 0x95, 0x06, 0xb1, 0x02, 0x85, 0x87,
    0x09, 0x27, 0x95, 0x23, 0xb1, 0x02, 0x85, 0x88, 0x09, 0x28, 0x95, 0x22,
    0xb1, 0x02, 0x85, 0x89, 0x09, 0x29, 0x95, 0x02, 0xb1, 0x02, 0x85, 0x90,
    0x09, 0x30, 0x95, 0x05, 0xb1, 0x02, 0x85, 0x91, 0x09, 0x31, 0x95, 0x03,
    0xb1, 0x02, 0x85, 0x92, 0x09, 0x32, 0x95, 0x03, 0xb1, 0x02, 0x85, 0x93,
    0x09, 0x33, 0x95, 0x0c, 0xb1, 0x02, 0x85, 0xa0, 0x09, 0x40, 0x95, 0x06,
    0xb1, 0x02, 0x85, 0xa1, 0x09, 0x41, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xa2,
    0x09, 0x42, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xa3, 0x09, 0x43, 0x95, 0x30,
    0xb1, 0x02, 0x85, 0xa4, 0x09, 0x44, 0x95, 0x0d, 0xb1, 0x02, 0x85, 0xa5,
    0x09, 0x45, 0x95, 0x15, 0xb1, 0x02, 0x85, 0xa6, 0x09, 0x46, 0x95, 0x15,
    0xb1, 0x02, 0x85, 0xf0, 0x09, 0x47, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf1,
    0x09, 0x48, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf2, 0x09, 0x49, 0x95, 0x0f,
    0xb1, 0x02, 0x85, 0xa7, 0x09, 0x4a, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xa8,
    0x09, 0x4b, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xa9, 0x09, 0x4c, 0x95, 0x08,
    0xb1, 0x02, 0x85, 0xaa, 0x09, 0x4e, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xab,
    0x09, 0x4f, 0x95, 0x39, 0xb1, 0x02, 0x85, 0xac, 0x09, 0x50, 0x95, 0x39,
    0xb1, 0x02, 0x85, 0xad, 0x09, 0x51, 0x95, 0x0b, 0xb1, 0x02, 0x85, 0xae,
    0x09, 0x52, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xaf, 0x09, 0x53, 0x95, 0x02,
    0xb1, 0x02, 0x85, 0xb0, 0x09, 0x54, 0x95, 0x3f, 0xb1, 0x02, 0xc0,
};

/* ViGEmBus's feature report 0xa3, firmware information: built "Aug  3 2013"
 * at "07:01:12", hardware version 0x3100 (bytes 35 and 36, little-endian) and
 * firmware 0x0049 (bytes 41 and 42). Mortal Kombat 11's libScePad reads the
 * hardware version from bytes 35 and 36 and gives up on a pad under 0x3100
 * (a jb at 0x1800027bc). */
static const uint8_t ds4_firmware_info[49] =
{
    0xa3, 0x41, 0x75, 0x67, 0x20, 0x20, 0x33, 0x20,
    0x32, 0x30, 0x31, 0x33, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x30, 0x37, 0x3a, 0x30, 0x31, 0x3a, 0x31,
    0x32, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x31, 0x03, 0x00, 0x00,
    0x00, 0x49, 0x00, 0x05, 0x00, 0x00, 0x80, 0x03,
    0x00,
};

/* ViGEmBus's feature report 0x02, a DualShock 4's motion calibration, for when
 * the pad's own cannot be read. */
static const uint8_t ds4_canned_calibration[37] =
{
    0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x87,
    0x22, 0x7b, 0xdd, 0xb2, 0x22, 0x47, 0xdd, 0xbd,
    0x22, 0x43, 0xdd, 0x1c, 0x02, 0x1c, 0x02, 0x7f,
    0x1e, 0x2e, 0xdf, 0x60, 0x1f, 0x4c, 0xe0, 0x3a,
    0x1d, 0xc6, 0xde, 0x08, 0x00,
};

/* ViGEmBus's feature report 0x12 before it puts its own addresses in: the
 * pad's address at bytes 1-6, then 0x08 0x25 0x00, then the host's at 10-15. */
static const uint8_t ds4_canned_pairing[16] =
{
    0x12, 0x8b, 0x09, 0x07, 0x6d, 0x66, 0x1c, 0x08,
    0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

/* The length of report `id` of one kind (main item tag 0x80 input, 0x90 output
 * or 0xb0 feature) in a descriptor with report ids, id byte included; 0 when
 * the descriptor declares no such report. Push and pop are not followed: the
 * descriptor here has none. */
static inline unsigned int ds4_report_length(const uint8_t *desc, size_t size, uint8_t kind, uint8_t id)
{
    unsigned int bits = 0, report_size = 0, report_count = 0, value, n;
    int current = -1, found = 0;
    size_t i = 0;

    while (i < size)
    {
        uint8_t prefix = desc[i];

        if (prefix == 0xfe)  /* a long item: its data size is the next byte */
        {
            if (i + 1 >= size) break;
            i += 3 + desc[i + 1];
            continue;
        }
        n = (prefix & 3) == 3 ? 4 : (prefix & 3);
        if (i + 1 + n > size) break;
        value = 0;
        while (n--) value |= (unsigned int)desc[i + 1 + n] << (8 * n);
        switch (prefix & 0xfc)
        {
        case 0x74: report_size = value; break;
        case 0x94: report_count = value; break;
        case 0x84: current = (int)value; break;
        case 0x80: case 0x90: case 0xb0:
            if ((prefix & 0xfc) == kind && current == id)
            {
                bits += report_size * report_count;
                found = 1;
            }
            break;
        }
        i += 1 + ((prefix & 3) == 3 ? 4 : (prefix & 3));
    }
    return found ? 1 + (bits + 7) / 8 : 0;
}

/* The pad's input report 0x01 (64 bytes: on a cable as it comes, over
 * Bluetooth as patch 0004 makes it of 0x31) as a DualShock 4's 0x01 (64).
 * `counter` counts the reports; its low 6 bits are the DualShock 4's own
 * counter, under the PS and touchpad buttons.
 *
 *   DualSense                         DualShock 4
 *   1-4 LX LY RX RY                   1-4 the same
 *   5, 6 L2, R2 (analog)              8, 9
 *   8 hat and face buttons            5, the same bits
 *   9 L1 R1 L2 R2 Create Options L3 R3   6, the same bits (Create is Share)
 *   10 bit 0 PS, bit 1 touchpad       7, with the counter in bits 2-7; mute and
 *                                     the Edge's Fn and back buttons have nowhere to go
 *   16-21 gyro, 22-27 accelerometer   13-18, 19-24, the raw values unscaled
 *   28-31 timestamp, le32, 1/3 us     10-11, le16, 16/3 us: divided by 16
 *   32 (SDL: temperature)             12, sensor temperature
 *   33-36, 37-40 two touch points     33 one touch report, 34 its stamp, 35-42 the
 *                                     points, Y scaled from 1080 to 942
 *   53 battery level, charge state    30 level, bit 4 the cable
 *
 * The gyro and accelerometer values are copied as the sensors give them, not
 * rescaled. A reader turns them into degrees a second and g with the pad's
 * calibration, and the DualShock 4's feature report 0x02 carries the
 * DualSense's own 0x05 (see ds4_feature_reply), which Linux parses at the same
 * offsets for both pads (dualshock4_get_calibration_data,
 * dualsense_get_calibration_data). When that read failed, ViGEmBus's
 * DualShock 4 calibration stands in, and the raw DualSense values are read
 * with it.
 */
static inline void ds4_input_from_dualsense(const uint8_t ds[64], uint8_t ds4[64], uint8_t counter)
{
    uint8_t level = ds[53] & 0x0f, charge = ds[53] >> 4;
    uint32_t stamp;
    unsigned int i, y;

    memset(ds4, 0, DS4_INPUT_SIZE);
    ds4[0] = DS4_INPUT_ID;
    memcpy(ds4 + 1, ds + 1, 4);
    ds4[5] = ds[8];
    ds4[6] = ds[9];
    ds4[7] = (ds[10] & 0x03) | (uint8_t)((counter & 0x3f) << 2);
    ds4[8] = ds[5];
    ds4[9] = ds[6];
    stamp = (ds[28] | (ds[29] << 8) | (ds[30] << 16) | ((uint32_t)ds[31] << 24)) / 16;
    ds4[10] = stamp & 0xff;
    ds4[11] = (stamp >> 8) & 0xff;
    ds4[12] = ds[32];
    memcpy(ds4 + 13, ds + 16, 12);

    /* The DualSense's charge state (hid-playstation.c, dualsense_parse_report):
     * 0 on battery, 1 charging, 2 full, 0xa and 0xb a voltage or temperature
     * error, 0xf a charge error. The DualShock 4's (dualshock4_parse_report):
     * the level 0-10 alone on battery; with the cable bit, 0-10 charging, 11
     * full, 14 not charging for voltage or temperature, 15 a charge error. */
    if (level > 10) level = 10;
    switch (charge)
    {
    case 0x0: ds4[30] = level; break;
    case 0x1: ds4[30] = 0x10 | level; break;
    case 0x2: ds4[30] = 0x10 | 11; break;
    case 0xa:
    case 0xb: ds4[30] = 0x10 | 14; break;
    default:  ds4[30] = 0x10 | 15; break;
    }
    /* Byte 31 stays 0: its bit 2 says a wireless adapter lost its pad, and SDL
     * drops a report that has it. */

    ds4[33] = 1;
    ds4[34] = counter;
    for (i = 0; i < 2; i++)
    {
        const uint8_t *from = ds + 33 + 4 * i;
        uint8_t *to = ds4 + 35 + 4 * i;

        y = ((from[2] >> 4) | (from[3] << 4)) * DS4_TOUCHPAD_HEIGHT / DS_TOUCHPAD_HEIGHT;
        to[0] = from[0];  /* the contact: bit 7 set when the finger is up, on both pads */
        to[1] = from[1];
        to[2] = (from[2] & 0x0f) | (uint8_t)((y & 0x0f) << 4);
        to[3] = (uint8_t)(y >> 4);
    }
    /* The two touch reports not sent, their contacts up, as ViGEmBus's own
     * empty report has them. */
    ds4[44] = ds4[48] = ds4[53] = ds4[57] = 0x80;
}

/* What the game last set that a DualShock 4 keeps until it is set again. */
struct ds4_output_state
{
    uint8_t motors[2];  /* right (the light one), left (the heavy one) */
    int motors_set;
};

/* The game's output report 0x05 (32 bytes) as the pad's 0x02, `ds_length`
 * bytes (48 for a DualSense, 64 for an Edge).
 *
 *   DualShock 4                       DualSense
 *   1 flag0: 0x01 motors              1 flag0 0x01|0x02, as a pad that rumbles the
 *                                     old way (patch 0006 gives it the improved one
 *                                     where the pad takes it)
 *   4, 5 right (light), left (heavy)  3, 4
 *   1 flag0: 0x02 light bar           2 flag1 0x04
 *   6-8 red, green, blue              45-47
 *   1 flag0: 0x04 blink, 9-10 times   nothing: a DualSense has no blink
 *
 * A DualShock 4 keeps its motors when a report sets only the light bar, while
 * a DualSense report without a rumble bit ends the rumble; so once the game
 * has set the motors every report carries them, as the DualShock 4 would still
 * be running them. Returns DS4_OUTPUT_BLINK when the game asked for a blink
 * with a time that is not 0. */
static inline unsigned int ds4_output_to_dualsense(const uint8_t *ds4, size_t length, uint8_t *ds, size_t ds_length,
                                                   struct ds4_output_state *state)
{
    uint8_t flags = length > 1 ? ds4[1] : 0;

    memset(ds, 0, ds_length);
    ds[0] = 0x02;
    if ((flags & 0x01) && length > 5)
    {
        state->motors[0] = ds4[4];
        state->motors[1] = ds4[5];
        state->motors_set = 1;
    }
    if (state->motors_set)
    {
        ds[1] |= 0x03;
        ds[3] = state->motors[0];
        ds[4] = state->motors[1];
    }
    if ((flags & 0x02) && length > 8 && ds_length > 47)
    {
        ds[2] |= 0x04;
        ds[45] = ds4[6];
        ds[46] = ds4[7];
        ds[47] = ds4[8];
    }
    /* Blink times of 0 and 0 are a steady light on a DualShock 4: Linux writes
     * them to stop the blinking (hid-playstation.c, dualshock4_led_set_brightness)
     * and SDL sets flag 0x04 for every pad it does not know as Sony's. */
    return ((flags & 0x04) && length > 10 && (ds4[9] || ds4[10])) ? DS4_OUTPUT_BLINK : 0;
}

/* The DualShock 4's feature report `id`, answered from what the pad says of
 * itself: `calibration` is the pad's feature report 0x05 and `pairing` its
 * 0x09, each as read (id at byte 0), or NULL. Returns the report's length as
 * the descriptor declares it, and writes it to `out` when `size` holds it; 0
 * for an id the descriptor does not declare.
 *
 *   0x02 calibration (37 bytes): bytes 1-34 are the DualSense's 0x05 bytes
 *        1-34, which Linux parses in the same order for both (gyro biases,
 *        pitch, yaw and roll plus and minus, speed plus and minus, accelerometer
 *        x, y, z plus and minus, little-endian 16 bits each)
 *   0x12 pairing (16 bytes): the pad's address at bytes 1-6, little-endian as
 *        in the DualSense's 0x09, then ViGEmBus's 0x08 0x25 0x00; the host's
 *        address at 10-15 is left 0
 *   0x81 (7 bytes): the pad's address again, at bytes 1-6
 *   0xa3 firmware information (49 bytes): ViGEmBus's
 *   any other declared id: zeros after the id */
static inline unsigned int ds4_feature_reply(uint8_t id, const uint8_t *calibration, size_t calibration_length,
                                             const uint8_t *pairing, size_t pairing_length, uint8_t *out, size_t size)
{
    static const uint8_t none[6];
    unsigned int length = ds4_report_length(ds4_usb_descriptor, sizeof(ds4_usb_descriptor), 0xb0, id);
    const uint8_t *address = ds4_canned_pairing + 1;

    if (!length || size < length) return length;
    /* An address of zeros is no address: SDL gives up on such a pad. */
    if (pairing && pairing_length >= 7 && pairing[0] == 0x09 && memcmp(pairing + 1, none, 6)) address = pairing + 1;
    memset(out, 0, length);
    out[0] = id;
    switch (id)
    {
    case 0x02:
        /* The last two bytes, which neither Linux nor SDL reads, are ViGEmBus's. */
        memcpy(out, ds4_canned_calibration, length);
        if (calibration && calibration_length >= 35 && calibration[0] == 0x05) memcpy(out + 1, calibration + 1, 34);
        break;
    case 0x12:
        memcpy(out, ds4_canned_pairing, 10);
        memcpy(out + 1, address, 6);
        break;
    case 0x81:
        memcpy(out + 1, address, 6);
        break;
    case 0xa3:
        memcpy(out, ds4_firmware_info, length);
        break;
    }
    return length;
}

#endif /* __MACGAMEFIX_DUALSHOCK4_H */
