/*
 * mk11-face-fix.c -- Mortal Kombat 11: dark smeared patches on bare faces.
 *
 * WHAT IT FIXES. On this Mac the skin of every fighter whose face is uncovered
 * -- the forehead, the brows, around the eyes -- turns into smeared dark
 * patches with hard edges, which follow the light and change from frame to
 * frame. A face is clean right after a screen loads and breaks as soon as it
 * starts to animate; it is worst in close views, the character select and the
 * fatalities. Masked fighters never show it. It is the same on D3DMetal
 * (MK11_DX12.exe) and on DXMT (MK11.exe, DirectX 11), at every graphics setting.
 *
 * WHERE IT COMES FROM. A face's expression is a set of morph targets: for each
 * one, a compute pass (cs_9f038ca4, or cs_b947e8cb without a mask) adds
 * PositionDeltas[i] * Weight to the vertices it moves. The deltas are read as
 * elements of a DXGI_FORMAT_R32G32B32_FLOAT buffer view. Metal has no
 * three-float texel format, and D3DMetal serves such a view as if it held two
 * floats an element: element i of a view starting at element F comes back as
 * the floats 2F+2i and 2F+2i+1 with z = 0, where D3D12 gives 3F+3i, 3F+3i+1 and
 * 3F+3i+2 (measured on the game's own device, Game Porting Toolkit 4.0b3). DXMT
 * serves it as one float an element (read from its source). So every
 * expression moves every vertex by a small wrong amount. The face keeps
 * roughly its shape, but the tangent frame the game recomputes from it after
 * the morph (cs_cb994f68, cs_6f7a24b6) turns the errors into the patches.
 *
 * WHAT IT DOES. Every R32G32B32_FLOAT buffer shader resource view is created as
 * an R32_FLOAT view three times as long, which both translators read correctly,
 * and the morph shaders read the three floats of a delta one by one. Under
 * DirectX 12 the two are replaced by rewrites (fixes/mk11-morph/, built into
 * mk11-morph-shaders.h); under DirectX 11 the game's own bytecode is edited as
 * it is handed over -- the one load from PositionDeltas becomes three
 * (rgb32-loads.c) -- so a morph shader is found by its resources, not by a hash.
 * Their arithmetic is the game's. Nothing is skipped. The game's other shaders that
 * read three-float buffers are its geometry caches (17 of them); they are not
 * rewritten. A game update that changes either morph shader makes the
 * replacement match nothing; the log then says no morph pipeline was replaced.
 *
 * THE MOVIES ride along: grey pictures with purple and green bands, and choppy
 * motion, from CrossOver's H.264 decoder. mk11-movie.c, included below, has why
 * and what it does; it hooks the executable's import of CoCreateInstance.
 *
 * WHERE IT HOOKS. MK11_DX12.exe imports d3d12.dll's D3D12CreateDevice by ordinal
 * (101), MK11.exe d3d11.dll's D3D11CreateDevice by name, and the executable's
 * import slot is pointed here. AMD's library can also create the DirectX 11
 * device, loading d3d11.dll itself; so if the game's device has not been seen
 * three seconds after load, a device of this DLL's own reaches the same class,
 * and the class-level patch covers the game's too. Carried on amd_ags_x64.dll,
 * which both executables import; every export is forwarded to the renamed
 * original (fixes/build-proxy.sh). Logs to mk11-face-fix.log beside itself.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <d3d11_3.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sm2fix_core.h"
#include "sm2fix_core.c"
#include "mk11-morph-shaders.h"
#include "dxbc-checksum.c"
#include "rgb32-loads.c"

#define LOG_NAME "mk11-face-fix.log"
#define DEV_IDX(m) (offsetof(ID3D12Device8Vtbl, m) / sizeof(void *))
#define DEV11_IDX(m) (offsetof(ID3D11Device3Vtbl, m) / sizeof(void *))

/* The game's two face morph shaders (vkd3d-proton's shader hash) and what replaces them. */
static const struct { unsigned long long hash; const void *code; SIZE_T len; } morphs[] = {
    { 0x9f038ca4c3a6eb7aULL, mk11_morph_9f038ca4, sizeof(mk11_morph_9f038ca4) },
    { 0xb947e8cbb6ef2fd9ULL, mk11_morph_b947e8cb, sizeof(mk11_morph_b947e8cb) },
};

