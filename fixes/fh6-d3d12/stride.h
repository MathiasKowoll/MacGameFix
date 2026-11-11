// stride: makes D3DMetal's 24-byte CBV/SRV/UAV descriptors look 32 bytes wide to the game (build id stride-1), and answers
// IDXGIAdapter::CheckInterfaceSupport (the UMD driver version) when D3DMetal fails it. Included after faillog.h.
//
// Why: FH5 sizes its CBV_SRV_UAV pool as 1,000,000 x GetDescriptorHandleIncrementSize bytes minus a fixed static part;
// with 24 the dynamic part is too small for free roam (Fatal Error 0x800705AA), with 32 it is not.
//
// How: every CBV_SRV_UAV descriptor heap gets FAKE CPU/GPU start handles in private address windows (each heap spaced
// N*32 + guard apart, so fake ranges never collide with each other or with real handles). The game computes
// start + i*32; every API that takes such a handle is hooked and maps it to real_start + i*real_inc (stride_math.h).
// Handles outside any fake range (RTV/DSV/sampler heaps, null) pass through unchanged.
//
// Handle ABI: ID3D12DescriptorHeap::GetCPU/GPUDescriptorHandleForHeapStart use the C-interface struct-return form
// `HANDLE *(*)(ID3D12DescriptorHeap *This, HANDLE *ret)` (hidden return pointer, returned in RAX), exactly as the
// mingw d3d12.h declares it; by-value handle parameters (one 8-byte member) travel in a register like a UINT64.
//
// Hooks are per vtable (registry keyed by table pointer, original function pointers saved per table), so interface
// generations whose tables differ are each forwarded to their own original; slots are re-written after every device
// patch because the shim / faillog may have overwritten them (their saved originals chain correctly).
#include <stddef.h>
#include <dxgi1_6.h>
#include "stride_math.h"

#define ST_BUILD "stride-1"
#define ST_FAKE_INC 32u

enum { SK_DEV, SK_LIST, SK_HEAP, SK_AD, SK_FAC };
enum { S_GDHIS, S_CCBV, S_CSRV, S_CUAV, S_CDESC, S_CDS, S_CDH, S_CCL, S_CCL1, S_CSFUAV,   // device
       S_SGRDT, S_SCRDT, S_CUAVU, S_CUAVF,                                                 // command list
       S_HCPU, S_HGPU,                                                                       // descriptor heap
       S_CIS,                                                                                // adapter
       S_EA, S_EA1, S_EABL, S_EABGP, S_N };                                                  // factory
// counters (calls / hits) for the hooked methods
enum { M_GDHIS, M_CCBV, M_CSRV, M_CUAV, M_CDESC, M_CDS, M_CSFUAV, M_SGRDT, M_SCRDT, M_CUAVU, M_CUAVF, M_HCPU, M_HGPU, M_N };
static const char *const st_mnames[M_N] = { "GetDescriptorHandleIncrementSize", "CreateConstantBufferView", "CreateShaderResourceView",
    "CreateUnorderedAccessView", "CopyDescriptors", "CopyDescriptorsSimple", "CreateSamplerFeedbackUnorderedAccessView",
    "SetGraphicsRootDescriptorTable", "SetComputeRootDescriptorTable", "ClearUnorderedAccessViewUint", "ClearUnorderedAccessViewFloat",
    "GetCPUDescriptorHandleForHeapStart", "GetGPUDescriptorHandleForHeapStart" };
typedef struct { volatile LONG calls, hits; char pad[56]; } st_cnt_t;   // one cache line per method: no false sharing
static st_cnt_t st_cnt[M_N];
extern int hb_debug;   // d3d12.c: HB_DEBUG=1
#define ST_CNT(m, f) do { if (hb_debug) st_cnt[m].f++; } while (0)   // diagnostic counters only under HB_DEBUG=1

typedef struct { void **vt; int kind, level; void *orig[S_N]; } st_vte;
#define ST_MAXVT 96
static st_vte st_vtes[ST_MAXVT]; static volatile LONG st_nvte;
static CRITICAL_SECTION st_cs;

// heap table: append-only (entries are killed by zeroing their fake bases), count published after the entry is complete
#define ST_MAXHEAP 256
static sm_heap st_heaps[ST_MAXHEAP]; static void *volatile st_hptr[ST_MAXHEAP]; static volatile LONG st_nheap;
static int st_enabled = 1, st_active, st_inited; static volatile LONG st_real_inc;
static volatile LONG st_anom, st_misaligned_logged, st_heap_overflow;
static ULONGLONG st_next_cpu, st_cpu_end, st_next_gpu; static ULONGLONG st_start_tick;
static int st_umd_enabled = 1; static ULONGLONG st_umd_ver; static volatile LONG st_umd_calls, st_umd_never_logged, st_umd_patched;

static void st_log(const char *fmt, ...)
{
    char b[600]; va_list ap;
    if (!hb_debug) return;   // play build
    va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    EnterCriticalSection(&fl_lock); fl_write(b); LeaveCriticalSection(&fl_lock);
}
// called by the faillog thread with fl_lock held
static void stride_dump_locked(void)
{
    char b[2200]; int n = 0, i;
    n += snprintf(b + n, sizeof b - n, "STRIDE build=%s active=%d real_inc=%ld fake_inc=%u heaps=%ld anomalies=%ld umd_calls=%ld |", ST_BUILD, st_active,
        (long)st_real_inc, ST_FAKE_INC, (long)st_nheap, (long)st_anom, (long)st_umd_calls);
    for (i = 0; i < M_N && n < (int)sizeof b - 120; i++)
        if (st_cnt[i].calls) n += snprintf(b + n, sizeof b - n, " %s=%ld/%ld", st_mnames[i], (long)st_cnt[i].calls, (long)st_cnt[i].hits);
    fl_write(b);
    if (st_umd_enabled && st_umd_patched && !st_umd_calls && !st_umd_never_logged && GetTickCount64() - st_start_tick > 60000) {
        st_umd_never_logged = 1;
        fl_write("STRIDE UMD: IDXGIAdapter::CheckInterfaceSupport was NEVER called in the first 60 s (FH302 would then come from D3DKMTQueryAdapterInfo, not this call)");
    }
}

