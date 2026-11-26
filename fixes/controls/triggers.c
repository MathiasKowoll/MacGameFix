// Trigger effects the user chooses (Game Feel): engine patches 0006 and 0014, for the winebus part.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "controls.h"

/* MacGameFix: trigger effects the user chooses for a game that sets none of
 * its own, an XInput title above all: trigger_r2= and trigger_l2=, each off,
 * resist, weapon, slope, vibrate or rumble, with a strength from 1 to 8
 * ("weapon@6"). The effects are the layouts games write through Sony's library,
 * as NotProton's controller bridge wrote them (fork/controllers, Controls.h):
 * resist from zone 3 (strength 4 unless given), weapon from zone 3 giving way
 * at zone 6 (7), slope from zone 2 rising to the strength (8), vibrate at 25 Hz
 * from zone 2 (3). rumble vibrates the trigger at 40 Hz with the game's motor,
 * R2 with the light one and L2 with the heavy one, in eight steps and at most
 * one change every 60 ms. recoil follows the motor the same way but resists
 * instead (from zone 2, the step as the strength), with whichever motor is the
 * stronger, so a shot or a hit kicks the trigger back.
 *
 * Each trigger may have a second effect, for while the other trigger is pressed:
 * trigger_r2_with_l2= and trigger_l2_with_r2=, a weapon on R2 while L2 aims, say.
 * The other trigger counts as pressed from 40 of 255 and as released under 20,
 * read from the pad's own input reports, and the side's effect is written again
 * at each change (a rumble starts still and follows the motor from there). A
 * fixed effect is also written again each time its own trigger starts to be
 * pressed: a launch starts and stops Wine more than once, and a Wine that
 * stops releases the triggers, maybe after the next one set them.
 *
 * The pad keeps an effect until something else is written, so they are written
 * when the pad starts, and kept: a game that writes a trigger off (Sony's
 * library does when it starts) gets the chosen effect in its place, and a game
 * that writes an effect of its own owns that trigger from then on. Stopping
 * releases them; and since a Wine that is torn down stops nothing, a marker in
 * /tmp/macgamefix-<uid> lets the next start release what was left set. */
enum { TRIGGER_OFF, TRIGGER_RESIST, TRIGGER_WEAPON, TRIGGER_SLOPE, TRIGGER_VIBRATE, TRIGGER_RUMBLE, TRIGGER_RECOIL };

static void trigger_zones(const uint8_t strengths[10], uint8_t out[11])
{
    uint16_t zones = 0;
    uint32_t forces = 0;
    unsigned int zone, i;

    memset(out, 0, 11);
    for (zone = 0; zone < 10; zone++)
        if (strengths[zone] >= 1 && strengths[zone] <= 8)
        {
            zones |= 1u << zone;
            forces |= (uint32_t)(strengths[zone] - 1) << (3 * zone);
        }
    if (!zones)
    {
        out[0] = 0x05;
        return;
    }
    out[0] = 0x21;
    out[1] = zones & 0xff;
    out[2] = zones >> 8;
    for (i = 0; i < 4; i++) out[3 + i] = forces >> (8 * i);
}

/* The 11 bytes of a trigger's effect; for rumble, at a step of 0 to 8. */
static void trigger_effect(uint8_t kind, uint8_t strength, uint8_t step, uint8_t out[11])
{
    uint8_t strengths[10] = {0};
    unsigned int zone, top;

    switch (kind)
    {
    case TRIGGER_RESIST:
        for (zone = 3; zone < 10; zone++) strengths[zone] = strength ? strength : 4;
        trigger_zones(strengths, out);
        return;
    case TRIGGER_WEAPON:
        memset(out, 0, 11);
        out[0] = 0x25;
        out[1] = ((1u << 3) | (1u << 6)) & 0xff;
        out[2] = ((1u << 3) | (1u << 6)) >> 8;
        out[3] = (strength ? strength : 7) - 1;
        return;
    case TRIGGER_SLOPE:
        top = strength ? strength : 8;
        for (zone = 2; zone < 10; zone++) strengths[zone] = 1 + (top - 1) * (zone - 2) / 7;
        trigger_zones(strengths, out);
        return;
    case TRIGGER_RECOIL:
        top = (step * (strength ? strength : 8) + 7) / 8;
        for (zone = 2; zone < 10 && top; zone++) strengths[zone] = top;
        trigger_zones(strengths, out);
        return;
    case TRIGGER_VIBRATE:
    case TRIGGER_RUMBLE:
        top = kind == TRIGGER_VIBRATE ? (strength ? strength : 3) : (step * (strength ? strength : 8) + 7) / 8;
        for (zone = 2; zone < 10 && top; zone++) strengths[zone] = top;
        trigger_zones(strengths, out);
        if (out[0] == 0x21)
        {
            out[0] = 0x26;
            out[9] = kind == TRIGGER_VIBRATE ? 25 : 40;
        }
        return;
    default:
        memset(out, 0, 11);
        out[0] = 0x05;
    }
}

