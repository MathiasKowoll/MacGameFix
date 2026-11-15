/*
 * gow-depth-fix.c -- God of War (2018): white specks on characters.
 *
 * WHAT IT FIXES. Characters, Kratos first, are covered in white specks in dim
 * light. The game draws a depth-only prepass and then draws the same geometry
 * again into its G-buffer with the depth test set to EQUAL: a pixel survives only
 * if its depth matches the prepass exactly. On Windows the GPU computes the same
 * position bit for bit in both passes. Translated to Metal -- by DXMT or by
 * D3DMetal -- the two passes need not agree to the last bit, and the pixels that
 * disagree are discarded before any lighting runs: the specks.
 *
 * Found by a r/macgaming poster ("God Of War 2018 White Dot Fix (through
 * Crossover)") with a d3d11.dll proxy that bisected the game's shaders and
 * states live: the one depth-stencil state with an EQUAL test (depth writes off,
 * stencil on) was it, and GREATER_EQUAL in its place removed every speck.
 *
 * WHY NOT EVERYWHERE. Creating that state with GREATER_EQUAL for every draw also
 * removes the specks, but alpha-tested grass and leaves near the camera are then
 * drawn as solid cards: their prepass writes depth only inside the silhouette,
 * and EQUAL is what clips the G-buffer pass to it.
 *
 * WHAT THIS DOES. Every EQUAL state is kept, and a twin with the replacement test
 * (gow-depth-fix.ini, `equal_depth`) is made beside it. OMSetDepthStencilState is
 * hooked on the immediate and deferred contexts, and the twin is bound only when
 * the stencil reference is one of `stencil_refs`. The game writes a different
 * reference per kind of object in that pass (write mask 0x07, REPLACE). Measured
 * with DXMT on CrossOver Preview 27 (2026-11-16):
 *
 *   ref 0x05  most draws (about half); left as EQUAL
 *   ref 0x03  characters: replacing it alone removed the specks on them, with
 *             grass and leaves drawn right
 *   ref 0x01  fewest draws: adding it stopped the flicker left on the axe on
 *             Kratos' back, still with grass and leaves drawn right
 *
 * The default, used when the ini has no `stencil_refs`, is 0x01 and 0x03.
 * `stencil_refs = all` is the earlier behaviour.
 *
 * FINDING THE REFERENCES AGAIN. The log counts each reference used with an EQUAL
 * state. With `probe_keys = on`, F9 steps live through: none, each reference
 * (most used first), all; F10 goes back to the ini's choice. Each step is logged.
 *
 * WHERE IT HOOKS. GoW.exe imports d3d11.dll directly, so its import table is
 * already bound when this loads; D3D11CreateDevice and D3D11CreateDeviceAndSwap-
 * Chain are redirected there, and the device that comes back -- DXMT's or
 * D3DMetal's -- has CreateDepthStencilState and CreateDeferredContext hooked on
 * its class, and its contexts OMSetDepthStencilState.
 *
 * Carried on libSceJobManager.dll, which the game imports and no runner ships;
 * every export is forwarded to the renamed original (runtime/build-proxy.sh).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <d3d11_4.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define LOG_NAME "gow-depth-fix.log"
#define INI_NAME "gow-depth-fix.ini"
#define DEV_IDX(m) (offsetof(ID3D11DeviceVtbl, m) / sizeof(void *))
#define CTX_IDX(m) (offsetof(ID3D11DeviceContextVtbl, m) / sizeof(void *))

static HMODULE g_self;
static FILE *g_log;
static SRWLOCK g_lock = SRWLOCK_INIT;      /* log and hook table */
static SRWLOCK g_states_lock = SRWLOCK_INIT;
static D3D11_COMPARISON_FUNC g_equal_to = D3D11_COMPARISON_GREATER_EQUAL;
static volatile LONG g_equal_seen;
static struct { void **vtbl; unsigned int index; void *orig; } g_hooks[64];
static unsigned int g_hook_count;

/* Which stencil references get the replacement test. */
static BOOL g_ini_all;                      /* stencil_refs = all */
static BYTE g_ini_refs[256];                /* stencil_refs = list */
static volatile LONG g_probe = -1;          /* -1: use the ini; else a probe step */
static BOOL g_probe_keys;