static CRITICAL_SECTION cs;
static FILE *logf;
static LONG device_seen, views_made, morphs_replaced, morphs_refused;

static void log_msg(const char *fmt, ...)
{
    va_list ap;
    SYSTEMTIME t;
    if (!logf) return;
    GetLocalTime(&t);
    EnterCriticalSection(&cs);
    fprintf(logf, "%02d:%02d:%02d ", t.wHour, t.wMinute, t.wSecond);
    va_start(ap, fmt); vfprintf(logf, fmt, ap); va_end(ap);
    fputc('\n', logf); fflush(logf);
    LeaveCriticalSection(&cs);
}

/* The rewrite of this shader, or NULL if it is not one of the two. */
static const void *morph_rewrite(const void *code, SIZE_T len, SIZE_T *out_len)
{
    unsigned long long h;
    size_t i;
    if (!code || len < 32) return NULL;
    h = sm2_shader_hash(code, len);
    for (i = 0; i < ARRAYSIZE(morphs); i++)
        if (morphs[i].hash == h) { *out_len = morphs[i].len; return morphs[i].code; }
    return NULL;
}

static void note_morph(const void *code, SIZE_T len, HRESULT hr)
{
    if (SUCCEEDED(hr)) InterlockedIncrement(&morphs_replaced);
    else InterlockedIncrement(&morphs_refused);
    log_msg("face morph shader %016llx: %s", (unsigned long long)sm2_shader_hash(code, len),
            SUCCEEDED(hr) ? "replaced" : "the rewrite was REFUSED, the game's own is used");
}

/* ---- vtable hooks ---------------------------------------------------------- */
static struct { void **vtbl; unsigned int index; void *orig; } hooks[32];
static unsigned int hook_n;
static SRWLOCK hook_lock = SRWLOCK_INIT;

static void *orig_fn(void *obj, unsigned int index)
{
    void **vtbl = *(void ***)obj, *fn = NULL;
    unsigned int i;
    AcquireSRWLockShared(&hook_lock);
    for (i = 0; i < hook_n; i++)
        if (hooks[i].vtbl == vtbl && hooks[i].index == index) fn = hooks[i].orig;
    ReleaseSRWLockShared(&hook_lock);
    return fn;
}

static void hook_slot(void *obj, unsigned int index, void *hook)
{
    void **vtbl = *(void ***)obj;
    DWORD old;
    unsigned int i;
    AcquireSRWLockExclusive(&hook_lock);
    for (i = 0; i < hook_n; i++)
        if (hooks[i].vtbl == vtbl && hooks[i].index == index) goto done;
    if (hook_n == ARRAYSIZE(hooks) || !vtbl[index] || vtbl[index] == hook
            || !VirtualProtect(&vtbl[index], sizeof(void *), PAGE_READWRITE, &old))
        goto done;
    hooks[hook_n].vtbl = vtbl;
    hooks[hook_n].index = index;
    hooks[hook_n].orig = vtbl[index];
    hook_n++;
    vtbl[index] = hook;
    VirtualProtect(&vtbl[index], sizeof(void *), old, &old);
done:
    ReleaseSRWLockExclusive(&hook_lock);
}

/* ---- three-float buffer views ------------------------------------------------ */
static void STDMETHODCALLTYPE hk_CreateShaderResourceView(ID3D12Device *dev, ID3D12Resource *res,
        const D3D12_SHADER_RESOURCE_VIEW_DESC *desc, D3D12_CPU_DESCRIPTOR_HANDLE h)
{
    void (STDMETHODCALLTYPE *orig)(ID3D12Device *, ID3D12Resource *, const D3D12_SHADER_RESOURCE_VIEW_DESC *,
            D3D12_CPU_DESCRIPTOR_HANDLE) = orig_fn(dev, DEV_IDX(CreateShaderResourceView));
    if (desc && desc->ViewDimension == D3D12_SRV_DIMENSION_BUFFER && desc->Format == DXGI_FORMAT_R32G32B32_FLOAT
            && !(desc->Buffer.Flags & D3D12_BUFFER_SRV_FLAG_RAW))
    {
        D3D12_SHADER_RESOURCE_VIEW_DESC one = *desc;
        one.Format = DXGI_FORMAT_R32_FLOAT;
        one.Buffer.FirstElement = desc->Buffer.FirstElement * 3;
        one.Buffer.NumElements = desc->Buffer.NumElements * 3;
        InterlockedIncrement(&views_made);
        orig(dev, res, &one, h);
        return;
    }
    orig(dev, res, desc, h);
}

