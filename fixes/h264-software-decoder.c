/* h264-software-decoder -- Microsoft's H.264 decoder MFT, as Unreal's Electra
 * needs it on macOS: system-memory NV12, no Direct3D.
 *
 * Installed as msmpeg2vdec.dll in the prefix's system32 and loaded native for
 * one executable through AppDefaults\<exe>\DllOverrides; every other program
 * in the prefix keeps CrossOver's builtin. It is CLSID_MSH264DecoderMFT's
 * server, exactly the class CrossOver's own msmpeg2vdec serves, and it makes
 * the same object that one does -- winegstreamer's wg_h264_decoder -- then
 * changes three answers on the way out:
 *
 * 1. MF_SA_D3D_AWARE and MF_SA_D3D11_AWARE read FALSE. winegstreamer sets both
 *    TRUE, and Electra then builds a D3D11 device for the decoder and expects
 *    frames as textures, which no macOS backend makes in NV12.
 * 2. MFT_MESSAGE_SET_D3D_MANAGER with a manager answers E_NOTIMPL, as a decoder
 *    that is not D3D aware does.
 * 3. NV12 is offered first. CrossOver skips it in GetOutputAvailableType on
 *    macOS (its CW HACK 26265), and Electra takes NV12 and nothing else: it
 *    logs "Failed to set video decoder output type to NV12" and the video
 *    stays black. SetOutputType still accepts NV12 -- the skip is only in the
 *    getter -- so the type is the YV12 one renamed: the two share the frame
 *    size, the stride and the image size, which is all the decoder writes in.
 *
 * Those are winevideo's patch 0006 to winegstreamer, applied at the COM
 * boundary instead of inside Wine: the engine stays CodeWeavers', and the same
 * DLL serves CrossOver 26.3 and Preview 27, whose decoder code is identical
 * here. Where a winegstreamer already offers NV12 (0006 in the engine), the
 * types pass through unchanged.
 *
 * Measured with 0006 itself in Phantom Blade Zero on 2026-11-01: the menu video
 * played from system-memory NV12 frames under D3DMetal. winevideo's 0008, which
 * makes the decoder hand out its own 2D samples, sent Electra down its D3D12
 * path, where CreatePlacedResource failed and the game closed; this DLL does
 * not do that.
 *
 * Log: C:\h264-software-decoder.log, a few lines per decoder.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>
#include <mfapi.h>
#include <mftransform.h>
#include <mferror.h>
#include <stdio.h>
#include <stdarg.h>

/* combaseapi.h declares both exports without dllexport. */
#ifdef __clang__
#pragma clang diagnostic ignored "-Wdll-attribute-on-redeclaration"
#endif

#define LOGFILE "C:\\h264-software-decoder.log"

DEFINE_GUID(CLSID_MSH264DecoderMFT_, 0x62ce7e72, 0x4c71, 0x4d20, 0xb1, 0x5d, 0x45, 0x28, 0x31, 0xa8, 0x7d, 0x9d);
DEFINE_GUID(CLSID_wg_h264_decoder, 0x1f1e273d, 0x12c0, 0x4b3a, 0x8e, 0x9b, 0x19, 0x33, 0xc2, 0x49, 0x8a, 0xea);
DEFINE_GUID(MF_SA_D3D11_AWARE_, 0x206b4fc8, 0xfcf9, 0x4c51, 0xaf, 0xe3, 0x97, 0x64, 0x36, 0x9e, 0x33, 0xa0);

static LONG objects;