/* EQUAL states we made a twin for. */
#define MAX_STATES 256
static struct { ID3D11DepthStencilState *equal, *repl; } g_states[MAX_STATES];
static unsigned int g_state_count;

/* Use counts per stencil reference (low byte), with an EQUAL state bound. */
static volatile LONG g_ref_count[256];

static void log_msg(const char *fmt, ...)
{
    va_list args;
    SYSTEMTIME t;

    if (!g_log)
        return;
    GetLocalTime(&t);
    AcquireSRWLockExclusive(&g_lock);
    fprintf(g_log, "%02d:%02d:%02d ", t.wHour, t.wMinute, t.wSecond);
    va_start(args, fmt);
    vfprintf(g_log, fmt, args);
    va_end(args);
    fputc('\n', g_log);
    fflush(g_log);
    ReleaseSRWLockExclusive(&g_lock);
}

static void path_next_to_self(char *out, size_t len, const char *file)
{
    char *slash;

    GetModuleFileNameA(g_self, out, (DWORD)len);
    slash = strrchr(out, '\\');
    if (slash)
        slash[1] = 0;
    else
        out[0] = 0;
    strncat(out, file, len - strlen(out) - 1);
}

static char *ini_value(char *line, const char *key)
{
    size_t n = strlen(key);
    char *value;

    if (line[0] == '#' || strncmp(line, key, n) || !(value = strchr(line, '=')))
        return NULL;
    value++;
    while (*value == ' ' || *value == '\t')
        value++;
    value[strcspn(value, "\r\n#;")] = 0;
    return value;
}

/*
 * gow-depth-fix.ini:
 *   equal_depth  = greater_equal | less_equal | off
 *   stencil_refs = all | none | a list such as 0x01, 0x03 (default 0x01, 0x03)
 *   probe_keys   = on | off
 */
static void read_settings(char *summary, size_t len)
{
    char path[MAX_PATH], line[512], refs_text[256] = "0x01, 0x03 (the default)";
    FILE *f;
    char *v;

    g_ini_all = FALSE;
    g_ini_refs[0x01] = g_ini_refs[0x03] = 1;
    path_next_to_self(path, sizeof(path), INI_NAME);
    if ((f = fopen(path, "r")))
    {
        while (fgets(line, sizeof(line), f))
        {
            if ((v = ini_value(line, "equal_depth")))
            {
                v[strcspn(v, " \t")] = 0;
                g_equal_to = !strcmp(v, "off") ? 0
                        : !strcmp(v, "less_equal") ? D3D11_COMPARISON_LESS_EQUAL
                        : D3D11_COMPARISON_GREATER_EQUAL;
            }
            else if ((v = ini_value(line, "probe_keys")))
                g_probe_keys = !strncmp(v, "on", 2);
            else if ((v = ini_value(line, "stencil_refs")))
            {
                char *p = v, *end;

                snprintf(refs_text, sizeof(refs_text), "%s", v);
                memset(g_ini_refs, 0, sizeof(g_ini_refs));
                g_ini_all = !strncmp(v, "all", 3);
                if (g_ini_all || !strncmp(v, "none", 4))
                    continue;
                while (*p)
                {
                    unsigned long r = strtoul(p, &end, 0);

                    if (end == p)
                    {
                        p++;
                        continue;
                    }
                    g_ini_refs[r & 0xff] = 1;
                    p = end;
                }
            }
        }
        fclose(f);
    }
    snprintf(summary, len, "EQUAL depth tests become %s for stencil refs %s; probe keys %s",
            g_equal_to == 0 ? "off" : g_equal_to == D3D11_COMPARISON_LESS_EQUAL ? "less_equal" : "greater_equal",
            refs_text, g_probe_keys ? "on (F9 next, F10 ini)" : "off");
}

/* ---------------------------------------------------------------- vtable hooks */

static void *orig_fn(void *obj, unsigned int index)
{
    void **vtbl = *(void ***)obj, *fn = NULL;
    unsigned int i;

    AcquireSRWLockShared(&g_lock);
    for (i = 0; i < g_hook_count; i++)
        if (g_hooks[i].vtbl == vtbl && g_hooks[i].index == index)
            fn = g_hooks[i].orig;
    ReleaseSRWLockShared(&g_lock);
    return fn;
}

