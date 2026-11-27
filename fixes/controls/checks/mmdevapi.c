/* A check for mmdevapi.c: the container an active audio output's property store gives.
 *
 * build-controls.sh runs it with a stand-in for a Bluetooth DualSense at location 00c0ffee (a
 * socket where the library looks for pads), which the library lists as a USB audio output.
 * It asks every active render endpoint for DEVPKEY_Device_ContainerId and for its name.
 * 0: one endpoint gave {00C0FFEE-27F2-4948-9654-152804AF6378} as VT_CLSID, every other endpoint
 *    gave nothing or a GUID, and every endpoint gave its name as text.
 * 2: no endpoint gave that container (CodeWeavers' files with nothing done: no such output is
 *    listed, and mmdevapi.dll never asks the driver).
 * 1: something else went wrong; the line it prints says what.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <propsys.h>
#include <stdio.h>

DEFINE_GUID(wanted, 0x00c0ffee, 0x27f2, 0x4948, 0x96, 0x54, 0x15, 0x28, 0x04, 0xaf, 0x63, 0x78);
static const PROPERTYKEY container_key = {{0x8c7ed206, 0x3f8a, 0x4827, {0xb3, 0xab, 0xae, 0x9e, 0x1f, 0xae, 0xfc, 0x6c}}, 2};
static const PROPERTYKEY name_key = {{0xa45c254e, 0xdf1c, 0x4efd, {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}}, 14};

int main(void)
{
    IMMDeviceEnumerator *enumerator;
    IMMDeviceCollection *endpoints;
    UINT count = 0, i, found = 0;

    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_INPROC_SERVER, &IID_IMMDeviceEnumerator,
                                (void **)&enumerator)))
        return printf("no device enumerator\n"), 1;
    if (FAILED(IMMDeviceEnumerator_EnumAudioEndpoints(enumerator, eRender, DEVICE_STATE_ACTIVE, &endpoints)))
        return printf("the outputs could not be listed\n"), 1;
    IMMDeviceCollection_GetCount(endpoints, &count);
    for (i = 0; i < count; i++)
    {
        IPropertyStore *store;
        IMMDevice *endpoint;
        PROPVARIANT value;

        if (FAILED(IMMDeviceCollection_Item(endpoints, i, &endpoint))
                || FAILED(IMMDevice_OpenPropertyStore(endpoint, STGM_READ, &store)))
            return printf("output %u could not be opened\n", i), 1;

        PropVariantInit(&value);
        if (FAILED(IPropertyStore_GetValue(store, &name_key, &value)) || value.vt != VT_LPWSTR)
            return printf("output %u has no name as text\n", i), 1;
        PropVariantClear(&value);

        if (FAILED(IPropertyStore_GetValue(store, &container_key, &value)))
            return printf("output %u: the container could not be asked\n", i), 1;
        if (value.vt == VT_CLSID && IsEqualGUID(value.puuid, &wanted)) found++;
        else if (value.vt != VT_EMPTY && value.vt != VT_CLSID)
            return printf("output %u: the container came back as type %u\n", i, value.vt), 1;
        PropVariantClear(&value);

        IPropertyStore_Release(store);
        IMMDevice_Release(endpoint);
    }
    IMMDeviceCollection_Release(endpoints);
    IMMDeviceEnumerator_Release(enumerator);
    CoUninitialize();

    if (found == 1) return printf("one of %u outputs has the pad's container\n", count), 0;
    if (!found) return printf("none of %u outputs has the pad's container\n", count), 2;
    return printf("%u outputs have the pad's container\n", found), 1;
}