static void say(const char *fmt, ...)
{
    char line[512];
    va_list args;
    SYSTEMTIME now;
    HANDLE file;
    DWORD written;
    int len;

    GetLocalTime(&now);
    len = snprintf(line, sizeof(line), "%02u:%02u:%02u.%03u [%lu] ", now.wHour, now.wMinute,
            now.wSecond, now.wMilliseconds, GetCurrentProcessId());
    va_start(args, fmt);
    len += vsnprintf(line + len, sizeof(line) - len - 2, fmt, args);
    va_end(args);
    if (len > (int)sizeof(line) - 2) len = sizeof(line) - 2;
    line[len++] = '\r';
    line[len++] = '\n';

    file = CreateFileA(LOGFILE, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;
    WriteFile(file, line, len, &written, NULL);
    CloseHandle(file);
}

struct decoder
{
    IMFTransform IMFTransform_iface;
    LONG refcount;
    IMFTransform *inner;
    LONG offered_nv12;  /* logged once */
};

static inline struct decoder *impl(IMFTransform *iface)
{
    return CONTAINING_RECORD(iface, struct decoder, IMFTransform_iface);
}

static HRESULT WINAPI decoder_QueryInterface(IMFTransform *iface, REFIID iid, void **out)
{
    struct decoder *decoder = impl(iface);

    if (IsEqualGUID(iid, &IID_IUnknown) || IsEqualGUID(iid, &IID_IMFTransform))
    {
        *out = iface;
        IMFTransform_AddRef(iface);
        return S_OK;
    }
    /* Anything else is the decoder's own; nothing Electra asks for. */
    return IMFTransform_QueryInterface(decoder->inner, iid, out);
}

static ULONG WINAPI decoder_AddRef(IMFTransform *iface)
{
    return InterlockedIncrement(&impl(iface)->refcount);
}

static ULONG WINAPI decoder_Release(IMFTransform *iface)
{
    struct decoder *decoder = impl(iface);
    ULONG refcount = InterlockedDecrement(&decoder->refcount);

    if (!refcount)
    {
        IMFTransform_Release(decoder->inner);
        HeapFree(GetProcessHeap(), 0, decoder);
        InterlockedDecrement(&objects);
    }
    return refcount;
}

static HRESULT WINAPI decoder_GetStreamLimits(IMFTransform *iface, DWORD *input_minimum,
        DWORD *input_maximum, DWORD *output_minimum, DWORD *output_maximum)
{
    return IMFTransform_GetStreamLimits(impl(iface)->inner, input_minimum, input_maximum,
            output_minimum, output_maximum);
}

static HRESULT WINAPI decoder_GetStreamCount(IMFTransform *iface, DWORD *inputs, DWORD *outputs)
{
    return IMFTransform_GetStreamCount(impl(iface)->inner, inputs, outputs);
}

static HRESULT WINAPI decoder_GetStreamIDs(IMFTransform *iface, DWORD input_size, DWORD *inputs,
        DWORD output_size, DWORD *outputs)
{
    return IMFTransform_GetStreamIDs(impl(iface)->inner, input_size, inputs, output_size, outputs);
}

static HRESULT WINAPI decoder_GetInputStreamInfo(IMFTransform *iface, DWORD id, MFT_INPUT_STREAM_INFO *info)
{
    return IMFTransform_GetInputStreamInfo(impl(iface)->inner, id, info);
}

static HRESULT WINAPI decoder_GetOutputStreamInfo(IMFTransform *iface, DWORD id, MFT_OUTPUT_STREAM_INFO *info)
{
    return IMFTransform_GetOutputStreamInfo(impl(iface)->inner, id, info);
}

/* winegstreamer hands out its own store, so the answer is written into it:
 * every reader then sees FALSE, the decoder included. */
static void not_d3d_aware(IMFAttributes *attributes)
{
    IMFAttributes_SetUINT32(attributes, &MF_SA_D3D_AWARE, FALSE);
    IMFAttributes_SetUINT32(attributes, &MF_SA_D3D11_AWARE_, FALSE);
}

static HRESULT WINAPI decoder_GetAttributes(IMFTransform *iface, IMFAttributes **attributes)
{
    HRESULT hr = IMFTransform_GetAttributes(impl(iface)->inner, attributes);

    if (SUCCEEDED(hr) && *attributes) not_d3d_aware(*attributes);
    return hr;
}

static HRESULT WINAPI decoder_GetInputStreamAttributes(IMFTransform *iface, DWORD id, IMFAttributes **attributes)
{
    return IMFTransform_GetInputStreamAttributes(impl(iface)->inner, id, attributes);
}

static HRESULT WINAPI decoder_GetOutputStreamAttributes(IMFTransform *iface, DWORD id, IMFAttributes **attributes)
{
    return IMFTransform_GetOutputStreamAttributes(impl(iface)->inner, id, attributes);
}

static HRESULT WINAPI decoder_DeleteInputStream(IMFTransform *iface, DWORD id)
{
    return IMFTransform_DeleteInputStream(impl(iface)->inner, id);
}

static HRESULT WINAPI decoder_AddInputStreams(IMFTransform *iface, DWORD streams, DWORD *ids)
{
    return IMFTransform_AddInputStreams(impl(iface)->inner, streams, ids);
}

static HRESULT WINAPI decoder_GetInputAvailableType(IMFTransform *iface, DWORD id, DWORD index, IMFMediaType **type)
{
    return IMFTransform_GetInputAvailableType(impl(iface)->inner, id, index, type);
}

static BOOL is_subtype(IMFMediaType *type, const GUID *subtype)
{
    GUID guid;
    return SUCCEEDED(IMFMediaType_GetGUID(type, &MF_MT_SUBTYPE, &guid)) && IsEqualGUID(&guid, subtype);
}

/* CrossOver's list on macOS reads YV12, YV12, IYUV, I420, YUY2: index 0 skips
 * NV12 into YV12, which index 1 then gives again. Ours reads NV12, YV12, IYUV,
 * I420, YUY2: index 0 is the first entry renamed, the rest are CrossOver's. */
static HRESULT WINAPI decoder_GetOutputAvailableType(IMFTransform *iface, DWORD id, DWORD index, IMFMediaType **type)
{
    struct decoder *decoder = impl(iface);
    IMFMediaType *first, *nv12 = NULL;
    HRESULT hr;

    if (index)
        return IMFTransform_GetOutputAvailableType(decoder->inner, id, index, type);

    if (FAILED(hr = IMFTransform_GetOutputAvailableType(decoder->inner, id, 0, &first)))
        return hr;
    if (is_subtype(first, &MFVideoFormat_NV12) || !is_subtype(first, &MFVideoFormat_YV12))
    {
        *type = first;  /* NV12 already offered, or a list this was not written for */
        return S_OK;
    }

    if (SUCCEEDED(hr = MFCreateMediaType(&nv12))
            && SUCCEEDED(hr = IMFMediaType_CopyAllItems(first, (IMFAttributes *)nv12))
            && SUCCEEDED(hr = IMFMediaType_SetGUID(nv12, &MF_MT_SUBTYPE, &MFVideoFormat_NV12)))
    {
        *type = nv12;
        if (!InterlockedExchange(&decoder->offered_nv12, 1))
            say("decoder %p: offering NV12 first", decoder);
    }
    else if (nv12)
        IMFMediaType_Release(nv12);
    IMFMediaType_Release(first);
    return hr;
}

static HRESULT WINAPI decoder_SetInputType(IMFTransform *iface, DWORD id, IMFMediaType *type, DWORD flags)
{
    return IMFTransform_SetInputType(impl(iface)->inner, id, type, flags);
}

static HRESULT WINAPI decoder_SetOutputType(IMFTransform *iface, DWORD id, IMFMediaType *type, DWORD flags)
{
    struct decoder *decoder = impl(iface);
    HRESULT hr = IMFTransform_SetOutputType(decoder->inner, id, type, flags);

    if (type && !(flags & MFT_SET_TYPE_TEST_ONLY))
        say("decoder %p: output type %s -> %#lx", decoder,
                is_subtype(type, &MFVideoFormat_NV12) ? "NV12" : "not NV12", hr);
    return hr;
}

static HRESULT WINAPI decoder_GetInputCurrentType(IMFTransform *iface, DWORD id, IMFMediaType **type)
{
    return IMFTransform_GetInputCurrentType(impl(iface)->inner, id, type);
}

static HRESULT WINAPI decoder_GetOutputCurrentType(IMFTransform *iface, DWORD id, IMFMediaType **type)
{
    return IMFTransform_GetOutputCurrentType(impl(iface)->inner, id, type);
}

static HRESULT WINAPI decoder_GetInputStatus(IMFTransform *iface, DWORD id, DWORD *flags)
{
    return IMFTransform_GetInputStatus(impl(iface)->inner, id, flags);
}

static HRESULT WINAPI decoder_GetOutputStatus(IMFTransform *iface, DWORD *flags)
{
    return IMFTransform_GetOutputStatus(impl(iface)->inner, flags);
}

static HRESULT WINAPI decoder_SetOutputBounds(IMFTransform *iface, LONGLONG lower, LONGLONG upper)
{
    return IMFTransform_SetOutputBounds(impl(iface)->inner, lower, upper);
}

static HRESULT WINAPI decoder_ProcessEvent(IMFTransform *iface, DWORD id, IMFMediaEvent *event)
{
    return IMFTransform_ProcessEvent(impl(iface)->inner, id, event);
}

static HRESULT WINAPI decoder_ProcessMessage(IMFTransform *iface, MFT_MESSAGE_TYPE message, ULONG_PTR param)
{
    struct decoder *decoder = impl(iface);

    if (message == MFT_MESSAGE_SET_D3D_MANAGER && param)
    {
        say("decoder %p: refused a D3D manager", decoder);
        return E_NOTIMPL;
    }
    return IMFTransform_ProcessMessage(decoder->inner, message, param);
}

static HRESULT WINAPI decoder_ProcessInput(IMFTransform *iface, DWORD id, IMFSample *sample, DWORD flags)
{
    return IMFTransform_ProcessInput(impl(iface)->inner, id, sample, flags);
}

static HRESULT WINAPI decoder_ProcessOutput(IMFTransform *iface, DWORD flags, DWORD count,
        MFT_OUTPUT_DATA_BUFFER *samples, DWORD *status)
{
    return IMFTransform_ProcessOutput(impl(iface)->inner, flags, count, samples, status);
}

static IMFTransformVtbl decoder_vtbl =
{
    decoder_QueryInterface,
    decoder_AddRef,
    decoder_Release,
    decoder_GetStreamLimits,
    decoder_GetStreamCount,
    decoder_GetStreamIDs,
    decoder_GetInputStreamInfo,
    decoder_GetOutputStreamInfo,
    decoder_GetAttributes,
    decoder_GetInputStreamAttributes,
    decoder_GetOutputStreamAttributes,
    decoder_DeleteInputStream,
    decoder_AddInputStreams,
    decoder_GetInputAvailableType,
    decoder_GetOutputAvailableType,
    decoder_SetInputType,
    decoder_SetOutputType,
    decoder_GetInputCurrentType,
    decoder_GetOutputCurrentType,
    decoder_GetInputStatus,
    decoder_GetOutputStatus,
    decoder_SetOutputBounds,
    decoder_ProcessEvent,
    decoder_ProcessMessage,
    decoder_ProcessInput,
    decoder_ProcessOutput,
};

static HRESULT WINAPI factory_QueryInterface(IClassFactory *iface, REFIID iid, void **out)
{
    if (IsEqualGUID(iid, &IID_IUnknown) || IsEqualGUID(iid, &IID_IClassFactory))
    {
        *out = iface;
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI factory_AddRef(IClassFactory *iface) { return 2; }
static ULONG WINAPI factory_Release(IClassFactory *iface) { return 1; }

static HRESULT WINAPI factory_CreateInstance(IClassFactory *iface, IUnknown *outer, REFIID iid, void **out)
{
    struct decoder *decoder;
    IMFAttributes *attributes;
    IMFTransform *inner;
    HRESULT hr;

    *out = NULL;
    if (outer) return CLASS_E_NOAGGREGATION;

    /* What CrossOver's msmpeg2vdec does, from wmvdecod's video_decoder.c. */
    if (FAILED(hr = CoCreateInstance(&CLSID_wg_h264_decoder, NULL, CLSCTX_INPROC_SERVER,
            &IID_IMFTransform, (void **)&inner)))
    {
        say("winegstreamer's H.264 decoder could not be created: %#lx", hr);
        return hr;
    }
    if (!(decoder = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*decoder))))
    {
        IMFTransform_Release(inner);
        return E_OUTOFMEMORY;
    }
    decoder->IMFTransform_iface.lpVtbl = &decoder_vtbl;
    decoder->refcount = 1;
    decoder->inner = inner;
    InterlockedIncrement(&objects);

    if (SUCCEEDED(IMFTransform_GetAttributes(inner, &attributes)))
    {
        not_d3d_aware(attributes);
        IMFAttributes_Release(attributes);
    }
    say("decoder %p made over winegstreamer's %p", decoder, inner);

    hr = IMFTransform_QueryInterface(&decoder->IMFTransform_iface, iid, out);
    IMFTransform_Release(&decoder->IMFTransform_iface);
    return hr;
}

static HRESULT WINAPI factory_LockServer(IClassFactory *iface, BOOL lock)
{
    if (lock) InterlockedIncrement(&objects);
    else InterlockedDecrement(&objects);
    return S_OK;
}

static IClassFactoryVtbl factory_vtbl =
{
    factory_QueryInterface,
    factory_AddRef,
    factory_Release,
    factory_CreateInstance,
    factory_LockServer,
};

static IClassFactory factory = {&factory_vtbl};

__declspec(dllexport) HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void **out)
{
    if (IsEqualGUID(clsid, &CLSID_MSH264DecoderMFT_))
        return IClassFactory_QueryInterface(&factory, iid, out);
    *out = NULL;
    return CLASS_E_CLASSNOTAVAILABLE;
}

__declspec(dllexport) HRESULT WINAPI DllCanUnloadNow(void)
{
    return objects ? S_FALSE : S_OK;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        char path[MAX_PATH];
        DisableThreadLibraryCalls(instance);
        if (!GetModuleFileNameA(NULL, path, sizeof(path))) lstrcpyA(path, "?");
        say("loaded into %s", path);
    }
    return TRUE;
}
