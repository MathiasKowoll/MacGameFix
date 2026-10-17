/*
 * mk11-face-fix.c -- Mortal Kombat 11: dark smeared patches on bare faces.
 *
 * WHAT IT FIXES. On this Mac the skin of every fighter whose face is uncovered
 * -- the forehead, the brows, around the eyes -- turns into smeared dark
 * patches with hard edges, which follow the light and change from frame to
 * frame. A face is clean right after a screen loads and breaks as soon as it
 * starts to animate, the character select included. Masked fighters never show
 * it. It is the same on D3DMetal (MK11_DX12.exe) and on DXMT (MK11.exe), at
 * every graphics setting.
 *
 * WHERE IT COMES FROM. After a face is deformed for its expression, two compute
 * passes give it a fresh tangent frame: one adds each triangle's tangent and
 * normal, weighted per corner, into an integer accumulator per vertex
 * (cs_cb994f68, InterlockedAdd), the other normalises the sums and packs them
 * (cs_6f7a24b6). Skipping those two removes most of the patches; faint ones
 * remain. Why the recomputed frame comes out wrong here is not known: a rewrite
 * of the first pass with robust weights and strict IEEE maths changed nothing,
 * and neither did UAV barriers anywhere in the chain or waiting for the GPU after
 * every submission. legacy/wiki/Mortal-Kombat-11.md has the rounds.
 *
 * WHAT IT DOES. The dispatches of those two compute shaders, direct and through
 * ExecuteIndirect, are skipped, so a face keeps the tangent frame it was
 * animated with. Nothing else the game draws or computes changes. A game update
 * that changes either shader makes this match nothing and do nothing.
 *
 * WHERE IT HOOKS. MK11_DX12.exe imports d3d12.dll's D3D12CreateDevice by ordinal
 * (101), so the executable's import slot is pointed here. If the game's device
 * has not been seen three seconds after load, a device of this DLL's own reaches
 * the same class, and the class-level patch covers the game's too. Carried on
 * amd_ags_x64.dll, which the game imports; every export is forwarded to the
 * renamed original (fixes/build-proxy.sh). Logs to mk11-face-fix.log beside
 * itself.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "sm2fix_core.h"
#include "sm2fix_core.c"

#define LOG_NAME "mk11-face-fix.log"
#define DEV_IDX(m) (offsetof(ID3D12Device8Vtbl, m) / sizeof(void *))
#define LIST_IDX(m) (offsetof(ID3D12GraphicsCommandListVtbl, m) / sizeof(void *))

/* The tangent accumulation and its normalisation (vkd3d-proton's shader hash). */
static const unsigned long long skipped_shaders[] = { 0xcb994f68f0668429ULL, 0x6f7a24b601b493c5ULL };

static CRITICAL_SECTION cs;
static FILE *logf;
static LONG device_seen, skipped_psos, skipped_dispatches, skipped_indirects;

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

