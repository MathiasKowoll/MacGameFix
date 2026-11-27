// A DualSense or DualSense Edge on Bluetooth, shown to games as the same pad on a USB cable.
//
// Games that drive the pad themselves (Sony's PC library) speak the wired protocol, and give a
// Bluetooth pad less, or nothing: on a cable they find the haptics output by its container, which
// winebus.sys builds from the USB location. So the Bluetooth pad gets the wired pad's report
// descriptor and bus type, keeps its own location ID (macOS gives a Bluetooth pad one, the low
// four bytes of its address), and its reports are translated: input 0x31 becomes USB 0x01, and the
// game's USB output 0x02 becomes Bluetooth 0x31 with its sequence and CRC.
//
// One thread per pad is the only writer to it, as a Bluetooth link drains only about 65 reports a
// second: the game's output, merged, at most every 16 ms; and the haptics. Those arrive on a socket
// from the winecoreaudio part, which shows the wired pad's 4-channel output for this pad and sends
// its channels 3 and 4 at the pad's 3 kHz. While they play, the writer sends them 64 frames at a
// time in reports 0x32 (0x33 first), every 21.3 ms, and the game's output takes what is left of the
// link.
//
// The approach is NotProton PR #90's controller bridge; engine patches 0004, 0006 and 0016 carried
// it inside winebus.so. On only while Game Feel's settings have "bluetooth=wired".
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include <sys/socket.h>
#include <sys/un.h>
#include "bt.h"

#define COUNT_OF(a) (sizeof(a) / sizeof((a)[0]))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

/* The standard pad's, as published at github.com/nondebug/dualsense. */
const uint8_t ds_usb_descriptor[] =
{
    0x05, 0x01, 0x09, 0x05, 0xa1, 0x01, 0x85, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x09, 0x32, 0x09, 0x35, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xff,
    0x00, 0x75, 0x08, 0x95, 0x06, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x20,
    0x95, 0x01, 0x81, 0x02, 0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
    0x35, 0x00, 0x46, 0x3b, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81,
    0x42, 0x65, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0f, 0x15, 0x00, 0x25,
    0x01, 0x75, 0x01, 0x95, 0x0f, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x21,
    0x95, 0x0d, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x22, 0x15, 0x00, 0x26,
    0xff, 0x00, 0x75, 0x08, 0x95, 0x34, 0x81, 0x02, 0x85, 0x02, 0x09, 0x23,
    0x95, 0x2f, 0x91, 0x02, 0x85, 0x05, 0x09, 0x33, 0x95, 0x28, 0xb1, 0x02,
    0x85, 0x08, 0x09, 0x34, 0x95, 0x2f, 0xb1, 0x02, 0x85, 0x09, 0x09, 0x24,
    0x95, 0x13, 0xb1, 0x02, 0x85, 0x0a, 0x09, 0x25, 0x95, 0x1a, 0xb1, 0x02,
    0x85, 0x20, 0x09, 0x26, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0x21, 0x09, 0x27,
    0x95, 0x04, 0xb1, 0x02, 0x85, 0x22, 0x09, 0x40, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0x80, 0x09, 0x28, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0x81, 0x09, 0x29,
    0x95, 0x3f, 0xb1, 0x02, 0x85, 0x82, 0x09, 0x2a, 0x95, 0x09, 0xb1, 0x02,
    0x85, 0x83, 0x09, 0x2b, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0x84, 0x09, 0x2c,
    0x95, 0x3f, 0xb1, 0x02, 0x85, 0x85, 0x09, 0x2d, 0x95, 0x02, 0xb1, 0x02,
    0x85, 0xa0, 0x09, 0x2e, 0x95, 0x01, 0xb1, 0x02, 0x85, 0xe0, 0x09, 0x2f,
    0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf0, 0x09, 0x30, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0xf1, 0x09, 0x31, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf2, 0x09, 0x32,
    0x95, 0x0f, 0xb1, 0x02, 0x85, 0xf4, 0x09, 0x35, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0xf5, 0x09, 0x36, 0x95, 0x03, 0xb1, 0x02, 0xc0,
};

