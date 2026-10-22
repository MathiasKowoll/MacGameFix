/* Host test of dualshock4.h, the translations patch 0013 gives winebus.so for a
 * DualSense or Edge shown to a game as a USB DualShock 4 (pad_as=dualshock4).
 * run.sh takes the header out of the patch and builds this against it. Every
 * expected byte below is written out by hand from the layouts in Linux's
 * hid-playstation.c, not computed with the code under test. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dualshock4.h"

static int failures, checks;

static void check(int ok, const char *what)
{
    checks++;
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", what);
}

static void check_bytes(const uint8_t *got, const uint8_t *want, size_t length, const char *what)
{
    size_t i;

    checks++;
    for (i = 0; i < length; i++)
        if (got[i] != want[i])
        {
            failures++;
            printf("FAIL: %s: byte %zu is 0x%02x, expected 0x%02x\n", what, i, got[i], want[i]);
            return;
        }
}

/* ---- input: DualSense 0x01 to DualShock 4 0x01 ---- */

static void test_input(void)
{
    static const uint8_t want[64] =
    {
        0x01, 0x11, 0x22, 0x33, 0x44,  /* id, LX LY RX RY */
        0xa3,                          /* hat 3 (south-east), Cross, Triangle */
        0xc5,                          /* L1, L2, L3, R3 */
        0xb7,                          /* PS, touchpad, counter 0x2d in bits 2-7; mute and Edge bits dropped */
        0x55, 0x66,                    /* L2, R2 analog */
        0x67, 0x45,                    /* timestamp 0x12345678 / 16 = 0x01234567, low 16 bits */
        0x1f,                          /* temperature */
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06,  /* gyro */
        0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,  /* accelerometer */
        0x00, 0x00, 0x00, 0x00, 0x00,  /* reserved */
        0x14,                          /* cable, level 4: charging */
        0x00, 0x00,                    /* status 1 (no adapter bit), reserved */
        0x01, 0x6d,                    /* one touch report, its stamp */
        0x05, 0xd2, 0x84, 0x36,        /* contact 5 at x 1234, y 1000 -> 872 */
        0x86, 0x7f, 0xd7, 0x3a,        /* contact 6 up, x 1919, y 1079 -> 941 */
        0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00,  /* touch report 2, contacts up */
        0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00,  /* touch report 3, contacts up */
        0x00, 0x00, 0x00,              /* reserved */
    };
    static const struct { uint8_t ds, ds4; const char *what; } battery[] =
    {
        {0x00, 0x00, "battery: on battery, empty"},
        {0x07, 0x07, "battery: on battery, level 7"},
        {0x0c, 0x0a, "battery: on battery, a level past 10 is 10"},
        {0x14, 0x14, "battery: charging, level 4"},
        {0x1a, 0x1a, "battery: charging, level 10"},
        {0x25, 0x1b, "battery: full"},
        {0xa3, 0x1e, "battery: voltage or temperature error"},
        {0xb0, 0x1e, "battery: temperature error"},
        {0xf2, 0x1f, "battery: charge error"},
        {0x37, 0x1f, "battery: an unknown charge state"},
    };
    uint8_t ds[64], ds4[64];
    unsigned int i;

    memset(ds, 0xee, sizeof(ds));
    ds[0] = 0x01;
    ds[1] = 0x11; ds[2] = 0x22; ds[3] = 0x33; ds[4] = 0x44;
    ds[5] = 0x55; ds[6] = 0x66;
    ds[7] = 0x77;
    ds[8] = 0xa3; ds[9] = 0xc5; ds[10] = 0xf7; ds[11] = 0xff;
    for (i = 0; i < 12; i++) ds[16 + i] = (uint8_t)(i + 1);
    ds[28] = 0x78; ds[29] = 0x56; ds[30] = 0x34; ds[31] = 0x12;
    ds[32] = 0x1f;
    ds[33] = 0x05; ds[34] = 0xd2; ds[35] = 0x84; ds[36] = 0x3e;  /* x 0x4d2, y 0x3e8 */
    ds[37] = 0x86; ds[38] = 0x7f; ds[39] = 0x77; ds[40] = 0x43;  /* x 0x77f, y 0x437 */
    ds[53] = 0x14;

    memset(ds4, 0xcc, sizeof(ds4));
    ds4_input_from_dualsense(ds, ds4, 0x6d);
    check_bytes(ds4, want, 64, "input, every field");

    for (i = 0; i < sizeof(battery) / sizeof(battery[0]); i++)
    {
        ds[53] = battery[i].ds;
        ds4_input_from_dualsense(ds, ds4, 0);
        check(ds4[30] == battery[i].ds4, battery[i].what);
        check(ds4[31] == 0, "status 1 stays 0, the adapter bit clear");
    }

    /* The counter wraps at 6 bits under the buttons; the touch stamp keeps 8. */
    ds[10] = 0x00;
    ds4_input_from_dualsense(ds, ds4, 0x3f);
    check(ds4[7] == 0xfc, "counter 0x3f in bits 2-7");
    ds4_input_from_dualsense(ds, ds4, 0x40);
    check(ds4[7] == 0x00 && ds4[34] == 0x40, "counter 0x40 wraps to 0, stamp 0x40");

    /* The top of the timestamp is cut, not carried. */
    ds[28] = 0xff; ds[29] = 0xff; ds[30] = 0xff; ds[31] = 0xff;
    ds4_input_from_dualsense(ds, ds4, 0);
    check(ds4[10] == 0xff && ds4[11] == 0xff, "timestamp 0xffffffff / 16, low 16 bits");

    /* Hat released (8) and nothing pressed. */
    ds[8] = 0x08; ds[9] = 0x00;
    ds4_input_from_dualsense(ds, ds4, 0);
    check(ds4[5] == 0x08 && ds4[6] == 0x00, "hat released, no button");
}

