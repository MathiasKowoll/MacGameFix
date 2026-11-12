// frame_trace: what the game asks of D3D12 around each frame, for one diagnostic run.
//
// Forza Horizon 6 at rest shows a 100-200 ms frame every ~10 s. Metal's own statistics show no slow frame
// in those seconds (CPU encode under 8 ms, end-to-end under 41 ms, a normal drawable wait), so the time is
// lost before Metal sees the frame. This records when the game submits work and how long each call into
// D3DMetal takes, so a gap can be put in one of three places: the game stopped submitting, a D3DMetal call
// blocked, or the game asked to wait on a fence.
//
// MGF_FH6_FRAME_TRACE=1 turns it on; otherwise nothing is hooked and nothing is written. Recorded:
//   E ExecuteCommandLists   a queue   b list count        c queue type
//   S queue Signal          a fence   b value             c queue type
//   W queue Wait            a fence   b value             c queue type
//   T UpdateTileMappings    a resource b range count      c queue type
//   F fence SetEventOnCompletion  a fence  b value        c 1 with an event, 0 without (blocks in the call)
//   f fence Signal from the CPU   a fence  b value
//   C/P/R committed, placed, reserved resource  a width  b height << 32 | depth or array size  c dimension
//   H CreateHeap            a size in bytes
//   M MakeResident, V Evict b object count
// Each record has its start on the performance counter, its duration and the calling thread. The records
// go into a ring in memory; a thread of its own writes them to C:\mgf\fh6-frame-<pid>.log every second,
// with an anchor line pairing the counter with the system time and the name of each new thread. Nothing
// is written from the game's own threads. Records the writer could not keep up with are counted.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef MGF_FRAME_TRACE_H
#define MGF_FRAME_TRACE_H

void patch_slot(void **slot, void *hook, void **saved);

#define FT_CAPACITY (1 << 18)
struct ft_record { LONGLONG start, ticks; UINT64 a, b; DWORD tid, c; LONG kind; volatile LONG ready; };
static struct ft_record *ft_records;
static volatile LONG64 ft_next, ft_done;
static volatile LONG ft_dropped;
static int frame_trace;

static inline LONGLONG ft_now(void) { LARGE_INTEGER q; QueryPerformanceCounter(&q); return q.QuadPart; }
static void ft_add(char kind, LONGLONG start, UINT64 a, UINT64 b, DWORD c)
{
    LONGLONG end = ft_now();
    LONG64 i;
    struct ft_record *r;
    // An index is taken only when its slot is free, so every taken index is filled and the writer never
    // waits on one that was given up.
    do {
        i = ft_next;
        if (i - ft_done >= FT_CAPACITY) { InterlockedIncrement(&ft_dropped); return; }
    } while (InterlockedCompareExchange64(&ft_next, i + 1, i) != i);
    r = &ft_records[i & (FT_CAPACITY - 1)];
    r->start = start; r->ticks = end - start; r->a = a; r->b = b; r->c = c;
    r->tid = GetCurrentThreadId(); r->kind = kind;
    InterlockedExchange(&r->ready, 1);
}

// Queue type, looked up once per queue.
static struct { ID3D12CommandQueue *q; DWORD type; } ft_queues[64];
static volatile LONG ft_nqueues;
static DWORD ft_queue_type(ID3D12CommandQueue *q)
{
    D3D12_COMMAND_QUEUE_DESC d; LONG i, n = ft_nqueues;
    for (i = 0; i < n && i < 64; i++) if (ft_queues[i].q == q) return ft_queues[i].type;
    q->lpVtbl->GetDesc(q, &d);
    if ((i = InterlockedIncrement(&ft_nqueues) - 1) < 64) { ft_queues[i].type = d.Type; ft_queues[i].q = q; }
    return d.Type;
}