static void pad_trigger_choice(const char *key, uint8_t *kind, uint8_t *strength)
{
    static const char *const names[] = {"off", "resist", "weapon", "slope", "vibrate", "rumble", "recoil"};
    const char *v = pad_value(key), *at = strchr(v, '@');
    size_t length = at ? (size_t)(at - v) : strlen(v);
    unsigned int i;

    *kind = TRIGGER_OFF;
    *strength = 0;
    for (i = 0; i < COUNT_OF(names); i++)
        if (strlen(names[i]) == length && !strncmp(v, names[i], length)) *kind = i;
    if (at && at[1] >= '1' && at[1] <= '8' && !at[2]) *strength = at[1] - '0';
}

/* The effect a side has now: its second while the other trigger is held. */
static void trigger_active(const struct pad *p, unsigned int side, uint8_t *kind, uint8_t *strength)
{
    bool second = p->trigger_held[side] && p->trigger_kind2[side] != TRIGGER_OFF;

    *kind = second ? p->trigger_kind2[side] : p->trigger_kind[side];
    *strength = second ? p->trigger_strength2[side] : p->trigger_strength[side];
}

static bool trigger_chosen(const struct pad *p, unsigned int side)
{
    return p->trigger_kind[side] != TRIGGER_OFF || p->trigger_kind2[side] != TRIGGER_OFF;
}

static void trigger_marker(const struct pad *p, char *path, size_t size)
{
    char dir[64];

    pad_dir(dir, sizeof(dir));
    snprintf(path, size, "%s/triggers-%08x", dir, p->location);
}

/* A report of the pad's own, 0x02 with only `flags` valid: to a Bluetooth pad
 * through its writer, to a wired one as the game's own output goes. */
static void pad_write_output(struct pad *p, uint8_t *report)
{
    if (p->bt) bt_queue_output(p->bt, report);
    else IOHIDDeviceSetReport(p->device, kIOHIDReportTypeOutput, 0x02, report, p->edge ? 64 : 48);
}

/* The chosen effects, written when the pad starts; or, with none chosen, the
 * release of what an earlier run left set. */
void pad_triggers(struct pad *p)
{
    static const char *const keys[2] = {"trigger_r2", "trigger_l2"};
    static const char *const keys2[2] = {"trigger_r2_with_l2", "trigger_l2_with_r2"};
    uint8_t report[64] = {0x02};
    char path[64];
    unsigned int side, set = 0;
    FILE *f;

    p->settings_stamp = pad_settings_stamp();
    p->settings_checked = mach_absolute_time();
    for (side = 0; side < 2; side++)
    {
        pad_trigger_choice(keys[side], &p->trigger_kind[side], &p->trigger_strength[side]);
        pad_trigger_choice(keys2[side], &p->trigger_kind2[side], &p->trigger_strength2[side]);
        p->trigger_replace[side] = !strcmp(pad_value(side ? "trigger_l2_replace" : "trigger_r2_replace"), "on");
        if (!trigger_chosen(p, side)) continue;
        set |= 4 << side;
        if (p->trigger_kind[side] == TRIGGER_OFF) continue;
        report[1] |= 4 << side;
        trigger_effect(p->trigger_kind[side], p->trigger_strength[side], 0, report + 11 + 11 * side);
    }
    trigger_marker(p, path, sizeof(path));
    if (!set && (f = fopen(path, "r")))
    {
        if (fscanf(f, "%u", &set) != 1) set = 0;
        fclose(f);
        unlink(path);
        set &= 0x0c;
        report[1] = set;
        if (set & 0x04) report[11] = 0x05;
        if (set & 0x08) report[22] = 0x05;
        if (set) pad_write_output(p, report);
        return;
    }
    if (!set) return;
    if (report[1]) pad_write_output(p, report);
    if ((f = fopen(path, "w")))
    {
        fprintf(f, "%u\n", set);
        fclose(f);
    }
    pad_log("trigger effects chosen for the %s: R2 %s (with L2 %s)%s, L2 %s (with R2 %s)%s\n", p->model,
            pad_value("trigger_r2")[0] ? pad_value("trigger_r2") : "off",
            pad_value("trigger_r2_with_l2")[0] ? pad_value("trigger_r2_with_l2") : "the same",
            p->trigger_replace[0] ? " in place of the game's" : "",
            pad_value("trigger_l2")[0] ? pad_value("trigger_l2") : "off",
            pad_value("trigger_l2_with_r2")[0] ? pad_value("trigger_l2_with_r2") : "the same",
            p->trigger_replace[1] ? " in place of the game's" : "");
}