static void hook_slot(void *obj, unsigned int index, void *hook)
{
    void **vtbl = *(void ***)obj;
    DWORD old;
    unsigned int i;

    AcquireSRWLockExclusive(&g_lock);
    for (i = 0; i < g_hook_count; i++)
        if (g_hooks[i].vtbl == vtbl && g_hooks[i].index == index)
            goto done;
    if (g_hook_count == ARRAYSIZE(g_hooks) || !vtbl[index] || vtbl[index] == hook
            || !VirtualProtect(&vtbl[index], sizeof(void *), PAGE_READWRITE, &old))
        goto done;
    g_hooks[g_hook_count].vtbl = vtbl;
    g_hooks[g_hook_count].index = index;
    g_hooks[g_hook_count].orig = vtbl[index];
    g_hook_count++;
    vtbl[index] = hook;
    VirtualProtect(&vtbl[index], sizeof(void *), old, &old);
done:
    ReleaseSRWLockExclusive(&g_lock);
}

/* ---------------------------------------------------------------- state twins */

static void remember_state(ID3D11DepthStencilState *equal, ID3D11DepthStencilState *repl)
{
    unsigned int i;

    AcquireSRWLockExclusive(&g_states_lock);
    for (i = 0; i < g_state_count; i++)
        if (g_states[i].equal == equal)
            break;
    if (i == g_state_count)
    {
        if (g_state_count == MAX_STATES)
        {
            ReleaseSRWLockExclusive(&g_states_lock);
            ID3D11DepthStencilState_Release(repl);
            return;
        }
        g_state_count++;
    }
    else if (g_states[i].repl && g_states[i].repl != repl)
        ID3D11DepthStencilState_Release(g_states[i].repl);
    g_states[i].equal = equal;
    g_states[i].repl = repl;      /* we keep the reference CreateDepthStencilState gave us */
    ReleaseSRWLockExclusive(&g_states_lock);
}

static ID3D11DepthStencilState *twin_of(ID3D11DepthStencilState *state)
{
    ID3D11DepthStencilState *repl = NULL;
    unsigned int i;

    if (!state)
        return NULL;
    AcquireSRWLockShared(&g_states_lock);
    for (i = 0; i < g_state_count; i++)
        if (g_states[i].equal == state)
        {
            repl = g_states[i].repl;
            break;
        }
    ReleaseSRWLockShared(&g_states_lock);
    return repl;
}

static const char *op_name(D3D11_STENCIL_OP op)
{
    static const char *n[] = { "?", "KEEP", "ZERO", "REPLACE", "INCR_SAT", "DECR_SAT", "INVERT", "INCR", "DECR" };
    return op < ARRAYSIZE(n) ? n[op] : "?";
}

static const char *func_name(D3D11_COMPARISON_FUNC f)
{
    static const char *n[] = { "?", "NEVER", "LESS", "EQUAL", "LESS_EQUAL", "GREATER", "NOT_EQUAL", "GREATER_EQUAL", "ALWAYS" };
    return f < ARRAYSIZE(n) ? n[f] : "?";
}

static HRESULT STDMETHODCALLTYPE hk_CreateDepthStencilState(ID3D11Device *device,
        const D3D11_DEPTH_STENCIL_DESC *desc, ID3D11DepthStencilState **state)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D11Device *, const D3D11_DEPTH_STENCIL_DESC *, ID3D11DepthStencilState **)
            = orig_fn(device, DEV_IDX(CreateDepthStencilState));
    D3D11_DEPTH_STENCIL_DESC changed;
    ID3D11DepthStencilState *repl = NULL;
    HRESULT hr;

    hr = orig(device, desc, state);
    if (FAILED(hr) || !state || !*state || !desc || !desc->DepthEnable
            || desc->DepthFunc != D3D11_COMPARISON_EQUAL || !g_equal_to)
        return hr;
    if (InterlockedIncrement(&g_equal_seen) <= 24)
        log_msg("EQUAL state %p: depth writes %s, stencil %s read %02x write %02x, "
                "front %s pass %s fail %s zfail %s, back %s pass %s",
                (void *)*state, desc->DepthWriteMask == D3D11_DEPTH_WRITE_MASK_ALL ? "on" : "off",
                desc->StencilEnable ? "on" : "off", desc->StencilReadMask, desc->StencilWriteMask,
                func_name(desc->FrontFace.StencilFunc), op_name(desc->FrontFace.StencilPassOp),
                op_name(desc->FrontFace.StencilFailOp), op_name(desc->FrontFace.StencilDepthFailOp),
                func_name(desc->BackFace.StencilFunc), op_name(desc->BackFace.StencilPassOp));
    changed = *desc;
    changed.DepthFunc = g_equal_to;
    if (SUCCEEDED(orig(device, &changed, &repl)) && repl)
        remember_state(*state, repl);
    return hr;
}

