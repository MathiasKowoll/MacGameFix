/* A check for container.c: the container stored for a USB device.
 *
 * It makes device keys of its own under Enum and stores a base container id for each as ntoskrnl
 * does, with SetupDiSetDeviceRegistryPropertyW, then reads the value back from the key.
 * The first is named as CodeWeavers' winebus.sys names a device on the IOHID bus, with the hash of
 * the bus's name and a location (USB\MGFCHECK\1&e06fec9a&0&14200000), and is given the container
 * that winebus.sys answers, which starts with the same hash.
 * 0: that one was stored as the location's container, {14200000-27F2-4948-9654-152804AF6378}, and
 *    the others as they were given: a container that does not start with the hash, a device with
 *    no location, a device that is not on the USB bus.
 * 2: the first was stored as given (CodeWeavers' files with nothing done).
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

static const WCHAR from_hash[] = L"{E06FEC9A-1111-2222-3333-444444444444}";
static const WCHAR from_location[] = L"{14200000-27F2-4948-9654-152804AF6378}";
static const WCHAR another[] = L"{11111111-2222-3333-4444-555555555555}";

/* Stores `container` for the device and gives what the key then holds. */
static int stored(const WCHAR *instance, const WCHAR *container, WCHAR *got, DWORD got_size)
{
    SP_DEVINFO_DATA device = {sizeof(device)};
    WCHAR path[256];
    DWORD type, size = got_size;
    HDEVINFO set;
    HKEY key;
    LONG err;

    swprintf(path, 256, L"System\\CurrentControlSet\\Enum\\%ls", instance);
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, path, 0, NULL, 0, KEY_ALL_ACCESS, NULL, &key, NULL))
        return printf("the key of %ls could not be made\n", instance), 0;
    set = SetupDiCreateDeviceInfoList(NULL, NULL);
    if (set == INVALID_HANDLE_VALUE || !SetupDiOpenDeviceInfoW(set, instance, NULL, 0, &device))
        return printf("%ls could not be opened: %lu\n", instance, GetLastError()), 0;
    if (!SetupDiSetDeviceRegistryPropertyW(set, &device, SPDRP_BASE_CONTAINERID, (const BYTE *)container,
                                           (lstrlenW(container) + 1) * sizeof(WCHAR)))
        return printf("the container of %ls could not be stored: %lu\n", instance, GetLastError()), 0;
    SetupDiDestroyDeviceInfoList(set);
    err = RegQueryValueExW(key, L"ContainerId", NULL, &type, (BYTE *)got, &size);
    RegCloseKey(key);
    RegDeleteTreeW(HKEY_LOCAL_MACHINE, path);
    if (err || type != REG_SZ) return printf("%ls has no container stored\n", instance), 0;
    return 1;
}

int main(void)
{
    static const struct { const WCHAR *instance, *container; } as_given[] = {
        {L"USB\\MGFCHECK\\1&e06fec9a&0&14200000", another},      /* not winebus.sys's answer */
        {L"USB\\MGFCHECK\\1&e06fec9a&0&14200000", from_location}, /* the Wine modules' answer */
        {L"USB\\MGFCHECK\\1&e06fec9a&0&0", from_hash},            /* no location */
        {L"HID\\MGFCHECK\\1&e06fec9a&0&14200000", from_hash},     /* not on the USB bus */
        {L"USB\\MGFCHECK\\2&e06fec9a&0&0000", from_hash},         /* a child's instance id */
    };
    WCHAR got[64], first[64];
    unsigned i;

    if (!stored(L"USB\\MGFCHECK\\1&e06fec9a&0&14200000", from_hash, first, sizeof(first))) return 1;
    for (i = 0; i < sizeof(as_given) / sizeof(as_given[0]); i++)
    {
        if (!stored(as_given[i].instance, as_given[i].container, got, sizeof(got))) return 1;
        if (lstrcmpW(got, as_given[i].container))
            return printf("%ls was given %ls and holds %ls\n", as_given[i].instance, as_given[i].container, got), 1;
    }
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, L"System\\CurrentControlSet\\Enum\\USB\\MGFCHECK");
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, L"System\\CurrentControlSet\\Enum\\HID\\MGFCHECK");

    if (!lstrcmpW(first, from_location))
        return printf("the container is the location's, the others as given\n"), 0;
    if (!lstrcmpW(first, from_hash))
        return printf("the container is stored as winebus.sys gave it\n"), 2;
    return printf("the container is neither: %ls\n", first), 1;
}
