/* A check for xinput.c's hold on hid.dll: its five exports that are pointed at the library still
 * answer a caller that is not xinput as hid.dll itself does.
 *
 * It asks each of them something hid.dll refuses (a handle that is no device, parsed data that is
 * none) and has to get hid.dll's own refusal: with the library and without it, exit 0. The
 * translation itself needs a Sony pad that xinput has open, which no check has: xinput_map.c
 * checks its arithmetic, and a game its use.
 * 1: an answer was not hid.dll's; the line it prints says which.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#include <windows.h>
#include <hidsdi.h>
#include <stdio.h>

#ifndef HIDP_STATUS_INVALID_PREPARSED_DATA
#define HIDP_STATUS_INVALID_PREPARSED_DATA ((NTSTATUS)0xC0110001)
#endif

int main(void)
{
    char none[256] = {0}, report[64] = {0};
    PHIDP_PREPARSED_DATA parsed = (PHIDP_PREPARSED_DATA)none, got = NULL;
    HIDP_VALUE_CAPS caps[4];
    USHORT caps_count = 4;
    USAGE usages[8];
    ULONG usage_count = 8, value = 0;
    NTSTATUS status;

    if (HidD_GetPreparsedData(INVALID_HANDLE_VALUE, &got))
        return printf("HidD_GetPreparsedData gave parsed data for no device\n"), 1;
    if ((status = HidP_GetValueCaps(HidP_Input, caps, &caps_count, parsed)) != HIDP_STATUS_INVALID_PREPARSED_DATA)
        return printf("HidP_GetValueCaps answered %#lx\n", (unsigned long)status), 1;
    if ((status = HidP_GetUsageValue(HidP_Input, 1, 0, 0x30, &value, parsed, report, sizeof(report)))
            != HIDP_STATUS_INVALID_PREPARSED_DATA)
        return printf("HidP_GetUsageValue answered %#lx\n", (unsigned long)status), 1;
    if ((status = HidP_GetUsages(HidP_Input, 9, 0, usages, &usage_count, parsed, report, sizeof(report)))
            != HIDP_STATUS_INVALID_PREPARSED_DATA)
        return printf("HidP_GetUsages answered %#lx\n", (unsigned long)status), 1;
    if (!HidD_FreePreparsedData(NULL))
        return printf("HidD_FreePreparsedData refused nothing to free\n"), 1;
    printf("hid.dll refuses what is no device and no parsed data, as itself\n");
    return 0;
}