/* ---------------------------------------------------------------- choosing */

/* Probe steps: 0 = none, 1..n = the n-th most used reference, n+1 = all. */
static int sorted_refs(int *out)
{
    int n = 0, i, j;

    for (i = 0; i < 256; i++)
        if (g_ref_count[i])
            out[n++] = i;
    for (i = 1; i < n; i++)
        for (j = i; j > 0 && g_ref_count[out[j]] > g_ref_count[out[j - 1]]; j--)
        {
            int t = out[j];
            out[j] = out[j - 1];
            out[j - 1] = t;
        }
    return n;
}

static volatile LONG g_probe_ref = -2;      /* -2: none, -1: all, else one reference */

static void probe_step(int forward)
{
    int refs[256], n = sorted_refs(refs), step;

    if (!forward)
    {
        InterlockedExchange(&g_probe, -1);
        log_msg("probe: back to the ini's choice");
        return;
    }
    step = (int)InterlockedIncrement(&g_probe) % (n + 2);
    if (step == 0)
    {
        InterlockedExchange(&g_probe_ref, -2);
        log_msg("probe step 0: replacement for no reference (game as is)");
    }
    else if (step == n + 1)
    {
        InterlockedExchange(&g_probe_ref, -1);
        log_msg("probe step %d: replacement for every reference (the original fix)", step);
    }
    else
    {
        InterlockedExchange(&g_probe_ref, refs[step - 1]);
        log_msg("probe step %d: replacement only for stencil ref 0x%02x (%ld uses so far)",
                step, refs[step - 1], g_ref_count[refs[step - 1]]);
    }
}

static void poll_keys(void)
{
    static ULONGLONG last;
    static BOOL f9, f10;
    ULONGLONG now = GetTickCount64();
    BOOL down9, down10;

    if (!g_probe_keys || now - last < 50)
        return;
    last = now;
    down9 = (GetAsyncKeyState(VK_F9) & 0x8000) != 0;
    down10 = (GetAsyncKeyState(VK_F10) & 0x8000) != 0;
    if (down9 && !f9)
        probe_step(1);
    if (down10 && !f10)
        probe_step(0);
    f9 = down9;
    f10 = down10;
}

static BOOL wants_replacement(UINT ref)
{
    if (g_probe >= 0)
    {
        LONG r = g_probe_ref;
        return r == -1 || (r >= 0 && (UINT)r == (ref & 0xff));
    }
    return g_ini_all || g_ini_refs[ref & 0xff];
}

static void STDMETHODCALLTYPE hk_OMSetDepthStencilState(ID3D11DeviceContext *ctx,
        ID3D11DepthStencilState *state, UINT ref)
{
    void (STDMETHODCALLTYPE *orig)(ID3D11DeviceContext *, ID3D11DepthStencilState *, UINT)
            = orig_fn(ctx, CTX_IDX(OMSetDepthStencilState));
    ID3D11DepthStencilState *repl;

    poll_keys();
    if ((repl = twin_of(state)))
    {
        InterlockedIncrement(&g_ref_count[ref & 0xff]);
        if (wants_replacement(ref))
            state = repl;
    }
    orig(ctx, state, ref);
}

/* ---------------------------------------------------------------- hooking */