static void (STDMETHODCALLTYPE *ft_real_Execute)(ID3D12CommandQueue *, UINT, ID3D12CommandList *const *);
static HRESULT (STDMETHODCALLTYPE *ft_real_QSignal)(ID3D12CommandQueue *, ID3D12Fence *, UINT64);
static HRESULT (STDMETHODCALLTYPE *ft_real_QWait)(ID3D12CommandQueue *, ID3D12Fence *, UINT64);
static void (STDMETHODCALLTYPE *ft_real_Tiles)(ID3D12CommandQueue *, ID3D12Resource *, UINT, const D3D12_TILED_RESOURCE_COORDINATE *, const D3D12_TILE_REGION_SIZE *, ID3D12Heap *, UINT, const D3D12_TILE_RANGE_FLAGS *, const UINT *, const UINT *, D3D12_TILE_MAPPING_FLAGS);
static void STDMETHODCALLTYPE ft_Execute(ID3D12CommandQueue *q, UINT n, ID3D12CommandList *const *lists)
{
    LONGLONG t = ft_now();
    ft_real_Execute(q, n, lists);
    ft_add('E', t, (UINT64)(ULONG_PTR)q, n, ft_queue_type(q));
}
static HRESULT STDMETHODCALLTYPE ft_QSignal(ID3D12CommandQueue *q, ID3D12Fence *f, UINT64 v)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_QSignal(q, f, v);
    ft_add('S', t, (UINT64)(ULONG_PTR)f, v, ft_queue_type(q));
    return hr;
}
static HRESULT STDMETHODCALLTYPE ft_QWait(ID3D12CommandQueue *q, ID3D12Fence *f, UINT64 v)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_QWait(q, f, v);
    ft_add('W', t, (UINT64)(ULONG_PTR)f, v, ft_queue_type(q));
    return hr;
}
static void STDMETHODCALLTYPE ft_Tiles(ID3D12CommandQueue *q, ID3D12Resource *res, UINT n, const D3D12_TILED_RESOURCE_COORDINATE *coords, const D3D12_TILE_REGION_SIZE *sizes, ID3D12Heap *heap, UINT ranges, const D3D12_TILE_RANGE_FLAGS *flags, const UINT *offsets, const UINT *counts, D3D12_TILE_MAPPING_FLAGS mf)
{
    LONGLONG t = ft_now();
    ft_real_Tiles(q, res, n, coords, sizes, heap, ranges, flags, offsets, counts, mf);
    ft_add('T', t, (UINT64)(ULONG_PTR)res, ranges, ft_queue_type(q));
}
static void ft_patch_queue(void *iface)
{
    ID3D12CommandQueueVtbl *vt = *(ID3D12CommandQueueVtbl **)iface;
    if (!frame_trace) return;
    patch_slot((void **)&vt->ExecuteCommandLists, (void *)ft_Execute, (void **)&ft_real_Execute);
    patch_slot((void **)&vt->Signal, (void *)ft_QSignal, (void **)&ft_real_QSignal);
    patch_slot((void **)&vt->Wait, (void *)ft_QWait, (void **)&ft_real_QWait);
    patch_slot((void **)&vt->UpdateTileMappings, (void *)ft_Tiles, (void **)&ft_real_Tiles);
}

static HRESULT (STDMETHODCALLTYPE *ft_real_SetEvent)(ID3D12Fence *, UINT64, HANDLE);
static HRESULT (STDMETHODCALLTYPE *ft_real_FSignal)(ID3D12Fence *, UINT64);
static HRESULT STDMETHODCALLTYPE ft_SetEvent(ID3D12Fence *f, UINT64 v, HANDLE e)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_SetEvent(f, v, e);
    ft_add('F', t, (UINT64)(ULONG_PTR)f, v, e != NULL);
    return hr;
}
static HRESULT STDMETHODCALLTYPE ft_FSignal(ID3D12Fence *f, UINT64 v)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_FSignal(f, v);
    ft_add('f', t, (UINT64)(ULONG_PTR)f, v, 0);
    return hr;
}
static HRESULT (STDMETHODCALLTYPE *ft_real_CreateFence)(ID3D12Device *, UINT64, D3D12_FENCE_FLAGS, REFIID, void **);
static HRESULT STDMETHODCALLTYPE ft_CreateFence(ID3D12Device *dev, UINT64 v, D3D12_FENCE_FLAGS fl, REFIID riid, void **out)
{
    HRESULT hr = ft_real_CreateFence(dev, v, fl, riid, out);
    if (SUCCEEDED(hr) && out && *out) {
        ID3D12Fence *f = NULL;
        if (SUCCEEDED(((IUnknown *)*out)->lpVtbl->QueryInterface((IUnknown *)*out, &IID_ID3D12Fence, (void **)&f)) && f) {
            ID3D12FenceVtbl *vt = f->lpVtbl;
            patch_slot((void **)&vt->SetEventOnCompletion, (void *)ft_SetEvent, (void **)&ft_real_SetEvent);
            patch_slot((void **)&vt->Signal, (void *)ft_FSignal, (void **)&ft_real_FSignal);
            f->lpVtbl->Release(f);
        }
    }
    return hr;
}
static HRESULT (STDMETHODCALLTYPE *ft_real_CreateHeap)(ID3D12Device *, const D3D12_HEAP_DESC *, REFIID, void **);
static HRESULT STDMETHODCALLTYPE ft_CreateHeap(ID3D12Device *dev, const D3D12_HEAP_DESC *d, REFIID riid, void **out)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_CreateHeap(dev, d, riid, out);
    ft_add('H', t, d ? d->SizeInBytes : 0, 0, 0);
    return hr;
}
static HRESULT (STDMETHODCALLTYPE *ft_real_MakeResident)(ID3D12Device *, UINT, ID3D12Pageable *const *);
static HRESULT (STDMETHODCALLTYPE *ft_real_Evict)(ID3D12Device *, UINT, ID3D12Pageable *const *);
static HRESULT STDMETHODCALLTYPE ft_MakeResident(ID3D12Device *dev, UINT n, ID3D12Pageable *const *o)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_MakeResident(dev, n, o);
    ft_add('M', t, 0, n, 0);
    return hr;
}
static HRESULT STDMETHODCALLTYPE ft_Evict(ID3D12Device *dev, UINT n, ID3D12Pageable *const *o)
{
    LONGLONG t = ft_now(); HRESULT hr = ft_real_Evict(dev, n, o);
    ft_add('V', t, 0, n, 0);
    return hr;
}
// Resource creations go through the shim's own resource hooks, which call this.
static void ft_resource(char kind, LONGLONG start, const D3D12_RESOURCE_DESC *d)
{
    if (frame_trace) ft_add(kind, start, d ? d->Width : 0, d ? ((UINT64)d->Height << 32) | d->DepthOrArraySize : 0, d ? (DWORD)d->Dimension : 0);
}
static void ft_patch_device(ID3D12DeviceVtbl *vt, int inspect_has_heap)
{
    if (!frame_trace) return;
    patch_slot((void **)&vt->CreateFence, (void *)ft_CreateFence, (void **)&ft_real_CreateFence);
    patch_slot((void **)&vt->MakeResident, (void *)ft_MakeResident, (void **)&ft_real_MakeResident);
    patch_slot((void **)&vt->Evict, (void *)ft_Evict, (void **)&ft_real_Evict);
    if (!inspect_has_heap) patch_slot((void **)&vt->CreateHeap, (void *)ft_CreateHeap, (void **)&ft_real_CreateHeap);
}