/* Game Feel written while the game runs: once a second the two files are
 * looked at, and when they changed the chosen effects are read again and put
 * on the pad, releasing a side whose effect was ours and has none now. A side
 * the game had taken follows the new choice until the game sets one again.
 * The other settings read on each report (motor_power, for one) follow by
 * themselves once the lines are read again; the ones that shape the device,
 * xinput, pad_as, bluetooth, wait for the next start. */
static void pad_settings_follow(struct pad *p)
{
    static const char *const keys[2] = {"trigger_r2", "trigger_l2"};
    static const char *const keys2[2] = {"trigger_r2_with_l2", "trigger_l2_with_r2"};
    uint8_t report[64] = {0x02};
    uint64_t now = mach_absolute_time();
    unsigned int side, set = 0;
    long long stamp;
    bool ours;
    char path[64];
    FILE *f;

    if (!p->settings_checked || now - p->settings_checked < pad_ticks(1.0)) return;
    p->settings_checked = now;
    if ((stamp = pad_settings_stamp()) == p->settings_stamp) return;
    p->settings_stamp = stamp;
    pad_reload();
    for (side = 0; side < 2; side++)
    {
        ours = trigger_chosen(p, side) && !p->trigger_game[side] && p->trigger_kind[side] != TRIGGER_OFF;
        pad_trigger_choice(keys[side], &p->trigger_kind[side], &p->trigger_strength[side]);
        pad_trigger_choice(keys2[side], &p->trigger_kind2[side], &p->trigger_strength2[side]);
        p->trigger_replace[side] = !strcmp(pad_value(side ? "trigger_l2_replace" : "trigger_r2_replace"), "on");
        p->trigger_game[side] = p->trigger_following[side] = p->trigger_game_on[side] = false;
        p->trigger_held[side] = false;
        p->trigger_step[side] = 0;
        if (trigger_chosen(p, side)) set |= 4 << side;
        if (trigger_chosen(p, side) && p->trigger_kind[side] != TRIGGER_OFF)
        {
            report[1] |= 4 << side;
            trigger_effect(p->trigger_kind[side], p->trigger_strength[side], 0, report + 11 + 11 * side);
        }
        else if (ours)
        {
            report[1] |= 4 << side;
            report[11 + 11 * side] = 0x05;
        }
    }
    if (report[1]) pad_write_output(p, report);
    trigger_marker(p, path, sizeof(path));
    if (!set) unlink(path);
    else if ((f = fopen(path, "w")))
    {
        fprintf(f, "%u\n", set);
        fclose(f);
    }
    pad_log("settings changed while the game runs: R2 %s%s, L2 %s%s\n",
            pad_value("trigger_r2")[0] ? pad_value("trigger_r2") : "off", p->trigger_replace[0] ? " in place of the game's" : "",
            pad_value("trigger_l2")[0] ? pad_value("trigger_l2") : "off", p->trigger_replace[1] ? " in place of the game's" : "");
}

/* From the pad's input report 0x01 (L2 at byte 5, R2 at byte 6): a side with a
 * second effect switches as the other trigger is pressed and released, and a
 * fixed effect is written again as its own trigger starts to be pressed. */