// ---- vtable registry -----------------------------------------------------------------------------
static st_vte *st_find(void *obj)
{
    void **vt = *(void ***)obj; int i, n = st_nvte;
    for (i = 0; i < n; i++) if (st_vtes[i].vt == vt) return &st_vtes[i];
    return NULL;
}
static void st_set(st_vte *e, int sid, size_t idx, void *hook)
{
    void **slot = &e->vt[idx];
    if (*slot == hook) return;
    if (!e->orig[sid]) e->orig[sid] = *slot;   // saved before the hook becomes visible
    patch_slot(slot, hook, &e->orig[sid]);     // orig already set, so this only writes the slot
}
#define SIDX(T, m) (offsetof(T, m) / sizeof(void *))
// hook prototypes (defined below)
static UINT STDMETHODCALLTYPE st_GDHIS(void *, D3D12_DESCRIPTOR_HEAP_TYPE);
static void STDMETHODCALLTYPE st_CCBV(void *, const D3D12_CONSTANT_BUFFER_VIEW_DESC *, D3D12_CPU_DESCRIPTOR_HANDLE);
static void STDMETHODCALLTYPE st_CSRV(void *, void *, const D3D12_SHADER_RESOURCE_VIEW_DESC *, D3D12_CPU_DESCRIPTOR_HANDLE);
static void STDMETHODCALLTYPE st_CUAV(void *, void *, void *, const D3D12_UNORDERED_ACCESS_VIEW_DESC *, D3D12_CPU_DESCRIPTOR_HANDLE);
static void STDMETHODCALLTYPE st_CDESC(void *, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE *, const UINT *, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE *, const UINT *, D3D12_DESCRIPTOR_HEAP_TYPE);
static void STDMETHODCALLTYPE st_CDS(void *, UINT, D3D12_CPU_DESCRIPTOR_HANDLE, D3D12_CPU_DESCRIPTOR_HANDLE, D3D12_DESCRIPTOR_HEAP_TYPE);
static HRESULT STDMETHODCALLTYPE st_CDH(void *, const D3D12_DESCRIPTOR_HEAP_DESC *, REFIID, void **);
static HRESULT STDMETHODCALLTYPE st_CCL(void *, UINT, D3D12_COMMAND_LIST_TYPE, void *, void *, REFIID, void **);
static HRESULT STDMETHODCALLTYPE st_CCL1(void *, UINT, D3D12_COMMAND_LIST_TYPE, UINT, REFIID, void **);
static void STDMETHODCALLTYPE st_CSFUAV(void *, void *, void *, D3D12_CPU_DESCRIPTOR_HANDLE);
static void STDMETHODCALLTYPE st_SGRDT(void *, UINT, D3D12_GPU_DESCRIPTOR_HANDLE);
static void STDMETHODCALLTYPE st_SCRDT(void *, UINT, D3D12_GPU_DESCRIPTOR_HANDLE);
static void STDMETHODCALLTYPE st_CUAVU(void *, D3D12_GPU_DESCRIPTOR_HANDLE, D3D12_CPU_DESCRIPTOR_HANDLE, void *, const UINT *, UINT, const D3D12_RECT *);
static void STDMETHODCALLTYPE st_CUAVF(void *, D3D12_GPU_DESCRIPTOR_HANDLE, D3D12_CPU_DESCRIPTOR_HANDLE, void *, const float *, UINT, const D3D12_RECT *);
static D3D12_CPU_DESCRIPTOR_HANDLE *STDMETHODCALLTYPE st_HCPU(void *, D3D12_CPU_DESCRIPTOR_HANDLE *);
static D3D12_GPU_DESCRIPTOR_HANDLE *STDMETHODCALLTYPE st_HGPU(void *, D3D12_GPU_DESCRIPTOR_HANDLE *);
static HRESULT STDMETHODCALLTYPE st_CIS(void *, REFGUID, LARGE_INTEGER *);
static HRESULT STDMETHODCALLTYPE st_EA(void *, UINT, IDXGIAdapter **);
static HRESULT STDMETHODCALLTYPE st_EA1(void *, UINT, IDXGIAdapter1 **);
static HRESULT STDMETHODCALLTYPE st_EABL(void *, LUID, REFIID, void **);
static HRESULT STDMETHODCALLTYPE st_EABGP(void *, UINT, DXGI_GPU_PREFERENCE, REFIID, void **);