/* ---- output: DualShock 4 0x05 to DualSense 0x02 ---- */

static void ds4_report(uint8_t out[32], uint8_t flags)
{
    unsigned int i;

    memset(out, 0, 32);
    out[0] = 0x05;
    out[1] = flags;
    out[4] = 0x40;   /* right, the light motor */
    out[5] = 0xc0;   /* left, the heavy motor */
    out[6] = 0x11; out[7] = 0x22; out[8] = 0x33;
    out[9] = 0x10; out[10] = 0x20;
    for (i = 11; i < 32; i++) out[i] = 0xee;  /* reserved: nothing of it may reach the pad */
}

static void test_output_at(size_t length)
{
    uint8_t ds4[32], ds[72], want[64];
    struct ds4_output_state state;
    char what[96];
    unsigned int r;

    /* 0x01: motors only. */
    memset(&state, 0, sizeof(state));
    memset(ds, 0xcc, sizeof(ds));
    ds4_report(ds4, 0x01);
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    memset(want, 0, sizeof(want));
    want[0] = 0x02; want[1] = 0x03; want[3] = 0x40; want[4] = 0xc0;
    snprintf(what, sizeof(what), "output at %zu, flags 0x01", length);
    check_bytes(ds, want, length, what);
    check(r == 0, "flags 0x01: no blink");
    check(ds[length] == 0xcc, "nothing written past the pad's length");

    /* 0x02: the light bar only, no motors ever set. */
    memset(&state, 0, sizeof(state));
    memset(ds, 0xcc, sizeof(ds));
    ds4_report(ds4, 0x02);
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    memset(want, 0, sizeof(want));
    want[0] = 0x02; want[2] = 0x04; want[45] = 0x11; want[46] = 0x22; want[47] = 0x33;
    snprintf(what, sizeof(what), "output at %zu, flags 0x02", length);
    check_bytes(ds, want, length, what);
    check(r == 0, "flags 0x02: no blink");

    /* 0x03: both. */
    memset(&state, 0, sizeof(state));
    ds4_report(ds4, 0x03);
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    memset(want, 0, sizeof(want));
    want[0] = 0x02; want[1] = 0x03; want[2] = 0x04; want[3] = 0x40; want[4] = 0xc0;
    want[45] = 0x11; want[46] = 0x22; want[47] = 0x33;
    snprintf(what, sizeof(what), "output at %zu, flags 0x03", length);
    check_bytes(ds, want, length, what);
    check(r == 0, "flags 0x03: no blink");

    /* 0x04: a blink, which a DualSense cannot do: said, and nothing written. */
    memset(&state, 0, sizeof(state));
    ds4_report(ds4, 0x04);
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    memset(want, 0, sizeof(want));
    want[0] = 0x02;
    snprintf(what, sizeof(what), "output at %zu, flags 0x04", length);
    check_bytes(ds, want, length, what);
    check(r == DS4_OUTPUT_BLINK, "flags 0x04: the blink is said");

    /* Blink times of 0 and 0 are a steady light (Linux writes them to stop a
     * blink, SDL sets 0x07 for pads it does not know as Sony's): no blink,
     * and the light bar still set. */
    memset(&state, 0, sizeof(state));
    ds4_report(ds4, 0x07);
    ds4[9] = ds4[10] = 0;
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    memset(want, 0, sizeof(want));
    want[0] = 0x02; want[1] = 0x03; want[2] = 0x04; want[3] = 0x40; want[4] = 0xc0;
    want[45] = 0x11; want[46] = 0x22; want[47] = 0x33;
    snprintf(what, sizeof(what), "output at %zu, flags 0x07, blink times 0", length);
    check_bytes(ds, want, length, what);
    check(r == 0, "flags 0x07 with blink times 0: no blink");
    ds4_report(ds4, 0xff);
    ds4[9] = ds4[10] = 0;
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    check(r == 0, "flags 0xff with blink times 0: no blink");
    /* One time not 0 is a blink. */
    ds4_report(ds4, 0x04);
    ds4[9] = 0;
    r = ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    check(r == DS4_OUTPUT_BLINK, "flags 0x04, on 0 and off 0x20: the blink is said");

    /* A DualShock 4 keeps its motors through a report that sets only the light
     * bar: the DualSense report carries them on. */
    memset(&state, 0, sizeof(state));
    ds4_report(ds4, 0x01);
    ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    ds4_report(ds4, 0x02);
    ds4[4] = ds4[5] = 0x99;  /* not valid in this report: must not be taken */
    ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    memset(want, 0, sizeof(want));
    want[0] = 0x02; want[1] = 0x03; want[2] = 0x04; want[3] = 0x40; want[4] = 0xc0;
    want[45] = 0x11; want[46] = 0x22; want[47] = 0x33;
    snprintf(what, sizeof(what), "output at %zu, light bar after motors keeps the motors", length);
    check_bytes(ds, want, length, what);

    /* Motors set to 0 stop them. */
    ds4_report(ds4, 0x01);
    ds4[4] = ds4[5] = 0;
    ds4_output_to_dualsense(ds4, 32, ds, length, &state);
    check(ds[1] == 0x03 && ds[3] == 0 && ds[4] == 0, "motors at 0 stop the rumble");
}