/* ---- pipelines ------------------------------------------------------------- */
static HRESULT STDMETHODCALLTYPE hk_CreateComputePipelineState(ID3D12Device *dev,
        const D3D12_COMPUTE_PIPELINE_STATE_DESC *desc, REFIID riid, void **pso)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12Device *, const D3D12_COMPUTE_PIPELINE_STATE_DESC *, REFIID, void **)
            = orig_fn(dev, DEV_IDX(CreateComputePipelineState));
    SIZE_T alt_len;
    const void *alt = desc ? morph_rewrite(desc->CS.pShaderBytecode, desc->CS.BytecodeLength, &alt_len) : NULL;
    if (alt)
    {
        D3D12_COMPUTE_PIPELINE_STATE_DESC copy = *desc;
        HRESULT hr;
        copy.CS.pShaderBytecode = alt;
        copy.CS.BytecodeLength = alt_len;
        hr = orig(dev, &copy, riid, pso);
        note_morph(desc->CS.pShaderBytecode, desc->CS.BytecodeLength, hr);
        if (SUCCEEDED(hr)) return hr;
    }
    return orig(dev, desc, riid, pso);
}

static HRESULT STDMETHODCALLTYPE hk_CreatePipelineState(ID3D12Device2 *dev,
        const D3D12_PIPELINE_STATE_STREAM_DESC *desc, REFIID riid, void **pso)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12Device2 *, const D3D12_PIPELINE_STATE_STREAM_DESC *, REFIID, void **)
            = orig_fn(dev, DEV_IDX(CreatePipelineState));
    const void *code = NULL, *alt;
    size_t size = 0;
    SIZE_T alt_len;
    long at;
    if (desc && sm2_stream_find_cs(desc->pPipelineStateSubobjectStream, desc->SizeInBytes, &code, &size) == SM2_STREAM_COMPUTE
            && (alt = morph_rewrite(code, size, &alt_len))
            && (at = sm2_stream_cs_offset(desc->pPipelineStateSubobjectStream, desc->SizeInBytes)) >= 0)
    {
        BYTE *copy = malloc(desc->SizeInBytes);
        if (copy)
        {
            D3D12_PIPELINE_STATE_STREAM_DESC patched = *desc;
            UINT64 len = alt_len;
            HRESULT hr;
            memcpy(copy, desc->pPipelineStateSubobjectStream, desc->SizeInBytes);
            memcpy(copy + at + 8, &alt, sizeof(alt));
            memcpy(copy + at + 16, &len, sizeof(len));
            patched.pPipelineStateSubobjectStream = copy;
            hr = orig(dev, &patched, riid, pso);
            free(copy);
            note_morph(code, size, hr);
            if (SUCCEEDED(hr)) return hr;
        }
    }
    return orig(dev, desc, riid, pso);
}

/* ---- the device ------------------------------------------------------------ */
static void hook_device(ID3D12Device *dev)
{
    static const IID *ifaces[] = { &IID_ID3D12Device, &IID_ID3D12Device1, &IID_ID3D12Device2, &IID_ID3D12Device3,
        &IID_ID3D12Device4, &IID_ID3D12Device5, &IID_ID3D12Device6, &IID_ID3D12Device7, &IID_ID3D12Device8 };
    static LONG done;
    unsigned int i;
    InterlockedExchange(&device_seen, 1);
    if (InterlockedExchange(&done, 1)) return;
    for (i = 0; i < ARRAYSIZE(ifaces); i++)
    {
        IUnknown *it = NULL;
        if (FAILED(ID3D12Device_QueryInterface(dev, ifaces[i], (void **)&it)) || !it) continue;
        hook_slot(it, DEV_IDX(CreateShaderResourceView), (void *)hk_CreateShaderResourceView);
        hook_slot(it, DEV_IDX(CreateComputePipelineState), (void *)hk_CreateComputePipelineState);
        if (i >= 2) hook_slot(it, DEV_IDX(CreatePipelineState), (void *)hk_CreatePipelineState);
        IUnknown_Release(it);
    }
    log_msg("device %p hooked (%u slots)", dev, hook_n);
}