static void st_apply(st_vte *e)
{
    switch (e->kind) {
    case SK_DEV:   // ID3D12Device9Vtbl is the superset layout; slots are written only up to this table's level
#define D(m, sid, h) st_set(e, sid, SIDX(ID3D12Device9Vtbl, m), (void *)h)
        D(GetDescriptorHandleIncrementSize, S_GDHIS, st_GDHIS); D(CreateConstantBufferView, S_CCBV, st_CCBV);
        D(CreateShaderResourceView, S_CSRV, st_CSRV); D(CreateUnorderedAccessView, S_CUAV, st_CUAV);
        D(CopyDescriptors, S_CDESC, st_CDESC); D(CopyDescriptorsSimple, S_CDS, st_CDS);
        D(CreateDescriptorHeap, S_CDH, st_CDH); D(CreateCommandList, S_CCL, st_CCL);
        if (e->level >= 4) D(CreateCommandList1, S_CCL1, st_CCL1);
        if (e->level >= 8) D(CreateSamplerFeedbackUnorderedAccessView, S_CSFUAV, st_CSFUAV);
#undef D
        break;
    case SK_LIST:
#define D(m, sid, h) st_set(e, sid, SIDX(ID3D12GraphicsCommandListVtbl, m), (void *)h)
        D(SetGraphicsRootDescriptorTable, S_SGRDT, st_SGRDT); D(SetComputeRootDescriptorTable, S_SCRDT, st_SCRDT);
        D(ClearUnorderedAccessViewUint, S_CUAVU, st_CUAVU); D(ClearUnorderedAccessViewFloat, S_CUAVF, st_CUAVF);
#undef D
        break;
    case SK_HEAP:
        st_set(e, S_HCPU, SIDX(ID3D12DescriptorHeapVtbl, GetCPUDescriptorHandleForHeapStart), (void *)st_HCPU);
        st_set(e, S_HGPU, SIDX(ID3D12DescriptorHeapVtbl, GetGPUDescriptorHandleForHeapStart), (void *)st_HGPU);
        break;
    case SK_AD:
        st_set(e, S_CIS, SIDX(IDXGIAdapterVtbl, CheckInterfaceSupport), (void *)st_CIS); break;
    case SK_FAC:   // level: 0 IDXGIFactory, 1 Factory1+, 4 Factory4+, 6 Factory6+
        st_set(e, S_EA, SIDX(IDXGIFactoryVtbl, EnumAdapters), (void *)st_EA);
        if (e->level >= 1) st_set(e, S_EA1, SIDX(IDXGIFactory1Vtbl, EnumAdapters1), (void *)st_EA1);
        if (e->level >= 4) st_set(e, S_EABL, SIDX(IDXGIFactory4Vtbl, EnumAdapterByLuid), (void *)st_EABL);
        if (e->level >= 6) st_set(e, S_EABGP, SIDX(IDXGIFactory6Vtbl, EnumAdapterByGpuPreference), (void *)st_EABGP);
        break;
    }
}
// register (or re-apply) the vtable behind `iface`, which MUST be an interface of the right kind and level
static st_vte *st_reg(void *iface, int kind, int level)
{
    void **vt = *(void ***)iface; int i; st_vte *e = NULL;
    EnterCriticalSection(&st_cs);
    for (i = 0; i < st_nvte; i++) if (st_vtes[i].vt == vt) { e = &st_vtes[i]; break; }
    if (!e && st_nvte < ST_MAXVT) {
        e = &st_vtes[st_nvte]; e->vt = vt; e->kind = kind; e->level = level;
        st_apply(e);                       // fills e->orig from the live slots before writing the hooks
        InterlockedExchange(&st_nvte, st_nvte + 1);   // published after (the hooks only run once a caller reaches the table)
        st_log("STRIDE vtable kind=%d level=%d table=%p registered", kind, level, (void *)vt);
    } else if (e) {
        if (level > e->level) e->level = level;
        st_apply(e);
    } else st_log("STRIDE vtable registry full, kind=%d table=%p NOT hooked", kind, (void *)vt);
    LeaveCriticalSection(&st_cs);
    return e;
}
static void st_reapply_all(void)
{
    int i;
    EnterCriticalSection(&st_cs);
    for (i = 0; i < st_nvte; i++) st_apply(&st_vtes[i]);
    LeaveCriticalSection(&st_cs);
}

// ---- translation ---------------------------------------------------------------------------------
static void st_anomaly(int s, int m, int gpu, uint64_t h)
{
    LONG n;
    if (!hb_debug) return;   // play build: anomalies are only counted/logged under HB_DEBUG=1 (the clamp itself is in sm_xlat)
    n = InterlockedIncrement(&st_anom);
    if (n <= 20 || n % 1000 == 0)
        st_log("STRIDE anomaly #%ld %s in %s handle=0x%llx (%s)", (long)n, s == SM_CLAMPED ? "index past heap end, clamped" : "handle not a multiple of 32 from heap start, rounded down",
            st_mnames[m], (unsigned long long)h, gpu ? "gpu" : "cpu");
}
static D3D12_CPU_DESCRIPTOR_HANDLE st_tc(D3D12_CPU_DESCRIPTOR_HANDLE h, int m)
{
    int s; D3D12_CPU_DESCRIPTOR_HANDLE r;
    r.ptr = (SIZE_T)sm_xlat(st_heaps, st_nheap, 0, (uint64_t)h.ptr, ST_FAKE_INC, (uint32_t)st_real_inc, &s);
    if (s) { ST_CNT(m, hits); if (s > SM_OK) st_anomaly(s, m, 0, (uint64_t)h.ptr); }
    return r;
}
static D3D12_GPU_DESCRIPTOR_HANDLE st_tg(D3D12_GPU_DESCRIPTOR_HANDLE h, int m)
{
    int s; D3D12_GPU_DESCRIPTOR_HANDLE r;
    r.ptr = sm_xlat(st_heaps, st_nheap, 1, (uint64_t)h.ptr, ST_FAKE_INC, (uint32_t)st_real_inc, &s);
    if (s) { ST_CNT(m, hits); if (s > SM_OK) st_anomaly(s, m, 1, (uint64_t)h.ptr); }
    return r;
}
#define ENT(obj, sid) st_vte *e = st_find(obj)