static DWORD ft_seen[1024]; static int ft_nseen;
static void ft_name(FILE *f, DWORD tid)
{
    int i; HANDLE h; PWSTR w = NULL;
    for (i = 0; i < ft_nseen; i++) if (ft_seen[i] == tid) return;
    if (ft_nseen < 1024) ft_seen[ft_nseen++] = tid;
    if ((h = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE, tid))) {
        if (SUCCEEDED(GetThreadDescription(h, &w)) && w) { fprintf(f, "N %lu %ls\n", (unsigned long)tid, w); LocalFree(w); }
        else fprintf(f, "N %lu ?\n", (unsigned long)tid);
        CloseHandle(h);
    }
}
static DWORD WINAPI ft_writer(LPVOID path)
{
    FILE *f = fopen((const char *)path, "w");
    LARGE_INTEGER freq;
    if (!f) return 0;
    QueryPerformanceFrequency(&freq);
    fprintf(f, "# fh6 frame trace: kind start_qpc duration_us tid a b c (see frame_trace.h); N tid name; A qpc filetime dropped\n");
    fprintf(f, "# qpc_frequency %lld\n", (long long)freq.QuadPart);
    for (;;) {
        FILETIME ft; LONGLONG q = ft_now();
        GetSystemTimePreciseAsFileTime(&ft);
        fprintf(f, "A %lld %llu dropped %ld\n", (long long)q, ((unsigned long long)ft.dwHighDateTime << 32) | ft.dwLowDateTime, (long)ft_dropped);
        for (;;) {
            struct ft_record *r = &ft_records[ft_done & (FT_CAPACITY - 1)];
            if (ft_done >= ft_next || !r->ready) break;
            ft_name(f, r->tid);
            fprintf(f, "%c %lld %lld %lu %llx %llx %lu\n", (char)r->kind, (long long)r->start,
                    (long long)(r->ticks * 1000000 / freq.QuadPart), (unsigned long)r->tid,
                    (unsigned long long)r->a, (unsigned long long)r->b, (unsigned long)r->c);
            InterlockedExchange(&r->ready, 0);
            InterlockedIncrement64(&ft_done);
        }
        fflush(f);
        Sleep(1000);
    }
    return 0;
}
static void ft_init(void)
{
    static char path[MAX_PATH];
    char v[8];
    frame_trace = GetEnvironmentVariableA("MGF_FH6_FRAME_TRACE", v, sizeof v) == 1 && v[0] == '1';
    if (!frame_trace) return;
    ft_records = VirtualAlloc(NULL, sizeof(struct ft_record) * FT_CAPACITY, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!ft_records) { frame_trace = 0; return; }
    CreateDirectoryA("C:\\mgf", NULL);
    snprintf(path, sizeof path, "C:\\mgf\\fh6-frame-%lu.log", (unsigned long)GetCurrentProcessId());
    CloseHandle(CreateThread(NULL, 0, ft_writer, path, 0, NULL));
}
#endif