/* ---- DirectX 11 ------------------------------------------------------------ */
static BOOL is_rgb32_view11(DXGI_FORMAT format, D3D11_SRV_DIMENSION dim, UINT exflags)
{
    return format == DXGI_FORMAT_R32G32B32_FLOAT
        && (dim == D3D11_SRV_DIMENSION_BUFFER
            || (dim == D3D11_SRV_DIMENSION_BUFFEREX && !(exflags & D3D11_BUFFEREX_SRV_FLAG_RAW)));
}

static HRESULT STDMETHODCALLTYPE hk11_CreateShaderResourceView(ID3D11Device *dev, ID3D11Resource *res,
        const D3D11_SHADER_RESOURCE_VIEW_DESC *desc, ID3D11ShaderResourceView **view)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D11Device *, ID3D11Resource *, const D3D11_SHADER_RESOURCE_VIEW_DESC *,
            ID3D11ShaderResourceView **) = orig_fn(dev, DEV11_IDX(CreateShaderResourceView));
    if (desc && is_rgb32_view11(desc->Format, desc->ViewDimension, desc->BufferEx.Flags))
    {
        D3D11_SHADER_RESOURCE_VIEW_DESC one = *desc;
        one.Format = DXGI_FORMAT_R32_FLOAT;
        if (desc->ViewDimension == D3D11_SRV_DIMENSION_BUFFER)
        {
            one.Buffer.FirstElement = desc->Buffer.FirstElement * 3;
            one.Buffer.NumElements = desc->Buffer.NumElements * 3;
        }
        else
        {
            one.BufferEx.FirstElement = desc->BufferEx.FirstElement * 3;
            one.BufferEx.NumElements = desc->BufferEx.NumElements * 3;
        }
        InterlockedIncrement(&views_made);
        return orig(dev, res, &one, view);
    }
    return orig(dev, res, desc, view);
}

static HRESULT STDMETHODCALLTYPE hk11_CreateShaderResourceView1(ID3D11Device3 *dev, ID3D11Resource *res,
        const D3D11_SHADER_RESOURCE_VIEW_DESC1 *desc, ID3D11ShaderResourceView1 **view)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D11Device3 *, ID3D11Resource *, const D3D11_SHADER_RESOURCE_VIEW_DESC1 *,
            ID3D11ShaderResourceView1 **) = orig_fn(dev, DEV11_IDX(CreateShaderResourceView1));
    if (desc && is_rgb32_view11(desc->Format, desc->ViewDimension, desc->BufferEx.Flags))
    {
        D3D11_SHADER_RESOURCE_VIEW_DESC1 one = *desc;
        one.Format = DXGI_FORMAT_R32_FLOAT;
        if (desc->ViewDimension == D3D11_SRV_DIMENSION_BUFFER)
        {
            one.Buffer.FirstElement = desc->Buffer.FirstElement * 3;
            one.Buffer.NumElements = desc->Buffer.NumElements * 3;
        }
        else
        {
            one.BufferEx.FirstElement = desc->BufferEx.FirstElement * 3;
            one.BufferEx.NumElements = desc->BufferEx.NumElements * 3;
        }
        InterlockedIncrement(&views_made);
        return orig(dev, res, &one, view);
    }
    return orig(dev, res, desc, view);
}

/* A face morph: it reads PositionDeltas as a three-float buffer, and binds
 * SourceIndices and OutputPositions. The register of PositionDeltas, or -1. */
static int morph_deltas_register(const void *code, SIZE_T len)
{
    int reg = rdef_float3_buffer(code, len, "PositionDeltas");
    if (reg < 0) return -1;
    if (rdef_float3_buffer(code, len, "SourceIndices") == -1 || rdef_float3_buffer(code, len, "OutputPositions") == -1)
        return -1;
    return reg;
}

static HRESULT STDMETHODCALLTYPE hk11_CreateComputeShader(ID3D11Device *dev, const void *code, SIZE_T len,
        ID3D11ClassLinkage *linkage, ID3D11ComputeShader **shader)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D11Device *, const void *, SIZE_T, ID3D11ClassLinkage *,
            ID3D11ComputeShader **) = orig_fn(dev, DEV11_IDX(CreateComputeShader));
    int reg = code ? morph_deltas_register(code, len) : -1;
    if (reg >= 0)
    {
        size_t alt_len = 0;
        const char *why = NULL;
        void *alt = rgb32_rewrite(code, len, reg, &alt_len, &why);
        if (alt)
        {
            HRESULT hr = orig(dev, alt, alt_len, linkage, shader);
            free(alt);
            note_morph(code, len, hr);
            if (SUCCEEDED(hr)) return hr;
        }
        else
        {
            InterlockedIncrement(&morphs_refused);
            log_msg("face morph shader %016llx: not rewritten (%s), the game's own is used",
                    (unsigned long long)sm2_shader_hash(code, len), why);
        }
    }
    return orig(dev, code, len, linkage, shader);
}