static UINT STDMETHODCALLTYPE st_GDHIS(void *d, D3D12_DESCRIPTOR_HEAP_TYPE t)
{
    ENT(d, S_GDHIS); UINT r;
    if (!e) return 0;
    r = ((UINT (STDMETHODCALLTYPE *)(void *, D3D12_DESCRIPTOR_HEAP_TYPE))e->orig[S_GDHIS])(d, t);
    ST_CNT(M_GDHIS, calls);
    if (t == D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV && st_active) { ST_CNT(M_GDHIS, hits); return ST_FAKE_INC; }
    return r;
}
static void STDMETHODCALLTYPE st_CCBV(void *d, const D3D12_CONSTANT_BUFFER_VIEW_DESC *desc, D3D12_CPU_DESCRIPTOR_HANDLE h)
{
    ENT(d, S_CCBV); if (!e) return;
    ST_CNT(M_CCBV, calls);
    ((void (STDMETHODCALLTYPE *)(void *, const D3D12_CONSTANT_BUFFER_VIEW_DESC *, D3D12_CPU_DESCRIPTOR_HANDLE))e->orig[S_CCBV])(d, desc, st_tc(h, M_CCBV));
}
static void STDMETHODCALLTYPE st_CSRV(void *d, void *res, const D3D12_SHADER_RESOURCE_VIEW_DESC *desc, D3D12_CPU_DESCRIPTOR_HANDLE h)
{
    ENT(d, S_CSRV); if (!e) return;
    ST_CNT(M_CSRV, calls);
    ((void (STDMETHODCALLTYPE *)(void *, void *, const D3D12_SHADER_RESOURCE_VIEW_DESC *, D3D12_CPU_DESCRIPTOR_HANDLE))e->orig[S_CSRV])(d, res, desc, st_tc(h, M_CSRV));
}
static void STDMETHODCALLTYPE st_CUAV(void *d, void *res, void *ctr, const D3D12_UNORDERED_ACCESS_VIEW_DESC *desc, D3D12_CPU_DESCRIPTOR_HANDLE h)
{
    ENT(d, S_CUAV); if (!e) return;
    ST_CNT(M_CUAV, calls);
    ((void (STDMETHODCALLTYPE *)(void *, void *, void *, const D3D12_UNORDERED_ACCESS_VIEW_DESC *, D3D12_CPU_DESCRIPTOR_HANDLE))e->orig[S_CUAV])(d, res, ctr, desc, st_tc(h, M_CUAV));
}
static void STDMETHODCALLTYPE st_CSFUAV(void *d, void *tgt, void *fb, D3D12_CPU_DESCRIPTOR_HANDLE h)
{
    ENT(d, S_CSFUAV); if (!e) return;
    ST_CNT(M_CSFUAV, calls);
    ((void (STDMETHODCALLTYPE *)(void *, void *, void *, D3D12_CPU_DESCRIPTOR_HANDLE))e->orig[S_CSFUAV])(d, tgt, fb, st_tc(h, M_CSFUAV));
}
// translate an array of range starts into a copy (stack for small counts), only when the heap type can be CBV_SRV_UAV
static D3D12_CPU_DESCRIPTOR_HANDLE *st_tarr(const D3D12_CPU_DESCRIPTOR_HANDLE *src, UINT n, D3D12_CPU_DESCRIPTOR_HANDLE *stack, UINT cap, int *heapalloc)
{
    D3D12_CPU_DESCRIPTOR_HANDLE *p = stack; UINT i;
    *heapalloc = 0;
    if (!src || !n) return (D3D12_CPU_DESCRIPTOR_HANDLE *)src;
    if (n > cap) { p = (D3D12_CPU_DESCRIPTOR_HANDLE *)HeapAlloc(GetProcessHeap(), 0, n * sizeof *p); if (!p) return (D3D12_CPU_DESCRIPTOR_HANDLE *)src; *heapalloc = 1; }
    for (i = 0; i < n; i++) p[i] = st_tc(src[i], M_CDESC);
    return p;
}
static void STDMETHODCALLTYPE st_CDESC(void *d, UINT nd, const D3D12_CPU_DESCRIPTOR_HANDLE *ds, const UINT *dsz, UINT ns, const D3D12_CPU_DESCRIPTOR_HANDLE *ss, const UINT *ssz, D3D12_DESCRIPTOR_HEAP_TYPE t)
{
    ENT(d, S_CDESC); D3D12_CPU_DESCRIPTOR_HANDLE sd[64], ssx[64], *pd = (D3D12_CPU_DESCRIPTOR_HANDLE *)ds, *ps = (D3D12_CPU_DESCRIPTOR_HANDLE *)ss; int ha = 0, hb = 0;
    if (!e) return;
    ST_CNT(M_CDESC, calls);
    if (t == D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV) { pd = st_tarr(ds, nd, sd, 64, &ha); ps = st_tarr(ss, ns, ssx, 64, &hb); }
    ((void (STDMETHODCALLTYPE *)(void *, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE *, const UINT *, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE *, const UINT *, D3D12_DESCRIPTOR_HEAP_TYPE))e->orig[S_CDESC])(d, nd, pd, dsz, ns, ps, ssz, t);
    if (ha) HeapFree(GetProcessHeap(), 0, pd);
    if (hb) HeapFree(GetProcessHeap(), 0, ps);
}
static void STDMETHODCALLTYPE st_CDS(void *d, UINT n, D3D12_CPU_DESCRIPTOR_HANDLE dst, D3D12_CPU_DESCRIPTOR_HANDLE src, D3D12_DESCRIPTOR_HEAP_TYPE t)
{
    ENT(d, S_CDS); if (!e) return;
    ST_CNT(M_CDS, calls);
    if (t == D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV) { dst = st_tc(dst, M_CDS); src = st_tc(src, M_CDS); }
    ((void (STDMETHODCALLTYPE *)(void *, UINT, D3D12_CPU_DESCRIPTOR_HANDLE, D3D12_CPU_DESCRIPTOR_HANDLE, D3D12_DESCRIPTOR_HEAP_TYPE))e->orig[S_CDS])(d, n, dst, src, t);
}
// command lists
static void STDMETHODCALLTYPE st_SGRDT(void *l, UINT i, D3D12_GPU_DESCRIPTOR_HANDLE h)
{
    ENT(l, S_SGRDT); if (!e) return;
    ST_CNT(M_SGRDT, calls);
    ((void (STDMETHODCALLTYPE *)(void *, UINT, D3D12_GPU_DESCRIPTOR_HANDLE))e->orig[S_SGRDT])(l, i, st_tg(h, M_SGRDT));
}
static void STDMETHODCALLTYPE st_SCRDT(void *l, UINT i, D3D12_GPU_DESCRIPTOR_HANDLE h)
{
    ENT(l, S_SCRDT); if (!e) return;
    ST_CNT(M_SCRDT, calls);
    ((void (STDMETHODCALLTYPE *)(void *, UINT, D3D12_GPU_DESCRIPTOR_HANDLE))e->orig[S_SCRDT])(l, i, st_tg(h, M_SCRDT));
}
static void STDMETHODCALLTYPE st_CUAVU(void *l, D3D12_GPU_DESCRIPTOR_HANDLE g, D3D12_CPU_DESCRIPTOR_HANDLE c, void *r, const UINT *v, UINT nr, const D3D12_RECT *rc)
{
    ENT(l, S_CUAVU); if (!e) return;
    ST_CNT(M_CUAVU, calls);
    ((void (STDMETHODCALLTYPE *)(void *, D3D12_GPU_DESCRIPTOR_HANDLE, D3D12_CPU_DESCRIPTOR_HANDLE, void *, const UINT *, UINT, const D3D12_RECT *))e->orig[S_CUAVU])(l, st_tg(g, M_CUAVU), st_tc(c, M_CUAVU), r, v, nr, rc);
}
static void STDMETHODCALLTYPE st_CUAVF(void *l, D3D12_GPU_DESCRIPTOR_HANDLE g, D3D12_CPU_DESCRIPTOR_HANDLE c, void *r, const float *v, UINT nr, const D3D12_RECT *rc)
{
    ENT(l, S_CUAVF); if (!e) return;
    ST_CNT(M_CUAVF, calls);
    ((void (STDMETHODCALLTYPE *)(void *, D3D12_GPU_DESCRIPTOR_HANDLE, D3D12_CPU_DESCRIPTOR_HANDLE, void *, const float *, UINT, const D3D12_RECT *))e->orig[S_CUAVF])(l, st_tg(g, M_CUAVF), st_tc(c, M_CUAVF), r, v, nr, rc);
}
// heaps: CBV_SRV_UAV heaps report fake starts, every other heap its real one
static D3D12_CPU_DESCRIPTOR_HANDLE *STDMETHODCALLTYPE st_HCPU(void *h, D3D12_CPU_DESCRIPTOR_HANDLE *ret)
{
    int i, n = st_nheap; ENT(h, S_HCPU);
    ST_CNT(M_HCPU, calls);
    for (i = 0; i < n; i++)
        if (st_hptr[i] == h && st_heaps[i].fake_cpu) { ret->ptr = (SIZE_T)st_heaps[i].fake_cpu; ST_CNT(M_HCPU, hits); return ret; }
    if (!e) { ret->ptr = 0; return ret; }
    return ((D3D12_CPU_DESCRIPTOR_HANDLE *(STDMETHODCALLTYPE *)(void *, D3D12_CPU_DESCRIPTOR_HANDLE *))e->orig[S_HCPU])(h, ret);
}
static D3D12_GPU_DESCRIPTOR_HANDLE *STDMETHODCALLTYPE st_HGPU(void *h, D3D12_GPU_DESCRIPTOR_HANDLE *ret)
{
    int i, n = st_nheap; ENT(h, S_HGPU);
    ST_CNT(M_HGPU, calls);
    for (i = 0; i < n; i++)
        if (st_hptr[i] == h && st_heaps[i].fake_gpu) { ret->ptr = st_heaps[i].fake_gpu; ST_CNT(M_HGPU, hits); return ret; }
    if (!e) { ret->ptr = 0; return ret; }
    return ((D3D12_GPU_DESCRIPTOR_HANDLE *(STDMETHODCALLTYPE *)(void *, D3D12_GPU_DESCRIPTOR_HANDLE *))e->orig[S_HGPU])(h, ret);
}