void pad_triggers_follow(struct pad *p, const uint8_t *input, unsigned length)
{
    uint8_t report[64] = {0x02}, kind, strength, other, own;
    unsigned int side;
    bool held, pressed;

    pad_settings_follow(p);
    if (length < 7 || input[0] != 0x01) return;
    for (side = 0; side < 2; side++)
    {
        if (!trigger_chosen(p, side) || p->trigger_game[side]) continue;
        /* On the game's timing: nothing of the chosen effect while the game's is off. */
        if (p->trigger_following[side] && !p->trigger_game_on[side]) continue;
        own = input[side ? 5 : 6];
        pressed = p->trigger_pressed[side] ? own >= 20 : own >= 40;
        if (pressed != p->trigger_pressed[side] && (p->trigger_pressed[side] = pressed))
        {
            trigger_active(p, side, &kind, &strength);
            if (kind != TRIGGER_OFF && kind != TRIGGER_RUMBLE && kind != TRIGGER_RECOIL)
            {
                report[1] |= 4 << side;
                trigger_effect(kind, strength, 0, report + 11 + 11 * side);
            }
        }
        if (p->trigger_kind2[side] == TRIGGER_OFF) continue;
        other = input[side ? 6 : 5];
        held = p->trigger_held[side] ? other >= 20 : other >= 40;
        if (held == p->trigger_held[side]) continue;
        p->trigger_held[side] = held;
        p->trigger_step[side] = 0;
        trigger_active(p, side, &kind, &strength);
        report[1] |= 4 << side;
        trigger_effect(kind, strength, 0, report + 11 + 11 * side);
    }
    if (report[1]) pad_write_output(p, report);
}

/* What the chosen effects make of a 0x02 on its way to the pad, in `copy`. */
uint8_t *pad_triggers_merge(struct pad *p, uint8_t *report, unsigned length, uint8_t copy[64], bool from_game)
{
    unsigned int side;
    uint8_t *field, mode, motor, step, kind, strength;

    for (side = 0; side < 2; side++)
    {
        if (!trigger_chosen(p, side) || p->trigger_game[side]) continue;
        trigger_active(p, side, &kind, &strength);
        field = report + 11 + 11 * side;
        mode = field[0];
        if (from_game && (report[1] & (4 << side)) && p->trigger_replace[side])
        {
            /* The game says when, the choice says what: its effect on is the
             * chosen one on, its effect off is off. */
            if (!p->trigger_following[side])
            {
                p->trigger_following[side] = true;
                pad_log("observed: the game sets its own %s effect on the %s; the chosen one takes its place, "
                        "on the game's timing\n", side ? "L2" : "R2", p->model);
            }
            p->trigger_game_on[side] = mode && mode != 0x05;
            if (report != copy) memcpy(copy, report, length);
            report = copy;
            if (p->trigger_game_on[side] && kind != TRIGGER_OFF)
                trigger_effect(kind, strength, p->trigger_step[side], report + 11 + 11 * side);
            else
            {
                memset(report + 11 + 11 * side, 0, 11);
                report[11 + 11 * side] = 0x05;
            }
            continue;
        }
        if (p->trigger_following[side] && !p->trigger_game_on[side]) continue;
        if (from_game && (report[1] & (4 << side)) && mode && mode != 0x05)
        {
            p->trigger_game[side] = true;
            pad_log("observed: the game sets its own %s effect on the %s; the chosen one stops\n",
                    side ? "L2" : "R2", p->model);
            continue;
        }
        if (kind == TRIGGER_OFF) continue;
        if (kind == TRIGGER_RUMBLE || kind == TRIGGER_RECOIL)
        {
            /* The motors' values only where the report sets them (see bt_queue_output). */
            if (!(report[1] & 0x01) && !(report[39] & 0x04)) continue;
            motor = kind == TRIGGER_RECOIL ? MAX(report[3], report[4]) : report[side ? 4 : 3];
            step = motor < 4 ? 0 : 1 + (motor - 4) * 8 / 252;
            if (step == p->trigger_step[side] ||
                mach_absolute_time() - p->trigger_at[side] < pad_ticks(0.060)) continue;
            p->trigger_step[side] = step;
            p->trigger_at[side] = mach_absolute_time();
        }
        else if (!(from_game && (report[1] & (4 << side)))) continue;
        if (report != copy) memcpy(copy, report, length);
        report = copy;
        report[1] |= 4 << side;
        trigger_effect(kind, strength, p->trigger_step[side], report + 11 + 11 * side);
    }
    return report;
}

// When the pad stops: the chosen effects are released, and their marker goes.
void pad_triggers_release(struct pad *p)
{
    uint8_t report[64] = {0x02};
    char path[64];

    if (!trigger_chosen(p, 0) && !trigger_chosen(p, 1)) return;
    report[1] = (trigger_chosen(p, 0) ? 0x04 : 0) | (trigger_chosen(p, 1) ? 0x08 : 0);
    report[11] = report[22] = 0x05;
    pad_write_output(p, report);
    trigger_marker(p, path, sizeof(path));
    unlink(path);
    pad_log("released the %s's triggers\n", p->model);
}