static void hook_device11(ID3D11Device *dev)
{
    static LONG done;
    ID3D11Device3 *dev3 = NULL;
    InterlockedExchange(&device_seen, 1);
    if (InterlockedExchange(&done, 1)) return;
    hook_slot(dev, DEV11_IDX(CreateShaderResourceView), (void *)hk11_CreateShaderResourceView);
    hook_slot(dev, DEV11_IDX(CreateComputeShader), (void *)hk11_CreateComputeShader);
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_ID3D11Device3, (void **)&dev3)) && dev3)
    {
        hook_slot(dev3, DEV11_IDX(CreateShaderResourceView1), (void *)hk11_CreateShaderResourceView1);
        ID3D11Device3_Release(dev3);
    }
    log_msg("DirectX 11 device %p hooked (%u slots)", dev, hook_n);
}

typedef HRESULT (WINAPI *create_fn)(IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);
static create_fn real_create;

static HRESULT WINAPI mgvf_D3D12CreateDevice(IUnknown *adapter, D3D_FEATURE_LEVEL level, REFIID riid, void **out)
{
    HRESULT hr = real_create(adapter, level, riid, out);
    if (SUCCEEDED(hr) && out && *out)
    {
        ID3D12Device *dev = NULL;
        if (SUCCEEDED(IUnknown_QueryInterface((IUnknown *)*out, &IID_ID3D12Device, (void **)&dev)) && dev)
        {
            hook_device(dev);
            ID3D12Device_Release(dev);
        }
    }
    return hr;
}