// ---- heap creation -------------------------------------------------------------------------------
static ULONGLONG st_alloc_range(ULONGLONG *next, ULONGLONG end, ULONG n)
{
    ULONGLONG span = ((ULONGLONG)n * ST_FAKE_INC + 0x10000 + 0xFFFF) & ~0xFFFFull, r = *next;
    if (end && r + span > end) return 0;
    *next += span; return r;
}
static void st_new_heap(void *heap, const D3D12_DESCRIPTOR_HEAP_DESC *desc)
{
    IUnknown *u = (IUnknown *)heap; void *hp = NULL; int i, n; st_vte *e; ID3D12DescriptorHeapVtbl *vt;
    typedef D3D12_CPU_DESCRIPTOR_HANDLE *(STDMETHODCALLTYPE *FC)(void *, D3D12_CPU_DESCRIPTOR_HANDLE *);
    typedef D3D12_GPU_DESCRIPTOR_HANDLE *(STDMETHODCALLTYPE *FG)(void *, D3D12_GPU_DESCRIPTOR_HANDLE *);
    if (FAILED(u->lpVtbl->QueryInterface(u, &IID_ID3D12DescriptorHeap, &hp)) || !hp) return;
    (void)vt;
    EnterCriticalSection(&st_cs);
    n = st_nheap;
    for (i = 0; i < n; i++)   // a destroyed heap's address can come back: its old entry must stop answering
        if (st_hptr[i] == hp) { st_heaps[i].fake_cpu = 0; st_heaps[i].fake_gpu = 0; st_hptr[i] = NULL; }
    if (desc && desc->Type == D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV) {
        e = st_reg(hp, SK_HEAP, 0);
        if (e && e->orig[S_HCPU] && n < ST_MAXHEAP) {
            sm_heap *s = &st_heaps[n]; D3D12_CPU_DESCRIPTOR_HANDLE c; D3D12_GPU_DESCRIPTOR_HANDLE g;
            ((FC)e->orig[S_HCPU])(hp, &c); s->real_cpu = (uint64_t)c.ptr;
            s->real_gpu = 0; g.ptr = 0;
            if (desc->Flags & D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE) { ((FG)e->orig[S_HGPU])(hp, &g); s->real_gpu = g.ptr; }
            s->n = desc->NumDescriptors;
            s->fake_cpu = st_alloc_range(&st_next_cpu, st_cpu_end, s->n);
            s->fake_gpu = s->real_gpu ? st_alloc_range(&st_next_gpu, 0, s->n) : 0;
            if (!s->fake_cpu) { st_log("STRIDE heap %p: fake CPU window exhausted, heap NOT translated", hp); InterlockedIncrement(&st_heap_overflow); }
            else {
                st_hptr[n] = hp; InterlockedExchange(&st_nheap, n + 1);
                st_log("STRIDE heap=%p type=CBV_SRV_UAV N=%u flags=0x%x real_cpu=0x%llx real_gpu=0x%llx fake_cpu=0x%llx fake_gpu=0x%llx real_bytes=%llu fake_bytes=%llu (heaps=%d)",
                    hp, s->n, (unsigned)desc->Flags, (unsigned long long)s->real_cpu, (unsigned long long)s->real_gpu, (unsigned long long)s->fake_cpu,
                    (unsigned long long)s->fake_gpu, (unsigned long long)s->n * (unsigned)st_real_inc, (unsigned long long)s->n * ST_FAKE_INC, n + 1);
            }
        } else { st_log("STRIDE heap %p: registry/table full, heap NOT translated", hp); InterlockedIncrement(&st_heap_overflow); }
    }
    LeaveCriticalSection(&st_cs);
    ((IUnknown *)hp)->lpVtbl->Release((IUnknown *)hp);
}
static HRESULT STDMETHODCALLTYPE st_CDH(void *d, const D3D12_DESCRIPTOR_HEAP_DESC *desc, REFIID r, void **o)
{
    ENT(d, S_CDH); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, const D3D12_DESCRIPTOR_HEAP_DESC *, REFIID, void **))e->orig[S_CDH])(d, desc, r, o);
    if (SUCCEEDED(hr) && o && *o && st_active) st_new_heap(*o, desc);
    return hr;
}