static BOOL is_skipped_shader(const void *code, SIZE_T len)
{
    unsigned long long h;
    size_t i;
    if (!code || len < 32) return FALSE;
    h = sm2_shader_hash(code, len);
    for (i = 0; i < ARRAYSIZE(skipped_shaders); i++)
        if (skipped_shaders[i] == h) return TRUE;
    return FALSE;
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

/* ---- the pipelines whose dispatches are skipped ---------------------------- */
static void *dead_psos[256];
static LONG dead_n;

static BOOL is_dead(const void *pso)
{
    LONG i, n = dead_n;
    for (i = 0; pso && i < n; i++) if (dead_psos[i] == pso) return TRUE;
    return FALSE;
}

static void bury(void *pso)
{
    LONG n;
    if (!pso) return;
    EnterCriticalSection(&cs);
    n = dead_n;
    if (n < 256) { dead_psos[n] = pso; dead_n = n + 1; }
    LeaveCriticalSection(&cs);
    if (InterlockedIncrement(&skipped_psos) <= 8) log_msg("face tangent pipeline %p: its dispatches will be skipped", pso);
}

/* The pipeline each command list has bound, so a dispatch knows what it runs. */
static struct { void *list, *pso; } bound[4096];
static SRWLOCK bound_lock = SRWLOCK_INIT;

static void bind(void *list, void *pso)
{
    unsigned int i = (unsigned int)(((ULONG_PTR)list >> 4) * 2654435761u) & 4095, n;
    AcquireSRWLockExclusive(&bound_lock);
    for (n = 0; n < 4096; n++, i = (i + 1) & 4095)
        if (bound[i].list == list || !bound[i].list) { bound[i].list = list; bound[i].pso = pso; break; }
    ReleaseSRWLockExclusive(&bound_lock);
}

static void *bound_pso(void *list)
{
    unsigned int i = (unsigned int)(((ULONG_PTR)list >> 4) * 2654435761u) & 4095, n;
    void *pso = NULL;
    AcquireSRWLockShared(&bound_lock);
    for (n = 0; n < 4096 && bound[i].list; n++, i = (i + 1) & 4095)
        if (bound[i].list == list) { pso = bound[i].pso; break; }
    ReleaseSRWLockShared(&bound_lock);
    return pso;
}

/* ---- command lists --------------------------------------------------------- */
static void STDMETHODCALLTYPE hk_SetPipelineState(ID3D12GraphicsCommandList *list, ID3D12PipelineState *pso)
{
    void (STDMETHODCALLTYPE *orig)(ID3D12GraphicsCommandList *, ID3D12PipelineState *)
            = orig_fn(list, LIST_IDX(SetPipelineState));
    bind(list, pso);
    orig(list, pso);
}

static HRESULT STDMETHODCALLTYPE hk_Reset(ID3D12GraphicsCommandList *list, ID3D12CommandAllocator *alloc,
        ID3D12PipelineState *pso)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12GraphicsCommandList *, ID3D12CommandAllocator *, ID3D12PipelineState *)
            = orig_fn(list, LIST_IDX(Reset));
    bind(list, pso);
    return orig(list, alloc, pso);
}

static void STDMETHODCALLTYPE hk_Dispatch(ID3D12GraphicsCommandList *list, UINT x, UINT y, UINT z)
{
    void (STDMETHODCALLTYPE *orig)(ID3D12GraphicsCommandList *, UINT, UINT, UINT) = orig_fn(list, LIST_IDX(Dispatch));
    if (dead_n && is_dead(bound_pso(list))) { InterlockedIncrement(&skipped_dispatches); return; }
    orig(list, x, y, z);
}

/* The game launches some compute passes from argument buffers. */
static void STDMETHODCALLTYPE hk_ExecuteIndirect(ID3D12GraphicsCommandList *list, ID3D12CommandSignature *sig,
        UINT max, ID3D12Resource *args, UINT64 args_off, ID3D12Resource *count, UINT64 count_off)
{
    void (STDMETHODCALLTYPE *orig)(ID3D12GraphicsCommandList *, ID3D12CommandSignature *, UINT, ID3D12Resource *,
            UINT64, ID3D12Resource *, UINT64) = orig_fn(list, LIST_IDX(ExecuteIndirect));
    if (dead_n && is_dead(bound_pso(list))) { InterlockedIncrement(&skipped_indirects); return; }
    orig(list, sig, max, args, args_off, count, count_off);
}

static void hook_list(void *list)
{
    hook_slot(list, LIST_IDX(SetPipelineState), (void *)hk_SetPipelineState);
    hook_slot(list, LIST_IDX(Reset), (void *)hk_Reset);
    hook_slot(list, LIST_IDX(Dispatch), (void *)hk_Dispatch);
    hook_slot(list, LIST_IDX(ExecuteIndirect), (void *)hk_ExecuteIndirect);
}

static HRESULT STDMETHODCALLTYPE hk_CreateCommandList(ID3D12Device *dev, UINT mask, D3D12_COMMAND_LIST_TYPE type,
        ID3D12CommandAllocator *alloc, ID3D12PipelineState *pso, REFIID riid, void **list)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12Device *, UINT, D3D12_COMMAND_LIST_TYPE, ID3D12CommandAllocator *,
            ID3D12PipelineState *, REFIID, void **) = orig_fn(dev, DEV_IDX(CreateCommandList));
    HRESULT hr = orig(dev, mask, type, alloc, pso, riid, list);
    if (SUCCEEDED(hr) && list && *list) { hook_list(*list); bind(*list, pso); }
    return hr;
}