static void hook_context(IUnknown *ctx)
{
    static const IID *ifaces[] = { &IID_ID3D11DeviceContext, &IID_ID3D11DeviceContext1, &IID_ID3D11DeviceContext2,
                                   &IID_ID3D11DeviceContext3, &IID_ID3D11DeviceContext4 };
    unsigned int i;

    for (i = 0; i < ARRAYSIZE(ifaces); i++)
    {
        IUnknown *iface = NULL;

        if (FAILED(ctx->lpVtbl->QueryInterface(ctx, ifaces[i], (void **)&iface)) || !iface)
            continue;
        hook_slot(iface, CTX_IDX(OMSetDepthStencilState), (void *)hk_OMSetDepthStencilState);
        iface->lpVtbl->Release(iface);
    }
}

static HRESULT STDMETHODCALLTYPE hk_CreateDeferredContext(ID3D11Device *device, UINT flags,
        ID3D11DeviceContext **ctx)
{
    HRESULT (STDMETHODCALLTYPE *orig)(ID3D11Device *, UINT, ID3D11DeviceContext **)
            = orig_fn(device, DEV_IDX(CreateDeferredContext));
    HRESULT hr = orig(device, flags, ctx);
    static volatile LONG made;

    if (SUCCEEDED(hr) && ctx && *ctx)
    {
        hook_context((IUnknown *)*ctx);
        if (InterlockedIncrement(&made) <= 4)
            log_msg("deferred context %p created and hooked", (void *)*ctx);
    }
    return hr;
}

static void hook_device(IUnknown *device)
{
    static const IID *ifaces[] = { &IID_ID3D11Device, &IID_ID3D11Device1, &IID_ID3D11Device2,
                                   &IID_ID3D11Device3, &IID_ID3D11Device4, &IID_ID3D11Device5 };
    ID3D11DeviceContext *imm = NULL;
    unsigned int i;

    for (i = 0; i < ARRAYSIZE(ifaces); i++)
    {
        IUnknown *iface = NULL;

        if (FAILED(device->lpVtbl->QueryInterface(device, ifaces[i], (void **)&iface)) || !iface)
            continue;
        hook_slot(iface, DEV_IDX(CreateDepthStencilState), (void *)hk_CreateDepthStencilState);
        hook_slot(iface, DEV_IDX(CreateDeferredContext), (void *)hk_CreateDeferredContext);
        iface->lpVtbl->Release(iface);
    }
    ID3D11Device_GetImmediateContext((ID3D11Device *)device, &imm);
    if (imm)
    {
        hook_context((IUnknown *)imm);
        ID3D11DeviceContext_Release(imm);
    }
}

/* ------------------------------------------------------- reaching the device */