// ---- command lists -------------------------------------------------------------------------------
static void *st_lprobed[16]; static int st_nlprobed;
static void st_patch_list(void *list)
{
    static const IID *const ids[] = { &IID_ID3D12GraphicsCommandList, &IID_ID3D12GraphicsCommandList1, &IID_ID3D12GraphicsCommandList2,
        &IID_ID3D12GraphicsCommandList3, &IID_ID3D12GraphicsCommandList4, &IID_ID3D12GraphicsCommandList5, &IID_ID3D12GraphicsCommandList6
#ifdef __ID3D12GraphicsCommandList7_INTERFACE_DEFINED__
        , &IID_ID3D12GraphicsCommandList7
#endif
    };
    void **vt0 = *(void ***)list; int i;
    EnterCriticalSection(&st_cs);
    for (i = 0; i < st_nlprobed; i++) if (st_lprobed[i] == (void *)vt0) { LeaveCriticalSection(&st_cs); return; }
    if (st_nlprobed < 16) st_lprobed[st_nlprobed++] = (void *)vt0;
    LeaveCriticalSection(&st_cs);
    for (i = 0; i < (int)(sizeof ids / sizeof *ids); i++) {
        void *p = NULL;
        if (FAILED(((IUnknown *)list)->lpVtbl->QueryInterface((IUnknown *)list, ids[i], &p)) || !p) continue;
        st_reg(p, SK_LIST, i); ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
    }
}
static HRESULT STDMETHODCALLTYPE st_CCL(void *d, UINT m, D3D12_COMMAND_LIST_TYPE t, void *a, void *p, REFIID r, void **o)
{
    ENT(d, S_CCL); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, UINT, D3D12_COMMAND_LIST_TYPE, void *, void *, REFIID, void **))e->orig[S_CCL])(d, m, t, a, p, r, o);
    if (SUCCEEDED(hr) && o && *o) st_patch_list(*o);
    return hr;
}
static HRESULT STDMETHODCALLTYPE st_CCL1(void *d, UINT m, D3D12_COMMAND_LIST_TYPE t, UINT f, REFIID r, void **o)
{
    ENT(d, S_CCL1); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, UINT, D3D12_COMMAND_LIST_TYPE, UINT, REFIID, void **))e->orig[S_CCL1])(d, m, t, f, r, o);
    if (SUCCEEDED(hr) && o && *o) st_patch_list(*o);
    return hr;
}

