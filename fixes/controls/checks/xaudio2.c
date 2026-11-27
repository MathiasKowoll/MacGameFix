/* A check for xaudio2.c: the device a mastering voice opens when the game names one.
 *
 * build-controls.sh runs it with the stand-in for a Bluetooth DualSense at location 00c0ffee,
 * whose audio output has four channels where the Mac's own has two. It finds that output by its
 * container, names it to IXAudio2::CreateMasteringVoice by its audio render interface's path, as
 * Nioh 3 names its pad's, and asks the voice how many channels it has.
 * 0: the voice has the pad's output's channels: it opened the device that was named.
 * 3: the voice has the default output's channels: the name was ignored (CodeWeavers'
 *    xaudio2_9.dll with nothing done to it).
 * 2: no output has the pad's container (nothing done at all).
 * 1: something else went wrong, or both outputs have as many channels and the check cannot tell;
 *    the line it prints says what.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: LGPL-2.1-or-later */

#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <propsys.h>
#include <stdio.h>

DEFINE_GUID(wanted, 0x00c0ffee, 0x27f2, 0x4948, 0x96, 0x54, 0x15, 0x28, 0x04, 0xaf, 0x63, 0x78);
static const PROPERTYKEY container_key = {{0x8c7ed206, 0x3f8a, 0x4827, {0xb3, 0xab, 0xae, 0x9e, 0x1f, 0xae, 0xfc, 0x6c}}, 2};

/* XAudio2 2.9, as much of it as this needs: objects by their tables of methods. */
struct voice_details { UINT32 creation_flags, active_flags, channels, rate; };
typedef struct { void **methods; } object;
typedef HRESULT (WINAPI *create_fn)(object **xaudio2, UINT32 flags, UINT32 processor);
typedef HRESULT (WINAPI *mastering_voice_fn)(object *xaudio2, object **voice, UINT32 channels, UINT32 rate, UINT32 flags,
                                             const WCHAR *device, const void *effects, UINT32 category);
typedef void (WINAPI *details_fn)(object *voice, struct voice_details *details);

static int channels_of(IMMDevice *endpoint)
{
    IAudioClient *client;
    WAVEFORMATEX *format;
    int channels = 0;

    if (FAILED(IMMDevice_Activate(endpoint, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client))) return 0;
    if (SUCCEEDED(IAudioClient_GetMixFormat(client, &format)))
    {
        channels = format->nChannels;
        CoTaskMemFree(format);
    }
    IAudioClient_Release(client);
    return channels;
}

int main(void)
{
    IMMDeviceEnumerator *enumerator;
    IMMDeviceCollection *endpoints;
    IMMDevice *endpoint;
    struct voice_details details = {0};
    WCHAR path[256] = {0}, *id;
    int pad_channels = 0, default_channels = 0;
    object *xaudio2, *voice;
    create_fn create;
    UINT count = 0, i;
    HMODULE module;

    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_INPROC_SERVER, &IID_IMMDeviceEnumerator,
                                (void **)&enumerator))
            || FAILED(IMMDeviceEnumerator_EnumAudioEndpoints(enumerator, eRender, DEVICE_STATE_ACTIVE, &endpoints)))
        return printf("the outputs could not be listed\n"), 1;
    IMMDeviceCollection_GetCount(endpoints, &count);
    for (i = 0; i < count && !path[0]; i++)
    {
        IPropertyStore *store;
        PROPVARIANT value;

        if (FAILED(IMMDeviceCollection_Item(endpoints, i, &endpoint))) continue;
        PropVariantInit(&value);
        if (SUCCEEDED(IMMDevice_OpenPropertyStore(endpoint, STGM_READ, &store)))
        {
            if (SUCCEEDED(IPropertyStore_GetValue(store, &container_key, &value)) && value.vt == VT_CLSID
                    && IsEqualGUID(value.puuid, &wanted) && SUCCEEDED(IMMDevice_GetId(endpoint, &id)))
            {
                swprintf(path, 256, L"\\\\?\\SWD#MMDEVAPI#%ls#{e6327cad-dcec-4949-ae8a-991e976a79d2}", id);
                CoTaskMemFree(id);
                pad_channels = channels_of(endpoint);
            }
            PropVariantClear(&value);
            IPropertyStore_Release(store);
        }
        IMMDevice_Release(endpoint);
    }
    IMMDeviceCollection_Release(endpoints);
    if (!path[0]) return printf("none of %u outputs has the pad's container\n", count), 2;
    if (FAILED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(enumerator, eRender, eConsole, &endpoint)))
        return printf("there is no default output\n"), 1;
    default_channels = channels_of(endpoint);
    IMMDevice_Release(endpoint);
    IMMDeviceEnumerator_Release(enumerator);
    if (!pad_channels || pad_channels == default_channels)
        return printf("the pad's output has %d channels and the default one %d: the check cannot tell them apart\n",
                      pad_channels, default_channels), 1;

    if (!(module = LoadLibraryA("xaudio2_9.dll")) || !(create = (create_fn)GetProcAddress(module, "XAudio2Create")))
        return printf("no XAudio2Create\n"), 1;
    if (FAILED(create(&xaudio2, 0, 1 /* XAUDIO2_DEFAULT_PROCESSOR */)))
        return printf("XAudio2Create failed\n"), 1;
    /* IXAudio2::CreateMasteringVoice is the eighth method; IXAudio2Voice::GetVoiceDetails the first. */
    if (FAILED(((mastering_voice_fn)xaudio2->methods[7])(xaudio2, &voice, 0, 0, 0, path, NULL, 0)))
        return printf("the mastering voice could not be created on %ls\n", path), 1;
    ((details_fn)voice->methods[0])(voice, &details);

    if ((int)details.channels == pad_channels)
        return printf("the voice has %u channels, the pad's output's\n", details.channels), 0;
    if ((int)details.channels == default_channels)
        return printf("the voice has %u channels, the default output's: the name was ignored\n", details.channels), 3;
    return printf("the voice has %u channels, neither output's (%d, %d)\n", details.channels, pad_channels,
                  default_channels), 1;
}
