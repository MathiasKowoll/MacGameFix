/* A check for endpoints.c: the audio outputs SetupAPI lists.
 *
 * build-controls.sh runs it with a stand-in for a Bluetooth DualSense at location 00c0ffee, as it
 * runs mmdevapi.c. It has mmdevapi list the outputs, as a game's audio does before the game looks
 * for its pad's, then asks SetupAPI for the present audio render interfaces and each one's base
 * container id, as Nioh 3 does.
 * 0: one interface has {00C0FFEE-27F2-4948-9654-152804AF6378}, every interface has a container
 *    and a path \\?\SWD#MMDEVAPI#...
 * 2: no interface has that container (CodeWeavers' files with nothing done: SetupAPI lists no
 *    audio endpoint at all).
 * 1: something else went wrong; the line it prints says what.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <setupapi.h>
#include <stdio.h>

#ifndef SPDRP_BASE_CONTAINERID
#define SPDRP_BASE_CONTAINERID 0x24
#endif

DEFINE_GUID(render_interface, 0xe6327cad, 0xdcec, 0x4949, 0xae, 0x8a, 0x99, 0x1e, 0x97, 0x6a, 0x79, 0xd2);

int main(void)
{
    static const WCHAR wanted[] = L"{00C0FFEE-27F2-4948-9654-152804AF6378}", prefix[] = L"\\\\?\\SWD#MMDEVAPI#";
    SP_DEVICE_INTERFACE_DATA iface = {sizeof(iface)};
    IMMDeviceEnumerator *enumerator;
    IMMDeviceCollection *endpoints;
    DWORD i, found = 0, listed = 0;
    HDEVINFO set;

    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_INPROC_SERVER, &IID_IMMDeviceEnumerator,
                                (void **)&enumerator))
            || FAILED(IMMDeviceEnumerator_EnumAudioEndpoints(enumerator, eRender, DEVICE_STATE_ACTIVE, &endpoints)))
        return printf("the outputs could not be listed\n"), 1;

    set = SetupDiGetClassDevsW(&render_interface, NULL, NULL, DIGCF_DEVICEINTERFACE | DIGCF_PRESENT);
    if (set == INVALID_HANDLE_VALUE) return printf("SetupAPI gave no list: %lu\n", GetLastError()), 1;
    for (i = 0; SetupDiEnumDeviceInterfaces(set, NULL, &render_interface, i, &iface); i++)
    {
        union { SP_DEVICE_INTERFACE_DETAIL_DATA_W detail; BYTE bytes[1024]; } path;
        SP_DEVINFO_DATA device = {sizeof(device)};
        WCHAR container[64] = {0};

        path.detail.cbSize = sizeof(path.detail);
        if (!SetupDiGetDeviceInterfaceDetailW(set, &iface, &path.detail, sizeof(path), NULL, &device))
            return printf("interface %lu has no path: %lu\n", i, GetLastError()), 1;
        if (_wcsnicmp(path.detail.DevicePath, prefix, lstrlenW(prefix)))
            return printf("interface %lu is at %ls\n", i, path.detail.DevicePath), 1;
        if (!SetupDiGetDeviceRegistryPropertyW(set, &device, SPDRP_BASE_CONTAINERID, NULL, (BYTE *)container,
                                               sizeof(container), NULL) || container[0] != '{')
            return printf("interface %lu has no container: %lu\n", i, GetLastError()), 1;
        if (!lstrcmpiW(container, wanted)) found++;
        listed++;
    }
    SetupDiDestroyDeviceInfoList(set);
    IMMDeviceCollection_Release(endpoints);
    IMMDeviceEnumerator_Release(enumerator);
    CoUninitialize();

    if (found == 1) return printf("one of %lu audio outputs in SetupAPI has the pad's container\n", listed), 0;
    if (!found) return printf("none of %lu audio outputs in SetupAPI has the pad's container\n", listed), 2;
    return printf("%lu audio outputs in SetupAPI have the pad's container\n", found), 1;
}