static void test_output(void)
{
    test_output_at(48);
    test_output_at(64);
}

/* ---- feature reports ---- */

static void test_features(void)
{
    static const uint8_t canned_mac[6] = {0x8b, 0x09, 0x07, 0x6d, 0x66, 0x1c};
    uint8_t calibration[41], pairing[20], out[72], want[64];
    unsigned int length, i;

    for (i = 0; i < sizeof(calibration); i++) calibration[i] = (uint8_t)(0x40 + i);
    calibration[0] = 0x05;
    for (i = 0; i < sizeof(pairing); i++) pairing[i] = 0xaa;
    pairing[0] = 0x09;
    pairing[1] = 0x11; pairing[2] = 0x22; pairing[3] = 0x33; pairing[4] = 0x44; pairing[5] = 0x55; pairing[6] = 0x66;

    /* 0x02: the pad's own calibration, bytes 1-34, then ViGEmBus's last two. */
    memset(out, 0xcc, sizeof(out));
    length = ds4_feature_reply(0x02, calibration, sizeof(calibration), pairing, sizeof(pairing), out, sizeof(out));
    check(length == 37, "feature 0x02 is 37 bytes");
    want[0] = 0x02;
    for (i = 1; i <= 34; i++) want[i] = (uint8_t)(0x40 + i);
    want[35] = 0x08; want[36] = 0x00;
    check_bytes(out, want, 37, "feature 0x02 from the pad's 0x05");
    check(out[37] == 0xcc, "feature 0x02: nothing past 37 bytes");

    /* 0x02 with no calibration, or one that is not a 0x05: a DualShock 4's. */
    length = ds4_feature_reply(0x02, NULL, 0, NULL, 0, out, sizeof(out));
    check(length == 37 && !memcmp(out, ds4_canned_calibration, 37), "feature 0x02 without the pad's: ViGEmBus's");
    calibration[0] = 0x31;
    length = ds4_feature_reply(0x02, calibration, sizeof(calibration), NULL, 0, out, sizeof(out));
    check(length == 37 && !memcmp(out, ds4_canned_calibration, 37), "feature 0x02 from a report that is not 0x05: ViGEmBus's");
    calibration[0] = 0x05;
    length = ds4_feature_reply(0x02, calibration, 20, NULL, 0, out, sizeof(out));
    check(length == 37 && !memcmp(out, ds4_canned_calibration, 37), "feature 0x02 from a short 0x05: ViGEmBus's");

    /* 0x12: the address in the DualSense's order (little-endian), 08 25 00, no host. */
    memset(out, 0xcc, sizeof(out));
    length = ds4_feature_reply(0x12, calibration, sizeof(calibration), pairing, sizeof(pairing), out, sizeof(out));
    check(length == 16, "feature 0x12 is 16 bytes");
    {
        static const uint8_t w[16] = {0x12, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x08, 0x25, 0x00,
                                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
        check_bytes(out, w, 16, "feature 0x12 from the pad's 0x09");
    }
    check(out[16] == 0xcc, "feature 0x12: nothing past 16 bytes");

    /* 0x81: the address again. */
    length = ds4_feature_reply(0x81, NULL, 0, pairing, sizeof(pairing), out, sizeof(out));
    {
        static const uint8_t w[7] = {0x81, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66};
        check(length == 7, "feature 0x81 is 7 bytes");
        check_bytes(out, w, 7, "feature 0x81 from the pad's 0x09");
    }

    /* An address of zeros, or none: ViGEmBus's stands in, never zeros (SDL refuses those). */
    memset(pairing + 1, 0, 6);
    length = ds4_feature_reply(0x12, NULL, 0, pairing, sizeof(pairing), out, sizeof(out));
    check(length == 16 && !memcmp(out + 1, canned_mac, 6), "feature 0x12 for an address of zeros");
    length = ds4_feature_reply(0x81, NULL, 0, NULL, 0, out, sizeof(out));
    check(length == 7 && !memcmp(out + 1, canned_mac, 6), "feature 0x81 with no address read");

    /* 0xa3: 49 bytes, hardware version at 35-36 at least 0x3100 (libScePad's gate). */
    length = ds4_feature_reply(0xa3, NULL, 0, NULL, 0, out, sizeof(out));
    check(length == 49 && out[0] == 0xa3, "feature 0xa3 is 49 bytes");
    check((out[35] | (out[36] << 8)) >= 0x3100, "feature 0xa3: hardware version 0x3100 or more");
    check((out[35] | (out[36] << 8)) == 0x3100 && (out[41] | (out[42] << 8)) == 0x0049,
          "feature 0xa3: ViGEmBus's hardware 0x3100, firmware 0x0049");

    /* Any other declared id: zeros after the id, at the declared length. */
    {
        static const struct { uint8_t id; unsigned int length; } others[] =
        {
            {0x04, 37}, {0x08, 4}, {0x10, 5}, {0x11, 3}, {0x13, 23}, {0x14, 17}, {0x15, 45},
            {0x80, 7}, {0x89, 3}, {0x93, 13}, {0xa0, 7}, {0xa4, 14}, {0xf0, 64}, {0xf2, 16}, {0xb0, 64},
        };
        char what[64];

        for (i = 0; i < sizeof(others) / sizeof(others[0]); i++)
        {
            memset(out, 0xcc, sizeof(out));
            length = ds4_feature_reply(others[i].id, calibration, sizeof(calibration), pairing, sizeof(pairing),
                                       out, sizeof(out));
            memset(want, 0, sizeof(want));
            want[0] = others[i].id;
            snprintf(what, sizeof(what), "feature 0x%02x: %u bytes of zeros", others[i].id, others[i].length);
            check(length == others[i].length, what);
            check_bytes(out, want, others[i].length, what);
        }
    }

    /* Ids the descriptor does not declare: none, so the caller refuses them. */
    check(ds4_feature_reply(0x03, NULL, 0, NULL, 0, out, sizeof(out)) == 0, "feature 0x03 is not declared");
    check(ds4_feature_reply(0x05, NULL, 0, NULL, 0, out, sizeof(out)) == 0, "feature 0x05 is not declared");
    check(ds4_feature_reply(0x06, NULL, 0, NULL, 0, out, sizeof(out)) == 0, "feature 0x06 is not declared");
    check(ds4_feature_reply(0x09, NULL, 0, NULL, 0, out, sizeof(out)) == 0, "feature 0x09 is not declared");

    /* A buffer too small: the length is said, nothing is written. */
    memset(out, 0xcc, sizeof(out));
    check(ds4_feature_reply(0xa3, NULL, 0, NULL, 0, out, 48) == 49 && out[0] == 0xcc,
          "feature 0xa3 into 48 bytes: length said, nothing written");
}

/* ---- the descriptor, parsed here on its own ---- */

struct parsed
{
    unsigned int input_bits[256], output_bits[256], feature_bits[256];
    unsigned int feature_page[256], feature_usage[256];
    int x_min, x_max, x_found, collections, depth;
};

static void parse(const uint8_t *d, size_t size, struct parsed *p)
{
    unsigned int page = 0, report_size = 0, report_count = 0, id = 0, usages[16], usage_count = 0, i;
    int logical_min = 0, logical_max = 0;
    size_t at = 0;

    memset(p, 0, sizeof(*p));
    while (at < size)
    {
        uint8_t prefix = d[at];
        unsigned int n = (prefix & 3) == 3 ? 4 : (prefix & 3), value = 0, k;
        int svalue;

        for (k = 0; k < n; k++) value |= (unsigned int)d[at + 1 + k] << (8 * k);
        svalue = n == 1 ? (int)(int8_t)value : n == 2 ? (int)(int16_t)value : (int)value;
        switch (prefix & 0xfc)
        {
        case 0x04: page = value; break;
        case 0x14: logical_min = svalue; break;
        case 0x24: logical_max = svalue; break;
        case 0x74: report_size = value; break;
        case 0x94: report_count = value; break;
        case 0x84: id = value; break;
        case 0x08: if (usage_count < 16) usages[usage_count++] = n == 4 ? value : (page << 16) | value; break;
        case 0xa0: p->collections++; p->depth++; usage_count = 0; break;
        case 0xc0: p->depth--; break;
        case 0x80:
            p->input_bits[id] += report_size * report_count;
            for (i = 0; i < usage_count; i++)
                if (usages[i] == 0x10030 && !p->x_found)
                {
                    p->x_found = 1;
                    p->x_min = logical_min;
                    p->x_max = logical_max;
                }
            usage_count = 0;
            break;
        case 0x90: p->output_bits[id] += report_size * report_count; usage_count = 0; break;
        case 0xb0:
            p->feature_bits[id] += report_size * report_count;
            if (usage_count)
            {
                p->feature_page[id] = usages[0] >> 16;
                p->feature_usage[id] = usages[0] & 0xffff;
            }
            usage_count = 0;
            break;
        }
        at += 1 + n;
    }
}

static void test_descriptor(void)
{
    static struct parsed p;

    {
        uint32_t hash = 2166136261u;
        size_t i;

        for (i = 0; i < sizeof(ds4_usb_descriptor); i++) hash = (hash ^ ds4_usb_descriptor[i]) * 16777619u;
        check(sizeof(ds4_usb_descriptor) == 467, "descriptor: 467 bytes, ViGEmBus's length");
        check(hash == 0x38ce732au, "descriptor: ViGEmBus's bytes (FNV-1a of Ds4Pdo.cpp's Ds4HidReportDescriptor)");
    }
    parse(ds4_usb_descriptor, sizeof(ds4_usb_descriptor), &p);
    check(p.collections == 1 && p.depth == 0, "descriptor: one top-level collection, closed");
    check(1 + p.input_bits[0x01] / 8 == 64 && p.input_bits[0x01] % 8 == 0, "descriptor: input 0x01 is 64 bytes");
    check(1 + p.output_bits[0x05] / 8 == 32, "descriptor: output 0x05 is 32 bytes");
    check(p.feature_bits[0xa3] && 1 + p.feature_bits[0xa3] / 8 == 49, "descriptor: feature 0xa3 is 49 bytes");
    check(p.feature_page[0xa3] == 0xff80 && p.feature_usage[0xa3] == 0x43, "descriptor: feature 0xa3 is FF80:0043");
    check(1 + p.feature_bits[0x02] / 8 == 37, "descriptor: feature 0x02 is 37 bytes");
    check(1 + p.feature_bits[0x12] / 8 == 16 && p.feature_page[0x12] == 0xff02, "descriptor: feature 0x12 is 16 bytes, FF02");
    check(1 + p.feature_bits[0x14] / 8 == 17 && p.feature_page[0x14] == 0xff05, "descriptor: feature 0x14 is 17 bytes, FF05");
    check(1 + p.feature_bits[0x81] / 8 == 7, "descriptor: feature 0x81 is 7 bytes");
    check(!p.feature_bits[0x06], "descriptor: no feature 0x06 (the Bluetooth DualShock 4's, which libScePad refuses)");
    check(p.x_found && p.x_min == 0 && p.x_max == 255, "descriptor: X logical 0 to 255 (unsigned, as patch 0008 needs)");
    {
        unsigned int id, most = 0;
        for (id = 0; id < 256; id++) if (p.feature_bits[id] / 8 + 1 > most) most = p.feature_bits[id] / 8 + 1;
        check(most >= 53 && most <= 64, "descriptor: the longest feature report 53 to 64 bytes");
    }
    /* The parser in dualshock4.h agrees with this one. */
    check(ds4_report_length(ds4_usb_descriptor, sizeof(ds4_usb_descriptor), 0x80, 0x01) == 64, "ds4_report_length: input 0x01");
    check(ds4_report_length(ds4_usb_descriptor, sizeof(ds4_usb_descriptor), 0x90, 0x05) == 32, "ds4_report_length: output 0x05");
    check(ds4_report_length(ds4_usb_descriptor, sizeof(ds4_usb_descriptor), 0xb0, 0xa3) == 49, "ds4_report_length: feature 0xa3");
    check(ds4_report_length(ds4_usb_descriptor, sizeof(ds4_usb_descriptor), 0x90, 0x02) == 0, "ds4_report_length: no output 0x02");
    check(DS4_INPUT_SIZE == 64 && DS4_OUTPUT_SIZE == 32 && DS4_PID == 0x05c4, "the header's constants");
}

int main(void)
{
    test_input();
    test_output();
    test_features();
    test_descriptor();
    printf("%d of %d checks passed\n", checks - failures, checks);
    return failures ? 1 : 0;
}
