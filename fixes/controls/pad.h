// What the controls library's parts share: pad.log, Game Feel's settings, the game it runs for,
// the clock and the real-time thread. The same as engine/patches' include/wine/mgf_pad.h, which
// winebus.so and winecoreaudio.so share when they are built with the patches, without Wine's types.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_PAD_H
#define MGF_CONTROLS_PAD_H

#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>

#define SONY_VID       0x054c
#define DUALSENSE_PID  0x0ce6
#define DS_EDGE_PID    0x0df2

// A Bluetooth pad's socket, in pad_dir: pad-<location>-<product shown to the game>-<product it is>.sock.
// The winebus part binds it; the winecoreaudio part finds the pad by it and sends it the haptics.
#define PAD_SOCKET      "pad-%08x-%04x-%04x.sock"
#define PAD_SOCKET_SCAN "pad-%8x-%4x-%4x.sock"

// Haptics at the pad's 3 kHz, signed 8-bit, channels 3 and 4 interleaved.
struct pad_packet {
    char magic[4];  // "MGFH"
    signed char samples[2 * 256];
};

void pad_dir(char *dir, size_t size);
void pad_game(char *id, size_t size);
void pad_log(const char *format, ...) __attribute__((format(printf, 1, 2)));
bool pad_conf(const char *game, int pass, char *path, size_t size);
const char *pad_value(const char *key);
bool pad_option(const char *option);
bool pad_game_option(const char *option);
void pad_reload(void);
long long pad_settings_stamp(void);
float pad_number(const char *s);
uint64_t pad_ticks(double seconds);
double pad_seconds(uint64_t ticks);
void pad_realtime(double period, double constraint);

// Whether MGF_CONTROLS_WITHOUT names this part of the Windows side.
bool pad_part_off(const char *part);

#endif
