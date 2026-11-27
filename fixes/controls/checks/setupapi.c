/* A check for setupapi.c: a device's base container id read with the ANSI function.
 *
 * It makes a device key of its own under Enum (ROOT\MGFCHECK\0000) with a base container id and a
 * description, opens it through SetupAPI and reads both with SetupDiGetDeviceRegistryPropertyA.
 * 0: the container came back as WCHAR, as on Windows, and the description as ANSI.
 * 2: the container came back as ANSI (CodeWeavers' setupapi.dll with nothing done to it).
 * 1: something else went wrong; the line it prints says what.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#include <windows.h>
#include <setupapi.h>
#include <stdio.h>

#ifndef SPDRP_BASE_CONTAINERID
#define SPDRP_BASE_CONTAINERID 0x24
#endif

static const char path[] = "System\\CurrentControlSet\\Enum\\ROOT\\MGFCHECK\\0000";
static const WCHAR container[] = L"{11111111-2222-3333-4444-555555555555}";

int main(void)
{
    SP_DEVINFO_DATA device = {sizeof(device)};
    BYTE ansi[128] = {0}, wide[128] = {0}, text[64] = {0};
    DWORD type, size;
    HDEVINFO set;
    HKEY key;

    if (RegCreateKeyExA(HKEY_LOCAL_MACHINE, path, 0, NULL, 0, KEY_ALL_ACCESS, NULL, &key, NULL))
        return printf("the device's key could not be made\n"), 1;
    RegSetValueExW(key, L"ContainerId", 0, REG_SZ, (const BYTE *)container, sizeof(container));
    RegSetValueExA(key, "DeviceDesc", 0, REG_SZ, (const BYTE *)"Check", 6);
    RegCloseKey(key);

    set = SetupDiCreateDeviceInfoList(NULL, NULL);
    if (set == INVALID_HANDLE_VALUE || !SetupDiOpenDeviceInfoA(set, "ROOT\\MGFCHECK\\0000", NULL, 0, &device))
        return printf("the device could not be opened: %lu\n", GetLastError()), 1;

    if (!SetupDiGetDeviceRegistryPropertyA(set, &device, SPDRP_BASE_CONTAINERID, &type, ansi, sizeof(ansi), &size))
        return printf("the container could not be read with the A function: %lu\n", GetLastError()), 1;
    if (!SetupDiGetDeviceRegistryPropertyW(set, &device, SPDRP_BASE_CONTAINERID, &type, wide, sizeof(wide), &size)
            || memcmp(wide, container, sizeof(container)))
        return printf("the W function does not give the container\n"), 1;
    if (!SetupDiGetDeviceRegistryPropertyA(set, &device, SPDRP_DEVICEDESC, &type, text, sizeof(text), &size)
            || strcmp((const char *)text, "Check"))
        return printf("the description is not ANSI from the A function\n"), 1;
    SetupDiDestroyDeviceInfoList(set);
    RegDeleteKeyA(HKEY_LOCAL_MACHINE, path);

    if (!memcmp(ansi, container, sizeof(container)))
        return printf("the container is WCHAR from the A function, the description ANSI\n"), 0;
    if (!strcmp((const char *)ansi, "{11111111-2222-3333-4444-555555555555}"))
        return printf("the container is ANSI from the A function\n"), 2;
    return printf("the container is neither\n"), 1;
}