typedef HRESULT (WINAPI *create_device_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
        const D3D_FEATURE_LEVEL *, UINT, UINT, ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
typedef HRESULT (WINAPI *create_device_swap_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
        const D3D_FEATURE_LEVEL *, UINT, UINT, const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **,
        ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
static create_device_fn g_real_create;
static create_device_swap_fn g_real_create_swap;

static void device_made(ID3D11Device *device)
{
    hook_device((IUnknown *)device);
    log_msg("D3D11 device %p created; CreateDepthStencilState, CreateDeferredContext and "
            "OMSetDepthStencilState hooked (%u hooks)", (void *)device, g_hook_count);
}

static HRESULT WINAPI mgvf_D3D11CreateDevice(IDXGIAdapter *adapter, D3D_DRIVER_TYPE type, HMODULE sw, UINT flags,
        const D3D_FEATURE_LEVEL *levels, UINT count, UINT sdk, ID3D11Device **device, D3D_FEATURE_LEVEL *level,
        ID3D11DeviceContext **context)
{
    HRESULT hr = g_real_create(adapter, type, sw, flags, levels, count, sdk, device, level, context);

    log_msg("D3D11CreateDevice -> 0x%08lx", (unsigned long)hr);
    if (SUCCEEDED(hr) && device && *device)
        device_made(*device);
    return hr;
}

static HRESULT WINAPI mgvf_D3D11CreateDeviceAndSwapChain(IDXGIAdapter *adapter, D3D_DRIVER_TYPE type, HMODULE sw,
        UINT flags, const D3D_FEATURE_LEVEL *levels, UINT count, UINT sdk, const DXGI_SWAP_CHAIN_DESC *swap_desc,
        IDXGISwapChain **swap, ID3D11Device **device, D3D_FEATURE_LEVEL *level, ID3D11DeviceContext **context)
{
    HRESULT hr = g_real_create_swap(adapter, type, sw, flags, levels, count, sdk, swap_desc, swap, device, level,
            context);

    log_msg("D3D11CreateDeviceAndSwapChain -> 0x%08lx", (unsigned long)hr);
    if (SUCCEEDED(hr) && device && *device)
        device_made(*device);
    return hr;
}

/* Points the executable's own imports of the two creators at ours. */
static int redirect_imports(HMODULE base)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    IMAGE_NT_HEADERS *nt;
    IMAGE_IMPORT_DESCRIPTOR *imp;
    DWORD rva;
    int n = 0;

    if (!dos || dos->e_magic != IMAGE_DOS_SIGNATURE)
        return 0;
    nt = (IMAGE_NT_HEADERS *)((char *)base + dos->e_lfanew);
    rva = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    if (!rva)
        return 0;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)((char *)base + rva); imp->Name; ++imp)
    {
        IMAGE_THUNK_DATA *orig, *iat;

        if (lstrcmpiA((const char *)base + imp->Name, "d3d11.dll"))
            continue;
        orig = (IMAGE_THUNK_DATA *)((char *)base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        iat = (IMAGE_THUNK_DATA *)((char *)base + imp->FirstThunk);
        for (; orig->u1.AddressOfData; ++orig, ++iat)
        {
            IMAGE_IMPORT_BY_NAME *name;
            void *ours;
            DWORD old;

            if (IMAGE_SNAP_BY_ORDINAL(orig->u1.Ordinal))
                continue;
            name = (IMAGE_IMPORT_BY_NAME *)((char *)base + orig->u1.AddressOfData);
            if (!lstrcmpA((const char *)name->Name, "D3D11CreateDevice"))
            {
                ours = (void *)mgvf_D3D11CreateDevice;
                if (!g_real_create)
                    g_real_create = (create_device_fn)(ULONG_PTR)iat->u1.Function;
            }
            else if (!lstrcmpA((const char *)name->Name, "D3D11CreateDeviceAndSwapChain"))
            {
                ours = (void *)mgvf_D3D11CreateDeviceAndSwapChain;
                if (!g_real_create_swap)
                    g_real_create_swap = (create_device_swap_fn)(ULONG_PTR)iat->u1.Function;
            }
            else
                continue;
            if (!VirtualProtect(&iat->u1.Function, sizeof(void *), PAGE_READWRITE, &old))
                continue;
            iat->u1.Function = (ULONG_PTR)ours;
            VirtualProtect(&iat->u1.Function, sizeof(void *), old, &old);
            log_msg("import %s redirected", (const char *)name->Name);
            n++;
        }
    }
    return n;
}

static void log_ref_counts(void)
{
    int refs[256], n = sorted_refs(refs), i;

    if (!g_log)
        return;
    fprintf(g_log, "Stencil refs used with an EQUAL state (%d distinct):\n", n);
    for (i = 0; i < n; i++)
        fprintf(g_log, "  0x%02x  %ld\n", refs[i], g_ref_count[refs[i]]);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        char path[MAX_PATH], summary[512];
        int n;

        g_self = instance;
        DisableThreadLibraryCalls(instance);
        path_next_to_self(path, sizeof(path), LOG_NAME);
        g_log = fopen(path, "w");
        read_settings(summary, sizeof(summary));
        log_msg("God of War depth fix (MGVF, on libSceJobManager.dll), by stencil reference");
        log_msg("%s", summary);
        n = redirect_imports(GetModuleHandleA(NULL));
        log_msg("%d D3D11 creator import%s redirected", n, n == 1 ? "" : "s");
    }
    else if (reason == DLL_PROCESS_DETACH && g_log)
    {
        fprintf(g_log, "Exit: %ld EQUAL states created, %u twins kept\n", (long)g_equal_seen, g_state_count);
        log_ref_counts();
        fclose(g_log);
        g_log = NULL;
    }
    return TRUE;
}