static HRESULT STDMETHODCALLTYPE hk_CreateCommandList1(ID3D12Device4 *dev, UINT mask, D3D12_COMMAND_LIST_TYPE type,
        D3D12_COMMAND_LIST_FLAGS flags, REFIID riid, void **list)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12Device4 *, UINT, D3D12_COMMAND_LIST_TYPE, D3D12_COMMAND_LIST_FLAGS,
            REFIID, void **) = orig_fn(dev, DEV_IDX(CreateCommandList1));
    HRESULT hr = orig(dev, mask, type, flags, riid, list);
    if (SUCCEEDED(hr) && list && *list) hook_list(*list);
    return hr;
}

/* ---- pipelines ------------------------------------------------------------- */
static HRESULT STDMETHODCALLTYPE hk_CreateComputePipelineState(ID3D12Device *dev,
        const D3D12_COMPUTE_PIPELINE_STATE_DESC *desc, REFIID riid, void **pso)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12Device *, const D3D12_COMPUTE_PIPELINE_STATE_DESC *, REFIID, void **)
            = orig_fn(dev, DEV_IDX(CreateComputePipelineState));
    HRESULT hr = orig(dev, desc, riid, pso);
    if (SUCCEEDED(hr) && desc && pso && is_skipped_shader(desc->CS.pShaderBytecode, desc->CS.BytecodeLength))
        bury(*pso);
    return hr;
}

static HRESULT STDMETHODCALLTYPE hk_CreatePipelineState(ID3D12Device2 *dev,
        const D3D12_PIPELINE_STATE_STREAM_DESC *desc, REFIID riid, void **pso)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D12Device2 *, const D3D12_PIPELINE_STATE_STREAM_DESC *, REFIID, void **)
            = orig_fn(dev, DEV_IDX(CreatePipelineState));
    HRESULT hr = orig(dev, desc, riid, pso);
    const void *code = NULL;
    size_t size = 0;
    if (SUCCEEDED(hr) && desc && pso
            && sm2_stream_find_cs(desc->pPipelineStateSubobjectStream, desc->SizeInBytes, &code, &size) == SM2_STREAM_COMPUTE
            && is_skipped_shader(code, size))
        bury(*pso);
    return hr;
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
        hook_slot(it, DEV_IDX(CreateComputePipelineState), (void *)hk_CreateComputePipelineState);
        hook_slot(it, DEV_IDX(CreateCommandList), (void *)hk_CreateCommandList);
        if (i >= 2) hook_slot(it, DEV_IDX(CreatePipelineState), (void *)hk_CreatePipelineState);
        if (i >= 4) hook_slot(it, DEV_IDX(CreateCommandList1), (void *)hk_CreateCommandList1);
        IUnknown_Release(it);
    }
    log_msg("device %p hooked (%u slots)", dev, hook_n);
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

/* Fallback: a device of our own reaches the same class. Then one line after the
 * first minute, so the log says whether anything was skipped. */
static DWORD WINAPI watcher(void *unused)
{
    int t;
    (void)unused;
    for (t = 0; t < 30 && !device_seen; t++) Sleep(100);
    if (!device_seen)
    {
        create_fn create = real_create ? real_create
            : (create_fn)GetProcAddress(GetModuleHandleA("d3d12.dll"), "D3D12CreateDevice");
        ID3D12Device *dev = NULL;
        HRESULT hr = create ? create(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev) : E_FAIL;
        if (SUCCEEDED(hr) && dev) { hook_device(dev); ID3D12Device_Release(dev); }
        else log_msg("no D3D12 device (%08lx): this is not the DirectX 12 game, nothing to do", (unsigned long)hr);
    }
    Sleep(60000);
    log_msg("after a minute: %ld face tangent pipelines, %ld dispatches and %ld indirect dispatches skipped",
            skipped_psos, skipped_dispatches, skipped_indirects);
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    char path[MAX_PATH], *slash;
    (void)reserved;
    if (reason == DLL_PROCESS_DETACH && logf)
    {
        log_msg("exit: %ld face tangent pipelines, %ld dispatches and %ld indirect dispatches skipped",
                skipped_psos, skipped_dispatches, skipped_indirects);
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
    log_msg("MK11 face fix: the face tangent recompute (cs_cb994f68, cs_6f7a24b6) is skipped; "
            "D3D12CreateDevice import: %d slot(s) redirected", redirect_exe_import());
    CloseHandle(CreateThread(NULL, 0, watcher, NULL, 0, NULL));
    return TRUE;
}
