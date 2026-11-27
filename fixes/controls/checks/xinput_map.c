/* A check for xinput_map.h, run on the Mac itself by build-controls.sh: a DualSense's report
 * values in, what Wine's xinput has to be given out.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#include <stdio.h>
#include "../xinput_map.h"

static int failed;
#define IS(what, got, want) do { if ((got) != (want)) { printf("  FAIL  xinput_map: %s is %u, not %u\n", what, (unsigned)(got), (unsigned)(want)); failed = 1; } } while (0)

int main(void) {
    /* Wine asks for the right stick on Rx and Ry and the triggers on Z and Rz. */
    IS("the axis for Rx", sony_axis(HID_USAGE_RX), HID_USAGE_Z);
    IS("the axis for Ry", sony_axis(HID_USAGE_RY), HID_USAGE_RZ);
    IS("the axis for Z", sony_axis(HID_USAGE_Z), HID_USAGE_RX);
    IS("the axis for Rz", sony_axis(HID_USAGE_RZ), HID_USAGE_RY);
    IS("the axis for X", sony_axis(HID_USAGE_X), HID_USAGE_X);
    IS("the axis for Y", sony_axis(HID_USAGE_Y), HID_USAGE_Y);
    IS("the hat's usage", sony_axis(HID_USAGE_HAT), HID_USAGE_HAT);
    IS("Y turned", sony_axis_turned(HID_USAGE_Y), 1);
    IS("Ry turned", sony_axis_turned(HID_USAGE_RY), 1);
    IS("X turned", sony_axis_turned(HID_USAGE_X), 0);
    IS("Z turned", sony_axis_turned(HID_USAGE_Z), 0);
    /* A stick pushed up reads 0 on a DualSense and has to read the top of the range. */
    IS("a stick up", sony_turned(0, 0, 255), 255);
    IS("a stick down", sony_turned(255, 0, 255), 0);
    IS("a stick at rest", sony_turned(128, 0, 255), 127);
    IS("a value out of range", sony_turned(300, 0, 255), 300);
    /* Cross is A, Circle B, Square X, Triangle Y. */
    IS("Square", sony_button(1), 3);
    IS("Cross", sony_button(2), 1);
    IS("Circle", sony_button(3), 2);
    IS("Triangle", sony_button(4), 4);
    IS("L1", sony_button(5), 5);
    IS("R1", sony_button(6), 6);
    IS("L2", sony_button(7), 0);
    IS("R2", sony_button(8), 0);
    IS("Create", sony_button(9), 7);
    IS("Options", sony_button(10), 8);
    IS("L3", sony_button(11), 9);
    IS("R3", sony_button(12), 10);
    IS("PS", sony_button(13), 0);
    IS("the touchpad", sony_button(14), 0);
    IS("mute", sony_button(15), 0);
    IS("no button", sony_button(0), 0);
    /* The hat: 0 is up on a DualSense and 1 for Wine; 8 is centred and 0 for Wine. */
    IS("the hat up", sony_hat(0, 0, 7), 1);
    IS("the hat up and left", sony_hat(7, 0, 7), 8);
    IS("the hat centred", sony_hat(8, 0, 7), 0);
    IS("a hat with no range", sony_hat(3, 0, 0), 0);
    if (!failed) printf("  ok    xinput_map: a Sony pad's axes, buttons and hat as Wine's xinput reads them\n");
    return failed;
}