// ---- UMD driver version (IDXGIAdapter::CheckInterfaceSupport) ------------------------------------
static void *st_aprobed[16]; static int st_naprobed;
static void st_patch_adapter(void *ad)
{
    static const IID *const ids[] = { &IID_IDXGIAdapter, &IID_IDXGIAdapter1, &IID_IDXGIAdapter2, &IID_IDXGIAdapter3, &IID_IDXGIAdapter4 };
    void **vt0 = *(void ***)ad; int i;
    EnterCriticalSection(&st_cs);
    for (i = 0; i < st_naprobed; i++) if (st_aprobed[i] == (void *)vt0) { LeaveCriticalSection(&st_cs); return; }
    if (st_naprobed < 16) st_aprobed[st_naprobed++] = (void *)vt0;
    LeaveCriticalSection(&st_cs);
    for (i = 0; i < (int)(sizeof ids / sizeof *ids); i++) {
        void *p = NULL;
        if (FAILED(((IUnknown *)ad)->lpVtbl->QueryInterface((IUnknown *)ad, ids[i], &p)) || !p) continue;
        st_reg(p, SK_AD, i); InterlockedExchange(&st_umd_patched, 1); ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
    }
}
static HRESULT STDMETHODCALLTYPE st_CIS(void *a, REFGUID iid, LARGE_INTEGER *v)
{
    ENT(a, S_CIS); HRESULT hr; LONG n; ULONGLONG before = 0; HRESULT orig_hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, REFGUID, LARGE_INTEGER *))e->orig[S_CIS])(a, iid, v);
    orig_hr = hr; if (v) before = (ULONGLONG)v->QuadPart;
    n = InterlockedIncrement(&st_umd_calls);
    if (st_umd_enabled && v && (FAILED(hr) || before == 0)) { v->QuadPart = (LONGLONG)st_umd_ver; hr = S_OK; }
    if (n <= 10)
        st_log("STRIDE UMD CheckInterfaceSupport #%ld iid={%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x} orig_hr=0x%08lx orig_value=%llu.%llu.%llu.%llu -> hr=0x%08lx value=%llu.%llu.%llu.%llu",
            (long)n, iid->Data1, iid->Data2, iid->Data3, iid->Data4[0], iid->Data4[1], iid->Data4[2], iid->Data4[3], iid->Data4[4], iid->Data4[5], iid->Data4[6], iid->Data4[7],
            (unsigned long)orig_hr, before >> 48, (before >> 32) & 0xFFFF, (before >> 16) & 0xFFFF, before & 0xFFFF,
            (unsigned long)hr, v ? (ULONGLONG)v->QuadPart >> 48 : 0, v ? ((ULONGLONG)v->QuadPart >> 32) & 0xFFFF : 0, v ? ((ULONGLONG)v->QuadPart >> 16) & 0xFFFF : 0, v ? (ULONGLONG)v->QuadPart & 0xFFFF : 0);
    return hr;
}
static HRESULT STDMETHODCALLTYPE st_EA(void *f, UINT i, IDXGIAdapter **o)
{
    ENT(f, S_EA); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, UINT, IDXGIAdapter **))e->orig[S_EA])(f, i, o);
    if (SUCCEEDED(hr) && o && *o) st_patch_adapter(*o);
    return hr;
}
static HRESULT STDMETHODCALLTYPE st_EA1(void *f, UINT i, IDXGIAdapter1 **o)
{
    ENT(f, S_EA1); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, UINT, IDXGIAdapter1 **))e->orig[S_EA1])(f, i, o);
    if (SUCCEEDED(hr) && o && *o) st_patch_adapter(*o);
    return hr;
}
static HRESULT STDMETHODCALLTYPE st_EABL(void *f, LUID l, REFIID r, void **o)
{
    ENT(f, S_EABL); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, LUID, REFIID, void **))e->orig[S_EABL])(f, l, r, o);
    if (SUCCEEDED(hr) && o && *o) st_patch_adapter(*o);
    return hr;
}
static HRESULT STDMETHODCALLTYPE st_EABGP(void *f, UINT i, DXGI_GPU_PREFERENCE p, REFIID r, void **o)
{
    ENT(f, S_EABGP); HRESULT hr;
    if (!e) return E_FAIL;
    hr = ((HRESULT (STDMETHODCALLTYPE *)(void *, UINT, DXGI_GPU_PREFERENCE, REFIID, void **))e->orig[S_EABGP])(f, i, p, r, o);
    if (SUCCEEDED(hr) && o && *o) st_patch_adapter(*o);
    return hr;
}
static void st_dxgi_init(void)
{
    typedef HRESULT (WINAPI *PFN)(REFIID, void **);
    static int done; HMODULE m; PFN f; void *fac = NULL, *ad = NULL; HRESULT hr;
    static const struct { const IID *id; int level; } fe[] = { { &IID_IDXGIFactory, 0 }, { &IID_IDXGIFactory1, 1 }, { &IID_IDXGIFactory2, 1 },
        { &IID_IDXGIFactory3, 1 }, { &IID_IDXGIFactory4, 4 }, { &IID_IDXGIFactory5, 4 }, { &IID_IDXGIFactory6, 6 }, { &IID_IDXGIFactory7, 6 } };
    int i;
    if (done) return; done = 1;
    m = LoadLibraryA("dxgi.dll"); f = m ? (PFN)GetProcAddress(m, "CreateDXGIFactory1") : NULL;
    if (!f) { st_log("STRIDE UMD: dxgi.dll / CreateDXGIFactory1 unavailable, adapter hook SKIPPED"); return; }
    hr = f(&IID_IDXGIFactory1, &fac);
    if (FAILED(hr) || !fac) { st_log("STRIDE UMD: CreateDXGIFactory1 hr=0x%08lx, adapter hook SKIPPED", (unsigned long)hr); return; }
    for (i = 0; i < (int)(sizeof fe / sizeof *fe); i++) {
        void *p = NULL;
        if (FAILED(((IUnknown *)fac)->lpVtbl->QueryInterface((IUnknown *)fac, fe[i].id, &p)) || !p) continue;
        st_reg(p, SK_FAC, fe[i].level); ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
    }
    hr = ((IDXGIFactory1 *)fac)->lpVtbl->EnumAdapters1((IDXGIFactory1 *)fac, 0, (IDXGIAdapter1 **)&ad);   // our own hooks patch the adapter
    if (FAILED(hr) || !ad) st_log("STRIDE UMD: EnumAdapters1(0) hr=0x%08lx, adapters will be patched when the game enumerates them", (unsigned long)hr);
    else ((IUnknown *)ad)->lpVtbl->Release((IUnknown *)ad);
    ((IUnknown *)fac)->lpVtbl->Release((IUnknown *)fac);
    st_log("STRIDE UMD: adapter CheckInterfaceSupport hook %s (version %llu.%llu.%llu.%llu)", st_umd_patched ? "installed" : "NOT installed", st_umd_ver >> 48,
        (st_umd_ver >> 32) & 0xFFFF, (st_umd_ver >> 16) & 0xFFFF, st_umd_ver & 0xFFFF);
}

