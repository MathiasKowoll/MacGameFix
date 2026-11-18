/* Smoke probe: do the patched modules load on this Wine, and what do they show?
 * HID interfaces with their container (W and A, patch 0010), XInput slots, audio render
 * endpoints with their container (0002, 0003, 0009). */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <setupapi.h>
#include <devguid.h>
#include <hidsdi.h>
#include <xinput.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <stdio.h>
#ifndef SPDRP_BASE_CONTAINERID
#define SPDRP_BASE_CONTAINERID 0x24
#endif

DEFINE_GUID(PKEY_ContainerId_fmtid, 0x8c7ed206, 0x3f8a, 0x4827, 0xb3, 0xab, 0xae, 0x9e, 0x1f, 0xae, 0xfc, 0x6c);

int main(void)
{
    GUID hid; HDEVINFO set; SP_DEVICE_INTERFACE_DATA iface = {sizeof(iface)}; DWORD i;
    char buf[2048]; SP_DEVICE_INTERFACE_DETAIL_DATA_A *detail = (void *)buf; SP_DEVINFO_DATA dev = {sizeof(dev)};

    HidD_GetHidGuid(&hid);
    set = SetupDiGetClassDevsA(&hid, NULL, NULL, DIGCF_DEVICEINTERFACE | DIGCF_PRESENT);
    printf("HID interfaces:\n");
    for (i = 0; SetupDiEnumDeviceInterfaces(set, NULL, &hid, i, &iface); i++)
    {
        WCHAR cw[64] = {0}; char ca[128] = {0}; DWORD type = 0, size = 0;
        detail->cbSize = sizeof(*detail);
        if (!SetupDiGetDeviceInterfaceDetailA(set, &iface, detail, sizeof(buf), NULL, &dev)) continue;
        SetupDiGetDeviceRegistryPropertyW(set, &dev, SPDRP_BASE_CONTAINERID, &type, (BYTE *)cw, sizeof(cw), &size);
        SetupDiGetDeviceRegistryPropertyA(set, &dev, SPDRP_BASE_CONTAINERID, &type, (BYTE *)ca, sizeof(ca), &size);
        printf("  %s\n    container W=%ls  A-as-WCHAR=%ls (A size %lu)\n", detail->DevicePath, cw, (WCHAR *)ca, (unsigned long)size);
    }
    printf("  %lu found\n", (unsigned long)i);
    SetupDiDestroyDeviceInfoList(set);

    for (i = 0; i < 4; i++)
    {
        XINPUT_STATE st; DWORD r = XInputGetState(i, &st);
        printf("XInput slot %lu: %s\n", (unsigned long)i, r == ERROR_SUCCESS ? "connected" : r == ERROR_DEVICE_NOT_CONNECTED ? "empty" : "error");
    }

    {
        IMMDeviceEnumerator *en; IMMDeviceCollection *col; UINT n = 0, k;
        CoInitializeEx(NULL, COINIT_MULTITHREADED);
        if (SUCCEEDED(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &IID_IMMDeviceEnumerator, (void **)&en)) &&
            SUCCEEDED(IMMDeviceEnumerator_EnumAudioEndpoints(en, eRender, DEVICE_STATE_ACTIVE, &col)))
        {
            IMMDeviceCollection_GetCount(col, &n);
            printf("Audio render endpoints: %u\n", n);
            for (k = 0; k < n; k++)
            {
                IMMDevice *d; IPropertyStore *ps; PROPVARIANT name, cont; PROPERTYKEY ck = {PKEY_ContainerId_fmtid, 2};
                WCHAR g[64] = L"(none)";
                if (FAILED(IMMDeviceCollection_Item(col, k, &d))) continue;
                PropVariantInit(&name); PropVariantInit(&cont);
                if (SUCCEEDED(IMMDevice_OpenPropertyStore(d, STGM_READ, &ps)))
                {
                    IPropertyStore_GetValue(ps, &PKEY_Device_FriendlyName, &name);
                    if (SUCCEEDED(IPropertyStore_GetValue(ps, &ck, &cont)) && cont.vt == VT_CLSID) StringFromGUID2(cont.puuid, g, 64);
                    printf("  %ls  container %ls\n", name.vt == VT_LPWSTR ? name.pwszVal : L"?", g);
                    IPropertyStore_Release(ps);
                }
                IMMDevice_Release(d);
            }
        }
        else printf("Audio render endpoints: enumeration failed\n");
    }
    return 0;
}
