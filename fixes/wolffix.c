/* d3d11.dll for The Wolf Among Us Remastered on CrossOver (D3DMetal): fixes the motion trails.
 *
 * With anti-aliasing on, the game uses TAA with 8x MSAA, and resolves it with shaders that read
 * 8 samples per pixel. Apple GPUs have no 8x MSAA: D3DMetal reports that, but still creates the
 * game's 8x textures, with 4 samples, so the shaders' reads of samples 4..7 return zero. The TAA
 * history clamp then always includes black, dark history is never rejected, and old frames stay
 * on screen as trails. This DLL makes those reads use samples 0..3 when the game creates its
 * pixel shaders, and passes everything else straight to the real d3d11.dll.
 *
 * It does nothing when the device really gives 8 samples, and changes no files. */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <stddef.h>
#include <stdlib.h>
#include "wolffix_core.h"

/* Lets the app recognise this DLL in a game folder. */
__attribute__((used)) static const char marker[] = "wolffix d3d11.dll for The Wolf Among Us Remastered";

typedef HRESULT (STDMETHODCALLTYPE *create_ps_fn)(ID3D11Device *, const void *, SIZE_T, ID3D11ClassLinkage *,
        ID3D11PixelShader **);

#define PS_INDEX (offsetof(ID3D11DeviceVtbl, CreatePixelShader) / sizeof(void *))

static HMODULE real_d3d11;
static INIT_ONCE init = INIT_ONCE_STATIC_INIT;
static SRWLOCK lock = SRWLOCK_INIT;
/* The original CreatePixelShader of each device vtable that was hooked. */
static struct { void **vtbl; create_ps_fn orig; } hooked[16];
static unsigned int hooked_count;

/* The original for this device's vtable; for a copy of a hooked vtable (another layer wrapping
 * the device), the first one hooked. */
static create_ps_fn original_create_ps(ID3D11Device *dev)
{
    void **vtbl = *(void ***)dev;
    create_ps_fn fn = NULL;
    unsigned int i;

    AcquireSRWLockShared(&lock);
    for (i = 0; i < hooked_count; i++)
        if (hooked[i].vtbl == vtbl)
            fn = hooked[i].orig;
    if (!fn && hooked_count)
        fn = hooked[0].orig;
    ReleaseSRWLockShared(&lock);
    return fn;
}

static HRESULT STDMETHODCALLTYPE hook_create_ps(ID3D11Device *dev, const void *code, SIZE_T size,
        ID3D11ClassLinkage *linkage, ID3D11PixelShader **out)
{
    create_ps_fn orig = original_create_ps(dev);
    int count;
    void *fixed;
    HRESULT hr;

    if (!orig)
        return E_FAIL;
    fixed = wolffix_remap_samples(code, size, &count);
    hr = orig(dev, fixed ? fixed : code, size, linkage, out);

    free(fixed);
    return hr;
}

/* Whether the device really gives 8 samples when asked; then the game's shaders are right as they are. */
static BOOL has_real_8x(ID3D11Device *dev)
{
    D3D11_TEXTURE2D_DESC desc = {1, 1, 1, 1, DXGI_FORMAT_R8G8B8A8_UNORM, {8, D3D11_STANDARD_MULTISAMPLE_PATTERN},
            D3D11_USAGE_DEFAULT, D3D11_BIND_RENDER_TARGET, 0, 0};
    ID3D11Texture2D *tex = NULL;
    BOOL real = FALSE;

    if (SUCCEEDED(ID3D11Device_CreateTexture2D(dev, &desc, NULL, &tex)) && tex)
    {
        ID3D11Texture2D_GetDesc(tex, &desc);
        real = desc.SampleDesc.Count >= 8;
        ID3D11Texture2D_Release(tex);
    }
    return real;
}

static void hook_device(ID3D11Device *dev)
{
    void **vtbl = *(void ***)dev;
    DWORD old;
    unsigned int i;

    if (has_real_8x(dev))
        return;
    AcquireSRWLockExclusive(&lock);
    for (i = 0; i < hooked_count; i++)
        if (hooked[i].vtbl == vtbl)
            break;
    if (i == hooked_count && hooked_count < ARRAYSIZE(hooked) && vtbl[PS_INDEX] != (void *)hook_create_ps
            && VirtualProtect(&vtbl[PS_INDEX], sizeof(void *), PAGE_EXECUTE_READWRITE, &old))
    {
        hooked[hooked_count].vtbl = vtbl;
        hooked[hooked_count].orig = (create_ps_fn)vtbl[PS_INDEX];
        hooked_count++;
        vtbl[PS_INDEX] = (void *)hook_create_ps;
        VirtualProtect(&vtbl[PS_INDEX], sizeof(void *), old, &old);
    }
    ReleaseSRWLockExclusive(&lock);
}

static BOOL CALLBACK load_real(INIT_ONCE *once, void *param, void **context)
{
    WCHAR path[MAX_PATH];
    UINT len = GetSystemDirectoryW(path, MAX_PATH - 12);

    if (len && len < MAX_PATH - 12)
    {
        lstrcatW(path, L"\\d3d11.dll");
        real_d3d11 = LoadLibraryW(path);
    }
    return TRUE;
}

static FARPROC real_proc(const char *name)
{
    InitOnceExecuteOnce(&init, load_real, NULL, NULL);
    return real_d3d11 ? GetProcAddress(real_d3d11, name) : NULL;
}

HRESULT WINAPI wolffix_D3D11CreateDevice(IDXGIAdapter *adapter, D3D_DRIVER_TYPE type, HMODULE sw, UINT flags,
        const D3D_FEATURE_LEVEL *levels, UINT nlevels, UINT sdk, ID3D11Device **dev, D3D_FEATURE_LEVEL *level,
        ID3D11DeviceContext **ctx)
{
    HRESULT (WINAPI *real)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *, UINT, UINT,
            ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **)
            = (void *)real_proc("D3D11CreateDevice");
    HRESULT hr;

    if (!real)
        return E_FAIL;
    hr = real(adapter, type, sw, flags, levels, nlevels, sdk, dev, level, ctx);
    if (SUCCEEDED(hr) && dev && *dev)
        hook_device(*dev);
    return hr;
}

HRESULT WINAPI wolffix_D3D11CreateDeviceAndSwapChain(IDXGIAdapter *adapter, D3D_DRIVER_TYPE type, HMODULE sw,
        UINT flags, const D3D_FEATURE_LEVEL *levels, UINT nlevels, UINT sdk, const DXGI_SWAP_CHAIN_DESC *scd,
        IDXGISwapChain **sc, ID3D11Device **dev, D3D_FEATURE_LEVEL *level, ID3D11DeviceContext **ctx)
{
    HRESULT (WINAPI *real)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *, UINT, UINT,
            const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **, ID3D11Device **, D3D_FEATURE_LEVEL *,
            ID3D11DeviceContext **) = (void *)real_proc("D3D11CreateDeviceAndSwapChain");
    HRESULT hr;

    if (!real)
        return E_FAIL;
    hr = real(adapter, type, sw, flags, levels, nlevels, sdk, scd, sc, dev, level, ctx);
    if (SUCCEEDED(hr) && dev && *dev)
        hook_device(*dev);
    return hr;
}