/* The Edge's, read from a pad on a cable. */
const uint8_t ds_edge_usb_descriptor[] =
{
    0x05, 0x01, 0x09, 0x05, 0xa1, 0x01, 0x85, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x09, 0x32, 0x09, 0x35, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xff,
    0x00, 0x75, 0x08, 0x95, 0x06, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x20,
    0x95, 0x01, 0x81, 0x02, 0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
    0x35, 0x00, 0x46, 0x3b, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81,
    0x42, 0x65, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0f, 0x15, 0x00, 0x25,
    0x01, 0x75, 0x01, 0x95, 0x0f, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x21,
    0x95, 0x0d, 0x81, 0x02, 0x06, 0x00, 0xff, 0x09, 0x22, 0x15, 0x00, 0x26,
    0xff, 0x00, 0x75, 0x08, 0x95, 0x34, 0x81, 0x02, 0x85, 0x02, 0x09, 0x23,
    0x95, 0x3f, 0x91, 0x02, 0x85, 0x05, 0x09, 0x33, 0x95, 0x28, 0xb1, 0x02,
    0x85, 0x08, 0x09, 0x34, 0x95, 0x2f, 0xb1, 0x02, 0x85, 0x09, 0x09, 0x24,
    0x95, 0x13, 0xb1, 0x02, 0x85, 0x0a, 0x09, 0x25, 0x95, 0x1a, 0xb1, 0x02,
    0x85, 0x0b, 0x09, 0x41, 0x95, 0x29, 0xb1, 0x02, 0x85, 0x0c, 0x09, 0x42,
    0x95, 0x29, 0xb1, 0x02, 0x85, 0x20, 0x09, 0x26, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0x21, 0x09, 0x27, 0x95, 0x04, 0xb1, 0x02, 0x85, 0x22, 0x09, 0x40,
    0x95, 0x3f, 0xb1, 0x02, 0x85, 0x80, 0x09, 0x28, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0x81, 0x09, 0x29, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0x82, 0x09, 0x2a,
    0x95, 0x09, 0xb1, 0x02, 0x85, 0x83, 0x09, 0x2b, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0x84, 0x09, 0x2c, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0x85, 0x09, 0x2d,
    0x95, 0x02, 0xb1, 0x02, 0x85, 0xa0, 0x09, 0x2e, 0x95, 0x01, 0xb1, 0x02,
    0x85, 0xe0, 0x09, 0x2f, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf0, 0x09, 0x30,
    0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf1, 0x09, 0x31, 0x95, 0x3f, 0xb1, 0x02,
    0x85, 0xf2, 0x09, 0x32, 0x95, 0x34, 0xb1, 0x02, 0x85, 0xf4, 0x09, 0x35,
    0x95, 0x3f, 0xb1, 0x02, 0x85, 0xf5, 0x09, 0x36, 0x95, 0x03, 0xb1, 0x02,
    0x85, 0x60, 0x09, 0x41, 0x95, 0x3f, 0xb1, 0x02, 0x85, 0x61, 0x09, 0x42,
    0xb1, 0x02, 0x85, 0x62, 0x09, 0x43, 0xb1, 0x02, 0x85, 0x63, 0x09, 0x44,
    0xb1, 0x02, 0x85, 0x64, 0x09, 0x45, 0xb1, 0x02, 0x85, 0x65, 0x09, 0x46,
    0xb1, 0x02, 0x85, 0x68, 0x09, 0x47, 0xb1, 0x02, 0x85, 0x70, 0x09, 0x48,
    0xb1, 0x02, 0x85, 0x71, 0x09, 0x49, 0xb1, 0x02, 0x85, 0x72, 0x09, 0x4a,
    0xb1, 0x02, 0x85, 0x73, 0x09, 0x4b, 0xb1, 0x02, 0x85, 0x74, 0x09, 0x4c,
    0xb1, 0x02, 0x85, 0x75, 0x09, 0x4d, 0xb1, 0x02, 0x85, 0x76, 0x09, 0x4e,
    0xb1, 0x02, 0x85, 0x77, 0x09, 0x4f, 0xb1, 0x02, 0x85, 0x78, 0x09, 0x50,
    0xb1, 0x02, 0x85, 0x79, 0x09, 0x51, 0xb1, 0x02, 0x85, 0x7a, 0x09, 0x52,
    0xb1, 0x02, 0x85, 0x7b, 0x09, 0x53, 0xb1, 0x02, 0xc0,
};