// ---- init / device patch -------------------------------------------------------------------------
static void stride_init(void)   // DllMain
{
    char v[64]; DWORD n; static const SIZE_T sizes[] = { 64ull << 30, 16ull << 30, 4ull << 30 }; int i;
    InitializeCriticalSection(&st_cs);
    st_start_tick = GetTickCount64();
    st_umd_ver = ((ULONGLONG)32 << 48) | ((ULONGLONG)0 << 32) | ((ULONGLONG)15 << 16) | 9700;
    n = GetEnvironmentVariableA("HB_DESC_STRIDE", v, sizeof v);
    if (n && n < sizeof v && v[0] == '0') st_enabled = 0;
    n = GetEnvironmentVariableA("HB_UMD_VERSION", v, sizeof v);
    if (n && n < sizeof v) {
        unsigned a, b, c, d;
        if (v[0] == '0' && !v[1]) st_umd_enabled = 0;
        else if (sscanf(v, "%u.%u.%u.%u", &a, &b, &c, &d) == 4)
            st_umd_ver = ((ULONGLONG)(a & 0xFFFF) << 48) | ((ULONGLONG)(b & 0xFFFF) << 32) | ((ULONGLONG)(c & 0xFFFF) << 16) | (d & 0xFFFF);
    }
    st_next_gpu = 0x7f0000000000ull;
    for (i = 0; i < 3; i++) {   // private window for fake CPU handles; falls back to a fixed high range if the reserve fails
        void *w = VirtualAlloc(NULL, sizes[i], MEM_RESERVE, PAGE_NOACCESS);
        if (w) { st_next_cpu = (ULONGLONG)(uintptr_t)w; st_cpu_end = st_next_cpu + sizes[i]; break; }
    }
    if (!st_next_cpu) { st_next_cpu = 0x6e0000000000ull; st_cpu_end = 0; }
}
static void stride_patch_device(ID3D12Device *dev)
{
    static const GUID iid10 = { 0x517f8718, 0xaa66, 0x49f9, { 0xb0, 0x2b, 0xa7, 0xab, 0x89, 0xc0, 0x60, 0x31 } };
    const IID *ids[11] = { 0 }; int lv;
    if (!st_inited) {   // the real increment is read once, from the first device, before any of our hooks exist
        st_inited = 1;
        st_real_inc = (LONG)dev->lpVtbl->GetDescriptorHandleIncrementSize(dev, D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
        st_active = st_enabled && st_real_inc > 0 && st_real_inc < (LONG)ST_FAKE_INC;
        st_log("STRIDE init build=%s real_inc=%ld fake_inc=%u HB_DESC_STRIDE=%s -> %s; cpu window 0x%llx..0x%llx; UMD hook %s", ST_BUILD, (long)st_real_inc, ST_FAKE_INC,
            st_enabled ? "on" : "0", st_active ? "ACTIVE (translating)" : "passthrough", (unsigned long long)st_next_cpu, (unsigned long long)st_cpu_end, st_umd_enabled ? "on" : "off");
    }
    if (st_active) {
        ID3D12CommandAllocator *alloc = NULL; ID3D12GraphicsCommandList *list = NULL;
        ids[1] = &IID_ID3D12Device1; ids[2] = &IID_ID3D12Device2; ids[3] = &IID_ID3D12Device3; ids[4] = &IID_ID3D12Device4;
        ids[5] = &IID_ID3D12Device5; ids[6] = &IID_ID3D12Device6; ids[7] = &IID_ID3D12Device7; ids[8] = &IID_ID3D12Device8;
        ids[9] = &IID_ID3D12Device9; ids[10] = &iid10;
        st_reg(dev, SK_DEV, 0);
        for (lv = 1; lv <= 10; lv++) {
            void *p = NULL;
            if (FAILED(dev->lpVtbl->QueryInterface(dev, ids[lv], &p)) || !p) continue;
            st_reg(p, SK_DEV, lv); ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
        }
        // register the command-list tables up front with a throwaway list
        if (SUCCEEDED(dev->lpVtbl->CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&alloc)) && alloc) {
            if (SUCCEEDED(dev->lpVtbl->CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, NULL, &IID_ID3D12GraphicsCommandList, (void **)&list)) && list) {
                st_patch_list(list); list->lpVtbl->Close(list); list->lpVtbl->Release(list);
            }
            alloc->lpVtbl->Release(alloc);
        }
    }
    if (st_umd_enabled) st_dxgi_init();
    st_reapply_all();   // the shim / faillog may have overwritten slots during this device's patching
}