/* The executable's import of D3D12CreateDevice, by name or by ordinal 101. */
static int redirect_exe_import(void)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    DWORD rva = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    IMAGE_IMPORT_DESCRIPTOR *imp;
    int n = 0;
    if (!rva) return 0;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + rva); imp->Name; ++imp)
    {
        IMAGE_THUNK_DATA *orig, *iat;
        if (lstrcmpiA((const char *)base + imp->Name, "d3d12.dll") != 0) continue;
        orig = (IMAGE_THUNK_DATA *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        iat = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
        for (; orig->u1.AddressOfData; ++orig, ++iat)
        {
            DWORD old;
            BOOL match = IMAGE_SNAP_BY_ORDINAL(orig->u1.Ordinal)
                ? IMAGE_ORDINAL(orig->u1.Ordinal) == 101
                : !lstrcmpA((const char *)((IMAGE_IMPORT_BY_NAME *)(base + orig->u1.AddressOfData))->Name,
                            "D3D12CreateDevice");
            if (!match || (void *)(ULONG_PTR)iat->u1.Function == (void *)mgvf_D3D12CreateDevice) continue;
            if (!VirtualProtect(&iat->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) continue;
            if (!real_create) real_create = (create_fn)(ULONG_PTR)iat->u1.Function;
            iat->u1.Function = (ULONG_PTR)mgvf_D3D12CreateDevice;
            VirtualProtect(&iat->u1.Function, sizeof(void *), old, &old);
            n++;
        }
    }
    return n;
}

typedef HRESULT (WINAPI *create11_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *,
        UINT, UINT, ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
static create11_fn real_create11;

static HRESULT WINAPI mgvf_D3D11CreateDevice(IDXGIAdapter *adapter, D3D_DRIVER_TYPE type, HMODULE sw, UINT flags,
        const D3D_FEATURE_LEVEL *levels, UINT nlevels, UINT sdk, ID3D11Device **dev, D3D_FEATURE_LEVEL *level,
        ID3D11DeviceContext **ctx)
{
    HRESULT hr = real_create11(adapter, type, sw, flags, levels, nlevels, sdk, dev, level, ctx);
    if (SUCCEEDED(hr) && dev && *dev) hook_device11(*dev);
    return hr;
}

/* The executable's import of D3D11CreateDevice, by name. */
static int redirect_exe_import11(void)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    DWORD rva = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    IMAGE_IMPORT_DESCRIPTOR *imp;
    int n = 0;
    if (!rva) return 0;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + rva); imp->Name; ++imp)
    {
        IMAGE_THUNK_DATA *orig, *iat;
        if (lstrcmpiA((const char *)base + imp->Name, "d3d11.dll") != 0) continue;
        orig = (IMAGE_THUNK_DATA *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        iat = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
        for (; orig->u1.AddressOfData; ++orig, ++iat)
        {
            DWORD old;
            if (IMAGE_SNAP_BY_ORDINAL(orig->u1.Ordinal)
                    || lstrcmpA((const char *)((IMAGE_IMPORT_BY_NAME *)(base + orig->u1.AddressOfData))->Name,
                                "D3D11CreateDevice")
                    || (void *)(ULONG_PTR)iat->u1.Function == (void *)mgvf_D3D11CreateDevice)
                continue;
            if (!VirtualProtect(&iat->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) continue;
            if (!real_create11) real_create11 = (create11_fn)(ULONG_PTR)iat->u1.Function;
            iat->u1.Function = (ULONG_PTR)mgvf_D3D11CreateDevice;
            VirtualProtect(&iat->u1.Function, sizeof(void *), old, &old);
            n++;
        }
    }
    return n;
}

static int imports12, imports11;

/* Fallback: a device of our own reaches the same class. Then one line after the
 * first minute, so the log says whether the morph was replaced. */
static DWORD WINAPI watcher(void *unused)
{
    int t;
    (void)unused;
    for (t = 0; t < 30 && !device_seen; t++) Sleep(100);
    if (!device_seen && imports12)
    {
        create_fn create = real_create ? real_create
            : (create_fn)GetProcAddress(GetModuleHandleA("d3d12.dll"), "D3D12CreateDevice");
        ID3D12Device *dev = NULL;
        HRESULT hr = create ? create(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev) : E_FAIL;
        if (SUCCEEDED(hr) && dev) { hook_device(dev); ID3D12Device_Release(dev); }
        else log_msg("no D3D12 device of our own (%08lx), nothing to do", (unsigned long)hr);
    }
    else if (!device_seen && imports11)
    {
        create11_fn create = real_create11 ? real_create11
            : (create11_fn)GetProcAddress(GetModuleHandleA("d3d11.dll"), "D3D11CreateDevice");
        ID3D11Device *dev = NULL;
        ID3D11DeviceContext *ctx = NULL;
        HRESULT hr = create ? create(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, NULL, &ctx)
                            : E_FAIL;
        if (SUCCEEDED(hr) && dev) hook_device11(dev);
        else log_msg("no D3D11 device of our own (%08lx), nothing to do", (unsigned long)hr);
        if (ctx) ID3D11DeviceContext_Release(ctx);
        if (dev) ID3D11Device_Release(dev);
    }
    else if (!device_seen)
        log_msg("the executable imports neither D3D12CreateDevice nor D3D11CreateDevice, nothing to do");
    Sleep(60000);
    log_msg("after a minute: %ld face morph pipelines replaced, %ld refused; %ld three-float views made one-float views",
            morphs_replaced, morphs_refused, views_made);
    return 0;
}

#include "mk11-movie.c"

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    char path[MAX_PATH], *slash;
    (void)reserved;
    if (reason == DLL_PROCESS_DETACH && logf)
    {
        log_msg("exit: %ld face morph pipelines replaced, %ld refused; %ld three-float views made one-float views",
                morphs_replaced, morphs_refused, views_made);
        fclose(logf);
        logf = NULL;
        return TRUE;
    }
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(inst);
    InitializeCriticalSection(&cs);
    GetModuleFileNameA(inst, path, sizeof(path));
    if ((slash = strrchr(path, '\\'))) strcpy(slash + 1, LOG_NAME);
    logf = fopen(path, "w");
    imports12 = redirect_exe_import();
    imports11 = redirect_exe_import11();
    log_msg("MK11 face fix: three-float buffer views become one-float views and the face morph reads them; "
            "D3D12CreateDevice import: %d slot(s), D3D11CreateDevice import: %d slot(s) redirected",
            imports12, imports11);
    log_msg("MK11 movies: NV12 offered and frames handed out in display order; CoCreateInstance import: %d slot(s) "
            "redirected", redirect_cocreate());
    CloseHandle(CreateThread(NULL, 0, watcher, NULL, 0, NULL));
    return TRUE;
}