/* The most haptics the queue holds: 192 frames, 64 ms. A link that cannot carry
 * them all loses the oldest frames instead of playing everything later; with its
 * whole 512 frames the queue sat at 170 ms in Uncharted. */
#define BT_QUEUE_LIMIT 192

static uint32_t bt_crc32(uint8_t seed, const uint8_t *data, size_t length)
{
    uint32_t crc = ~0u;
    size_t i;
    int bit;

    crc ^= seed;
    for (bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
    for (i = 0; i < length; i++)
    {
        crc ^= data[i];
        for (bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
    }
    return ~crc;
}

/* Fields a game sets with a valid flag: one report merged over another keeps
 * an earlier field the later one did not set. Anything else is the later
 * report's. Offsets count from the byte after the report ID. */
static const struct { uint8_t flag, mask, offset, length; } bt_fields[] =
{
    {0, 0x03,  2,  2},  /* rumble motors */
    {0, 0x04, 10, 11},  /* right trigger effect */
    {0, 0x08, 21, 11},  /* left trigger effect */
    {1, 0x01,  8,  1},  /* microphone LED */
    {1, 0x04, 44,  3},  /* lightbar colour */
    {1, 0x10, 43,  1},  /* player LEDs */
    {1, 0x40, 36,  1},  /* motor power */
};

/* Waits for new output or haptics, or until the deadline. */
static void bt_wait_until(struct bt_pad *pad, uint64_t deadline)
{
    uint64_t now = mach_absolute_time(), nanos;

    if (deadline <= now) return;
    nanos = pad_seconds(deadline - now) * 1e9;
    semaphore_timedwait(pad->wake, (mach_timespec_t){(unsigned int)(nanos / 1000000000), (clock_res_t)(nanos % 1000000000)});
}

static bool bt_write(struct bt_pad *pad, uint8_t *report, unsigned size)
{
    uint32_t crc = bt_crc32(0xa2, report, size - 4);
    int i;

    for (i = 0; i < 4; i++) report[size - 4 + i] = crc >> (8 * i);
    static bool told;

    if (!IOHIDDeviceSetReport(pad->device, kIOHIDReportTypeOutput, report[0], report, size)) return true;
    if (!told) pad_log("Bluetooth output 0x%02x to the DualSense failed (said once)\n", report[0]);
    told = true;
    return false;
}

/* Report 0x31. In audio mode the rumble bits are the writer's to clear, so that
 * a game's rumble or reset command cannot stop the haptics; out of it the pad
 * rumbles with the game's last motor values. */
static void bt_control(struct bt_pad *pad, const uint8_t *payload, bool audio)
{
    uint8_t report[78] = {0x31};

    report[1] = (pad->seq++ & 15) << 4;
    report[2] = 0x10;
    if (payload) memcpy(report + 3, payload, 47);
    if (pad_option("motor_power=full"))
    {
        report[4] |= 0x40;
        report[39] = 0;
    }
    if (audio)
    {
        report[3] &= ~3;
        report[5] = report[6] = 0;
    }
    else if (pad->rumble_improved)
    {
        report[3] = (report[3] & ~1) | 2;
        report[5] = pad->motors[0];
        report[6] = pad->motors[1];
    }
    else
    {
        report[3] |= 3;
        report[5] = pad->motors[0];
        report[6] = pad->motors[1];
    }
    /* Byte 41 (the game's byte 39) bit 0x04: the improved rumble emulation, only
     * out of audio mode and only on a pad that takes it. */
    if (!audio && pad->rumble_improved) report[41] |= 4;
    else report[41] &= ~4;
    /* While haptics stream, the same report again is not written. The game's
     * motor values are cleared from it there, and Uncharted sends them all the
     * time: its copies took up to 18 of the link's ~65 reports a second, and the
     * haptics, which need 46.875, got about 40. The sequence number and the CRC
     * are not compared. */
    if (audio && pad->control_known && !memcmp(report + 2, pad->control_last + 2, sizeof(report) - 6)) return;
    memcpy(pad->control_last, report, sizeof(report));
    pad->control_known = true;
    bt_write(pad, report, sizeof(report));
}

/* Reports 0x33 (the first, which sets the pad's audio up) and 0x32: 64 frames
 * of 3 kHz signed 8-bit stereo. */
static void bt_pcm(struct bt_pad *pad, unsigned int index, const signed char samples[128])
{
    uint8_t report[206] = {0};
    unsigned size, offset;

    report[0] = index ? 0x32 : 0x33;
    report[1] = (pad->seq++ & 15) << 4;
    report[2] = 0x91;
    if (!index)
    {
        report[3] = 7;
        report[4] = 0xfe;
        memset(report + 5, 48, 5);
        report[11] = 0xd2;
        report[12] = 64;
        offset = 13;
        size = 206;
    }
    else
    {
        report[3] = 3;
        report[4] = 0x62;
        report[5] = 48;
        report[6] = (uint8_t)(index * 2);
        report[7] = 0xd2;
        report[8] = 64;
        offset = 9;
        size = 142;
    }
    memcpy(report + offset, samples, 128);
    bt_write(pad, report, size);
}

static void *bt_receiver(void *arg)
{
    struct bt_pad *pad = arg;
    struct pad_packet packet;
    ssize_t got;
    unsigned int i, n;
    bool nonzero;

    while (!pad->quit)
    {
        if ((got = recv(pad->sock, &packet, sizeof(packet), 0)) < 6 || memcmp(packet.magic, "MGFH", 4)) continue;
        n = (got - 4) / 2;
        nonzero = false;
        pthread_mutex_lock(&pad->lock);
        for (i = 0; i < n; i++)
        {
            if (pad->fifo_count >= BT_QUEUE_LIMIT)
            {
                pad->fifo_head = (pad->fifo_head + 1) % COUNT_OF(pad->fifo);
                pad->fifo_count--;
            }
            memcpy(pad->fifo[(pad->fifo_head + pad->fifo_count++) % COUNT_OF(pad->fifo)], packet.samples + 2 * i, 2);
            nonzero |= packet.samples[2 * i] || packet.samples[2 * i + 1];
        }
        pad->audio_at = mach_absolute_time();
        if (nonzero) pad->nonzero_at = pad->audio_at;
        pthread_mutex_unlock(&pad->lock);
        semaphore_signal(pad->wake);
    }
    return NULL;
}

/* rumble=haptics: the game's motor values played on the actuators instead of
 * the motors, for a game that rumbles and plays no haptics of its own (an XInput
 * title). The heavy motor becomes a 65 Hz tone on the left actuator and the
 * light one a 160 Hz tone on the right, 64 frames a block, the amplitude ramped
 * across the block from the last so a step does not click; as NotProton's
 * controller bridge did (fork/controllers, PCM.h DSBRumbleSynthBlock). A motor
 * value under 4 of 255 renders nothing. Real haptics from the game win. */
static void bt_synth(struct bt_pad *pad, uint8_t heavy, uint8_t light, signed char out[128])
{
    static const double hz[2] = {65.0, 160.0};
    /* The haptics' strength over Bluetooth applies to the tone as to the game's own haptics, up to full scale. */
    const float target[2] = {heavy < 4 ? 0 : fminf(1, heavy / 255.f * pad->synth_gain),
                             light < 4 ? 0 : fminf(1, light / 255.f * pad->synth_gain)};
    unsigned int i, ch;
    float amplitude;
    double v;

    for (i = 0; i < 64; i++)
        for (ch = 0; ch < 2; ch++)
        {
            amplitude = pad->synth_level[ch] + (target[ch] - pad->synth_level[ch]) * (i + 1) / 64.f;
            v = sin(pad->synth_phase[ch]) * amplitude * 127;
            out[2 * i + ch] = (signed char)lrint(fmax(-127, fmin(127, v)));
            pad->synth_phase[ch] += 2 * M_PI * hz[ch] / 3000;
            if (pad->synth_phase[ch] >= 2 * M_PI) pad->synth_phase[ch] -= 2 * M_PI;
        }
    pad->synth_level[0] = target[0];
    pad->synth_level[1] = target[1];
}

/* The pad's one writer. Haptics start when the game plays something on
 * channels 3 and 4, or, with rumble=haptics, when its motor values say
 * something. They stop 150 ms after the game stops sending, or after 150 ms of
 * silence when the game has motor values to rumble with: a game that plays
 * haptics and no rumble keeps one stream through its quiet stretches, since a
 * stream that starts again switches the pad's mode, waits 30 ms and sets the
 * pad's audio up again (report 0x33) before its first sound (Uncharted started
 * the stream 54 times in two minutes). The game's output goes out at most every
 * 16 ms, or while haptics stream, in the link's remaining ~18 reports a second.
 * It writes nothing while the pad sends no input: the link is gone. */
static void *bt_writer(void *arg)
{
    struct bt_pad *pad = arg;
    const double pcm_period = 64.0 / 3000, streaming_gap = 1.0 / (65 - 3000.0 / 64);
    uint8_t payload[47];
    signed char samples[128];
    bool streaming = false, audio, control, synth, flowing, heard;
    unsigned int index = 0, i, n, take;
    uint64_t now, next_pcm = 0, next_control = 0, wake_at;
    uint8_t heavy, light;

    pad_realtime(pcm_period, 0.005);

    while (!pad->quit)
    {
        now = mach_absolute_time();
        pthread_mutex_lock(&pad->lock);
        if (now - pad->input_at > pad_ticks(0.5))
        {
            pthread_mutex_unlock(&pad->lock);
            streaming = false;
            bt_wait_until(pad, now + pad_ticks(0.020));
            continue;
        }
        flowing = pad->fifo_count || now - pad->audio_at < pad_ticks(0.15);
        heard = pad->nonzero_at && now - pad->nonzero_at < pad_ticks(0.15);
        audio = flowing && (heard || (streaming && pad->motors[0] < 4 && pad->motors[1] < 4));
        if (pad->synth && (pad->motors[0] >= 4 || pad->motors[1] >= 4)) pad->synth_at = now;
        synth = pad->synth && !audio && pad->synth_at && now - pad->synth_at < pad_ticks(0.15);
        heavy = pad->motors[1];
        light = pad->motors[0];
        if (!audio && !synth && !streaming) pad->fifo_head = pad->fifo_count = 0;
        if ((control = pad->dirty && now >= next_control))
        {
            memcpy(payload, pad->pending, sizeof(payload));
            pad->dirty = false;
        }
        pthread_mutex_unlock(&pad->lock);

        if (control)
        {
            bt_control(pad, payload, audio || streaming);
            next_control = mach_absolute_time() + pad_ticks(audio || streaming ? streaming_gap : 0.016);
        }
        if ((audio || synth) && !streaming)
        {
            bt_control(pad, NULL, true);
            streaming = true;
            index = 0;
            next_pcm = mach_absolute_time() + pad_ticks(0.030);
        }
        if (streaming && mach_absolute_time() >= next_pcm)
        {
            /* After a stall, start the clock again rather than send a burst. */
            if (mach_absolute_time() > next_pcm + pad_ticks(0.040)) next_pcm = mach_absolute_time();
            memset(samples, 0, sizeof(samples));
            pthread_mutex_lock(&pad->lock);
            /* The link cannot always carry the 46.875 reports a second the haptics
             * need, and a stream that no longer stops on silence has nothing else
             * to empty the queue: it filled to its 170 ms in Uncharted. Past 96
             * frames (32 ms) a block takes up to 12 frames more and spreads them
             * over its 64 by linear interpolation, a few percent faster, which the
             * hand does not tell, rather than let the queue grow. */
            take = pad->fifo_count > 96 ? 64 + MIN(12, (pad->fifo_count - 96) / 8) : 64;
            if (take > 64 && pad->fifo_count > take)
            {
                for (i = 0; i < 64; i++)
                {
                    unsigned int at = i * take / 64, frac = i * take % 64, ch;
                    const signed char *a = pad->fifo[(pad->fifo_head + at) % COUNT_OF(pad->fifo)];
                    const signed char *b = pad->fifo[(pad->fifo_head + at + 1) % COUNT_OF(pad->fifo)];
                    for (ch = 0; ch < 2; ch++) samples[2 * i + ch] = (a[ch] * (64 - (int)frac) + b[ch] * (int)frac) / 64;
                }
                pad->fifo_head = (pad->fifo_head + take) % COUNT_OF(pad->fifo);
                pad->fifo_count -= take;
                n = 64;
            }
            else
            {
                n = MIN(pad->fifo_count, 64);
                for (i = 0; i < n; i++)
                {
                    memcpy(samples + 2 * i, pad->fifo[pad->fifo_head], 2);
                    pad->fifo_head = (pad->fifo_head + 1) % COUNT_OF(pad->fifo);
                    pad->fifo_count--;
                }
            }
            pthread_mutex_unlock(&pad->lock);
            if (!n && synth) bt_synth(pad, heavy, light, samples);
            bt_pcm(pad, index++, samples);
            next_pcm += pad_ticks(pcm_period);
            if (!audio && !synth)
            {
                pad->synth_level[0] = pad->synth_level[1] = 0;
                /* Let the silent tail reach the actuators, then rumble again. */
                mach_wait_until(mach_absolute_time() + pad_ticks(0.030));
                pthread_mutex_lock(&pad->lock);
                memcpy(payload, pad->pending, sizeof(payload));
                pthread_mutex_unlock(&pad->lock);
                bt_control(pad, payload, false);
                streaming = false;
            }
        }

        now = mach_absolute_time();
        wake_at = now + pad_ticks(0.050);
        if (streaming && next_pcm < wake_at) wake_at = next_pcm;
        pthread_mutex_lock(&pad->lock);
        if (pad->dirty && next_control < wake_at) wake_at = next_control;
        pthread_mutex_unlock(&pad->lock);
        /* The haptics' deadline is kept to the tick; anything else may wake it early. */
        if (streaming && wake_at == next_pcm) mach_wait_until(wake_at);
        else bt_wait_until(pad, wake_at);
    }
    return NULL;
}

void bt_queue_output(struct bt_pad *pad, const uint8_t *usb)
{
    const uint8_t *update = usb + 1;
    uint8_t merged[47];
    unsigned int i;

    pthread_mutex_lock(&pad->lock);
    memcpy(merged, update, sizeof(merged));
    if (pad->dirty)
    {
        for (i = 0; i < COUNT_OF(bt_fields); i++)
        {
            uint8_t flag = bt_fields[i].flag, mask = bt_fields[i].mask & pad->pending[flag] & ~update[flag];
            if (!mask) continue;
            merged[flag] |= mask;
            memcpy(merged + bt_fields[i].offset, pad->pending + bt_fields[i].offset, bt_fields[i].length);
        }
    }
    /* A report with 0x01 of the first flag byte (or the improved emulation's 0x04
     * of byte 39) sets the motors. One with 0x02 alone keeps the pad rumbling with
     * the values it has, as the pad itself does on a cable: Grand Theft Auto V
     * Enhanced rumbles with 0x03 and updates its lights and triggers with 0x02 and
     * the motors at 0, and on a cable it vibrates (2026-10-26); taking those as the
     * motors stopped every rumble within a few milliseconds over Bluetooth. One
     * with neither ends the emulated rumble, as the pad does on a cable, where such
     * a report puts it back to audio haptics. SDL stops a rumble that way, never
     * with motors at 0: the writer kept rumbling with the last values over
     * Bluetooth, through a whole fight of Mortal Kombat 1. */
    if ((update[0] & 1) || (update[38] & 4))
    {
        pad->motors[0] = update[2];
        pad->motors[1] = update[3];
    }
    else if (!(update[0] & 2)) pad->motors[0] = pad->motors[1] = 0;
    memcpy(pad->pending, merged, sizeof(merged));
    pad->dirty = true;
    pthread_mutex_unlock(&pad->lock);
    semaphore_signal(pad->wake);
}

/* The haptics' strength over Bluetooth, 1 to 4, as winecoreaudio.so reads it for
 * the game's own haptics: edge_haptics_gain_bluetooth or haptics_gain_bluetooth,
 * else an older file's edge_haptics_gain or haptics_gain; by the pad it is, not
 * the one it is shown as. */
static float pad_gain_bluetooth(bool edge)
{
    const char *v = pad_value(edge ? "edge_haptics_gain_bluetooth" : "haptics_gain_bluetooth");
    float gain;

    if (!*v) v = pad_value(edge ? "edge_haptics_gain" : "haptics_gain");
    gain = *v ? pad_number(v) : 1;
    return isfinite(gain) ? fmaxf(1, fminf(4, gain)) : 1;
}
struct bt_pad *bt_pad_create(IOHIDDeviceRef device, uint32_t pid, uint32_t location, bool physical_edge)
{
    struct bt_pad *pad;

    if (!(pad = calloc(1, sizeof(*pad)))) return NULL;
    pad->device = device;
    pad->edge = pid == DS_EDGE_PID;
    pad->physical_edge = physical_edge;
    pad->synth_gain = pad_gain_bluetooth(physical_edge);
    if ((pad->synth = pad_option("rumble=haptics")))
        pad_log("the game's rumble plays on the actuators over Bluetooth, at %.2f\n", pad->synth_gain);
    pad->location = location;
    pad->sock = -1;
    pthread_mutex_init(&pad->lock, NULL);
    if (semaphore_create(mach_task_self(), &pad->wake, SYNC_POLICY_FIFO, 0))
    {
        free(pad);
        return NULL;
    }
    return pad;
}

/* The socket winecoreaudio.so finds the pad by: /tmp/macgamefix-<uid>/
 * pad-<location>-<product shown>-<product it is>.sock. */
static void bt_pad_listen(struct bt_pad *pad)
{
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    struct timeval timeout = {0, 200000};
    char dir[64];

    pad_dir(dir, sizeof(dir));
    snprintf(pad->path, sizeof(pad->path), "%s/" PAD_SOCKET, dir, (unsigned int)pad->location,
             pad->edge ? DS_EDGE_PID : DUALSENSE_PID, pad->physical_edge ? DS_EDGE_PID : DUALSENSE_PID);
    if ((pad->sock = socket(AF_UNIX, SOCK_DGRAM, 0)) < 0) return;
    unlink(pad->path);
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", pad->path);
    if (bind(pad->sock, (struct sockaddr *)&addr, sizeof(addr)))
    {
        pad_log("cannot listen for the DualSense's haptics at %s\n", pad->path);
        close(pad->sock);
        pad->sock = -1;
        return;
    }
    setsockopt(pad->sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
}

void bt_pad_start(struct bt_pad *pad)
{
    uint8_t calibration[64] = {0x05};
    CFIndex length = 41;

    /* Reading the calibration switches the pad from its short Bluetooth
     * report to the full 0x31 one, as Linux's driver does. */
    IOHIDDeviceGetReport(pad->device, kIOHIDReportTypeFeature, 0x05, calibration, &length);
    pad->input_at = mach_absolute_time();
    pad->quit = false;
    /* A pad shown as a DualShock 4 gets no socket, so winecoreaudio.so shows no
     * haptics output for it: a DualShock 4 has no haptics, and a game that knows
     * only that pad never plays any. The writer still plays rumble=haptics. */
    if (!pad->no_haptics) bt_pad_listen(pad);
    pad->running = !pthread_create(&pad->writer, NULL, bt_writer, pad);
    if (pad->running && pad->sock >= 0 && pthread_create(&pad->receiver, NULL, bt_receiver, pad))
    {
        close(pad->sock);
        pad->sock = -1;
    }
}

void bt_pad_stop(struct bt_pad *pad)
{
    if (!pad->running) return;
    pad->quit = true;
    semaphore_signal(pad->wake);
    pthread_join(pad->writer, NULL);
    if (pad->sock >= 0)
    {
        pthread_join(pad->receiver, NULL);
        close(pad->sock);
        unlink(pad->path);
        pad->sock = -1;
    }
    pad->running = false;
}

const size_t ds_usb_descriptor_size = sizeof(ds_usb_descriptor);
const size_t ds_edge_usb_descriptor_size = sizeof(ds_edge_usb_descriptor);
