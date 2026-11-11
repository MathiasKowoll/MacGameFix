// faillog: diagnostic layer (build id faillog-2). Logs only failing D3D12 device / pipeline-library calls
// (FAILED(hr), or S_OK with a NULL returned object), keeps per-method ok/fail counters, always on.
// Hooks are layered on top of whatever the vtable slot holds after the shim's own patching, so shim behaviour
// is unchanged. Log: C:\highball\logs\d3d12-faillog-<pid>.log
#include <dxgi1_4.h>
#define FL_BUILD "stride-1"
enum { FL_CCQ, FL_CCA, FL_CGPS, FL_CCPS, FL_CCL, FL_CFS, FL_CDH, FL_CRS, FL_CCR, FL_CH, FL_CPR, FL_CRR, FL_CSH, FL_OSH,
       FL_MR, FL_EV, FL_GDRR, FL_CQH, FL_CPL, FL_SRP, FL_CPS2, FL_EMR, FL_CCL1, FL_CCR1, FL_CH1, FL_CRR1, FL_CCR2,
       FL_CPR1, FL_CCQ1, FL_CCR3, FL_CPR2, FL_CRR2, FL_LGP, FL_LCP, FL_LP, FL_STP, FL_CFSUP,
       FL_QSignal, FL_QWait, FL_QGTF, FL_QGCC, FL_QUTM, FL_QCTM, FL_QECL, FL_FSEOC, FL_FSignal, FL_LClose, FL_LReset, FL_AReset, FL_RMap,
       FL_AQVMI, FL_ASVMR, FL_ARVMB, FL_FCSC, FL_FCSCH, FL_FCSCC, FL_SPresent, FL_SPresent1, FL_SResize, FL_SResize1, FL_SGetBuffer, FL_N };
static const char *const fl_names[FL_N] = { "CreateCommandQueue", "CreateCommandAllocator", "CreateGraphicsPipelineState",
    "CreateComputePipelineState", "CreateCommandList", "CreateFence", "CreateDescriptorHeap", "CreateRootSignature",
    "CreateCommittedResource", "CreateHeap", "CreatePlacedResource", "CreateReservedResource", "CreateSharedHandle",
    "OpenSharedHandle", "MakeResident", "Evict", "GetDeviceRemovedReason", "CreateQueryHeap", "CreatePipelineLibrary",
    "SetResidencyPriority", "CreatePipelineState", "EnqueueMakeResident", "CreateCommandList1", "CreateCommittedResource1",
    "CreateHeap1", "CreateReservedResource1", "CreateCommittedResource2", "CreatePlacedResource1", "CreateCommandQueue1",
    "CreateCommittedResource3", "CreatePlacedResource2", "CreateReservedResource2", "LoadGraphicsPipeline",
    "LoadComputePipeline", "LoadPipeline", "StorePipeline", "CheckFeatureSupport",
    "Queue::Signal", "Queue::Wait", "Queue::GetTimestampFrequency", "Queue::GetClockCalibration", "Queue::UpdateTileMappings",
    "Queue::CopyTileMappings", "Queue::ExecuteCommandLists", "Fence::SetEventOnCompletion", "Fence::Signal", "CmdList::Close",
    "CmdList::Reset", "CmdAlloc::Reset", "Resource::Map", "Adapter3::QueryVideoMemoryInfo", "Adapter3::SetVideoMemoryReservation",
    "Adapter3::RegisterVideoMemoryBudgetChangeNotificationEvent", "Factory::CreateSwapChain", "Factory2::CreateSwapChainForHwnd",
    "Factory2::CreateSwapChainForComposition", "SwapChain::Present", "SwapChain1::Present1", "SwapChain::ResizeBuffers",
    "SwapChain3::ResizeBuffers1", "SwapChain::GetBuffer" };
static volatile LONG fl_ok[FL_N], fl_fail[FL_N];
static CRITICAL_SECTION fl_lock; static FILE *fl_file; static ULONGLONG fl_last_dump; static int fl_thread_started;

extern int hb_debug;   // d3d12.c: HB_DEBUG=1
static void fl_write(const char *msg)
{
    if (!fl_file) return;
    fprintf(fl_file, "%llu t%lu %s\n", (unsigned long long)GetTickCount64(), (unsigned long)GetCurrentThreadId(), msg);
    fflush(fl_file);
}
static void fl_dump_locked(const char *why)
{
    char b[4096]; int n = 0, i;
    n += snprintf(b + n, sizeof b - n, "COUNTERS(%s) ok/fail:", why);
    for (i = 0; i < FL_N && n < (int)sizeof b - 80; i++)
        if (fl_ok[i] || fl_fail[i]) n += snprintf(b + n, sizeof b - n, " %s=%ld/%ld", fl_names[i], (long)fl_ok[i], (long)fl_fail[i]);
    fl_write(b); fl_last_dump = GetTickCount64();
}
static void fl_init(void)
{
    char path[MAX_PATH], h[128];
    InitializeCriticalSection(&fl_lock);
    if (!hb_debug) return;   // play build: no log file, no hooks, no counters
    CreateDirectoryA("C:\\highball", NULL); CreateDirectoryA("C:\\highball\\logs", NULL);
    snprintf(path, sizeof path, "C:\\highball\\logs\\d3d12-faillog-%lu.log", (unsigned long)GetCurrentProcessId());
    fl_file = fopen(path, "a");
    snprintf(h, sizeof h, "HEADER build=%s pid=%lu", FL_BUILD, (unsigned long)GetCurrentProcessId());
    EnterCriticalSection(&fl_lock); fl_write(h); LeaveCriticalSection(&fl_lock);
}
static void stride_dump_locked(void);   // stride.h
static DWORD WINAPI fl_thread(LPVOID p)
{
    (void)p;
    for (;;) { Sleep(30000); EnterCriticalSection(&fl_lock); fl_dump_locked("30s"); stride_dump_locked(); LeaveCriticalSection(&fl_lock); }
    return 0;
}
// fl_bad: failure, or success with a NULL returned object. fl_note: counts, and says whether to log (rate limit: first 50, then every 100th)
static int fl_bad(HRESULT hr, void **out) { return FAILED(hr) || (hr == S_OK && out && !*out); }
static int fl_note(int id, int bad)
{
    LONG n;
    if (!bad) { InterlockedIncrement(&fl_ok[id]); return 0; }
    n = InterlockedIncrement(&fl_fail[id]);
    return n <= 50 || n % 100 == 0;
}
static ID3D12Device *fl_dev;   // latest patched device (AddRef'd), used for the DeviceRemovedReason suffix
static int fl_drr_str(char *b, size_t n);   // defined after the saved-original pointers
static void fl_log(int id, HRESULT hr, const char *fmt, ...)
{
    char b[1400]; int n; size_t l; va_list ap;
    n = snprintf(b, sizeof b, "%s FAIL hr=0x%08lx n=%ld ", fl_names[id], (unsigned long)hr, (long)fl_fail[id]);
    va_start(ap, fmt); vsnprintf(b + n, sizeof b - n, fmt, ap); va_end(ap);
    l = strlen(b); if (l > sizeof b - 48) l = sizeof b - 48;
    fl_drr_str(b + l, sizeof b - l);   // F) every failure line ends with the device's GetDeviceRemovedReason
    EnterCriticalSection(&fl_lock);
    fl_write(b);
    if (GetTickCount64() - fl_last_dump > 2000) fl_dump_locked("fail");
    LeaveCriticalSection(&fl_lock);
}
// informational (non-failure) line, no DRR suffix
static void fl_info(int id, const char *fmt, ...)
{
    char b[900]; int n; va_list ap;
    n = snprintf(b, sizeof b, "%s INFO ", fl_names[id]);
    va_start(ap, fmt); vsnprintf(b + n, sizeof b - n, fmt, ap); va_end(ap);
    EnterCriticalSection(&fl_lock); fl_write(b); LeaveCriticalSection(&fl_lock);
}
static const char *fl_res(char *b, size_t n, const D3D12_RESOURCE_DESC *d)
{
    if (!d) return "desc=NULL";
    snprintf(b, n, "dim=%d %llux%u dpth/arr=%u mips=%u fmt=%u samples=%u layout=%d flags=0x%x align=%llu", (int)d->Dimension,
        (unsigned long long)d->Width, (unsigned)d->Height, (unsigned)d->DepthOrArraySize, (unsigned)d->MipLevels, (unsigned)d->Format,
        (unsigned)d->SampleDesc.Count, (int)d->Layout, (unsigned)d->Flags, (unsigned long long)d->Alignment);
    return b;
}
static const char *fl_hp(char *b, size_t n, const D3D12_HEAP_PROPERTIES *p)
{
    if (!p) return "hp=NULL";
    snprintf(b, n, "heaptype=%d cpupage=%d pool=%d", (int)p->Type, (int)p->CPUPageProperty, (int)p->MemoryPoolPreference);
    return b;
}
static const char *fl_hd(char *b, size_t n, const D3D12_HEAP_DESC *d)
{
    if (!d) return "heapdesc=NULL";
    snprintf(b, n, "size=%llu heaptype=%d cpupage=%d pool=%d align=%llu flags=0x%x", (unsigned long long)d->SizeInBytes, (int)d->Properties.Type,
        (int)d->Properties.CPUPageProperty, (int)d->Properties.MemoryPoolPreference, (unsigned long long)d->Alignment, (unsigned)d->Flags);
    return b;
}

// real (next-in-chain) function pointers, saved from the vtable slot at patch time
#define FLR(name, ret, ...) static ret (STDMETHODCALLTYPE *fl_r_##name)(__VA_ARGS__)
FLR(CreateCommandQueue, HRESULT, void *, const D3D12_COMMAND_QUEUE_DESC *, REFIID, void **);
FLR(CreateCommandAllocator, HRESULT, void *, D3D12_COMMAND_LIST_TYPE, REFIID, void **);
FLR(CreateGraphicsPipelineState, HRESULT, void *, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *, REFIID, void **);
FLR(CreateComputePipelineState, HRESULT, void *, const D3D12_COMPUTE_PIPELINE_STATE_DESC *, REFIID, void **);
FLR(CreateCommandList, HRESULT, void *, UINT, D3D12_COMMAND_LIST_TYPE, void *, void *, REFIID, void **);
FLR(CheckFeatureSupport, HRESULT, void *, D3D12_FEATURE, void *, UINT);
FLR(CreateDescriptorHeap, HRESULT, void *, const D3D12_DESCRIPTOR_HEAP_DESC *, REFIID, void **);
FLR(CreateRootSignature, HRESULT, void *, UINT, const void *, SIZE_T, REFIID, void **);
FLR(CreateCommittedResource, HRESULT, void *, const D3D12_HEAP_PROPERTIES *, D3D12_HEAP_FLAGS, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, REFIID, void **);
FLR(CreateHeap, HRESULT, void *, const D3D12_HEAP_DESC *, REFIID, void **);
FLR(CreatePlacedResource, HRESULT, void *, void *, UINT64, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, REFIID, void **);
FLR(CreateReservedResource, HRESULT, void *, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, REFIID, void **);
FLR(CreateSharedHandle, HRESULT, void *, void *, const SECURITY_ATTRIBUTES *, DWORD, LPCWSTR, HANDLE *);
FLR(OpenSharedHandle, HRESULT, void *, HANDLE, REFIID, void **);
FLR(MakeResident, HRESULT, void *, UINT, void *const *);
FLR(Evict, HRESULT, void *, UINT, void *const *);
FLR(CreateFence, HRESULT, void *, UINT64, D3D12_FENCE_FLAGS, REFIID, void **);
FLR(GetDeviceRemovedReason, HRESULT, void *);
FLR(CreateQueryHeap, HRESULT, void *, const D3D12_QUERY_HEAP_DESC *, REFIID, void **);
FLR(CreatePipelineLibrary, HRESULT, void *, const void *, SIZE_T, REFIID, void **);
FLR(SetResidencyPriority, HRESULT, void *, UINT, void *const *, const D3D12_RESIDENCY_PRIORITY *);
FLR(CreatePipelineState, HRESULT, void *, const D3D12_PIPELINE_STATE_STREAM_DESC *, REFIID, void **);
FLR(EnqueueMakeResident, HRESULT, void *, UINT, UINT, void *const *, void *, UINT64);
FLR(CreateCommandList1, HRESULT, void *, UINT, D3D12_COMMAND_LIST_TYPE, UINT, REFIID, void **);
FLR(CreateCommittedResource1, HRESULT, void *, const D3D12_HEAP_PROPERTIES *, D3D12_HEAP_FLAGS, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, void *, REFIID, void **);
FLR(CreateHeap1, HRESULT, void *, const D3D12_HEAP_DESC *, void *, REFIID, void **);
FLR(CreateReservedResource1, HRESULT, void *, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, void *, REFIID, void **);
FLR(CreateCommittedResource2, HRESULT, void *, const D3D12_HEAP_PROPERTIES *, D3D12_HEAP_FLAGS, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, void *, REFIID, void **);
FLR(CreatePlacedResource1, HRESULT, void *, void *, UINT64, const D3D12_RESOURCE_DESC *, D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE *, REFIID, void **);
FLR(CreateCommandQueue1, HRESULT, void *, const D3D12_COMMAND_QUEUE_DESC *, REFIID, REFIID, void **);
FLR(CreateCommittedResource3, HRESULT, void *, const D3D12_HEAP_PROPERTIES *, D3D12_HEAP_FLAGS, const D3D12_RESOURCE_DESC *, UINT, const D3D12_CLEAR_VALUE *, void *, UINT, const DXGI_FORMAT *, REFIID, void **);
FLR(CreatePlacedResource2, HRESULT, void *, void *, UINT64, const D3D12_RESOURCE_DESC *, UINT, const D3D12_CLEAR_VALUE *, UINT, const DXGI_FORMAT *, REFIID, void **);
FLR(CreateReservedResource2, HRESULT, void *, const D3D12_RESOURCE_DESC *, UINT, const D3D12_CLEAR_VALUE *, void *, UINT, const DXGI_FORMAT *, REFIID, void **);
FLR(LoadGraphicsPipeline, HRESULT, void *, LPCWSTR, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *, REFIID, void **);
FLR(LoadComputePipeline, HRESULT, void *, LPCWSTR, const D3D12_COMPUTE_PIPELINE_STATE_DESC *, REFIID, void **);
FLR(LoadPipeline, HRESULT, void *, LPCWSTR, const D3D12_PIPELINE_STATE_STREAM_DESC *, REFIID, void **);
FLR(StorePipeline, HRESULT, void *, LPCWSTR, void *);
// ---- faillog-2: queue / fence / list / allocator / resource / DXGI ----
FLR(QSignal, HRESULT, void *, void *, UINT64);
FLR(QWait, HRESULT, void *, void *, UINT64);
FLR(QGTF, HRESULT, void *, UINT64 *);
FLR(QGCC, HRESULT, void *, UINT64 *, UINT64 *);
FLR(QUTM, void, void *, void *, UINT, const D3D12_TILED_RESOURCE_COORDINATE *, const D3D12_TILE_REGION_SIZE *, void *, UINT, const D3D12_TILE_RANGE_FLAGS *, const UINT *, const UINT *, D3D12_TILE_MAPPING_FLAGS);
FLR(QCTM, void, void *, void *, const D3D12_TILED_RESOURCE_COORDINATE *, void *, const D3D12_TILED_RESOURCE_COORDINATE *, const D3D12_TILE_REGION_SIZE *, D3D12_TILE_MAPPING_FLAGS);
FLR(QECL, void, void *, UINT, void *const *);
FLR(FSEOC, HRESULT, void *, UINT64, HANDLE);
FLR(FSignal, HRESULT, void *, UINT64);
FLR(LClose, HRESULT, void *);
FLR(LReset, HRESULT, void *, void *, void *);
FLR(AReset, HRESULT, void *);
FLR(RMap, HRESULT, void *, UINT, const D3D12_RANGE *, void **);
FLR(AQVMI, HRESULT, void *, UINT, DXGI_MEMORY_SEGMENT_GROUP, DXGI_QUERY_VIDEO_MEMORY_INFO *);
FLR(ASVMR, HRESULT, void *, UINT, DXGI_MEMORY_SEGMENT_GROUP, UINT64);
FLR(ARVMB, HRESULT, void *, HANDLE, DWORD *);
FLR(FCSC, HRESULT, void *, IUnknown *, DXGI_SWAP_CHAIN_DESC *, void **);
FLR(FCSCH, HRESULT, void *, IUnknown *, HWND, const DXGI_SWAP_CHAIN_DESC1 *, const DXGI_SWAP_CHAIN_FULLSCREEN_DESC *, void *, void **);
FLR(FCSCC, HRESULT, void *, IUnknown *, const DXGI_SWAP_CHAIN_DESC1 *, void *, void **);
FLR(SPresent, HRESULT, void *, UINT, UINT);
FLR(SPresent1, HRESULT, void *, UINT, UINT, const DXGI_PRESENT_PARAMETERS *);
FLR(SResize, HRESULT, void *, UINT, UINT, UINT, DXGI_FORMAT, UINT);
FLR(SResize1, HRESULT, void *, UINT, UINT, UINT, DXGI_FORMAT, UINT, const UINT *, IUnknown *const *);
FLR(SGetBuffer, HRESULT, void *, UINT, REFIID, void **);

static int fl_drr_str(char *b, size_t n)
{
    HRESULT d;
    if (!fl_dev || !fl_r_GetDeviceRemovedReason) return snprintf(b, n, " DRR=nodev");
    d = fl_r_GetDeviceRemovedReason(fl_dev);   // saved original: does not re-enter the logger
    return snprintf(b, n, " DRR=0x%08lx", (unsigned long)d);
}
// per-object patch entry points (defined after FLP), called by the Create* hooks after a successful create
static void fl_obj_queue(void *o); static void fl_obj_fence(void *o); static void fl_obj_list(void *o);
static void fl_obj_alloc(void *o); static void fl_obj_res(void *o); static void fl_obj_sc(void *o);

#define HK static HRESULT STDMETHODCALLTYPE
HK fl_CreateCommandQueue(void *d, const D3D12_COMMAND_QUEUE_DESC *q, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommandQueue(d, q, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_queue(*o);
    if (fl_note(FL_CCQ, fl_bad(hr, o))) fl_log(FL_CCQ, hr, "type=%d prio=%d flags=0x%x", q ? (int)q->Type : -1, q ? (int)q->Priority : -1, q ? (unsigned)q->Flags : 0);
    return hr; }
HK fl_CreateCommandQueue1(void *d, const D3D12_COMMAND_QUEUE_DESC *q, REFIID c, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommandQueue1(d, q, c, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_queue(*o);
    if (fl_note(FL_CCQ1, fl_bad(hr, o))) fl_log(FL_CCQ1, hr, "type=%d prio=%d flags=0x%x", q ? (int)q->Type : -1, q ? (int)q->Priority : -1, q ? (unsigned)q->Flags : 0);
    return hr; }
HK fl_CreateCommandAllocator(void *d, D3D12_COMMAND_LIST_TYPE t, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommandAllocator(d, t, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_alloc(*o);
    if (fl_note(FL_CCA, fl_bad(hr, o))) fl_log(FL_CCA, hr, "type=%d", (int)t);
    return hr; }
HK fl_CreateGraphicsPipelineState(void *d, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *g, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateGraphicsPipelineState(d, g, r, o);
    if (fl_note(FL_CGPS, fl_bad(hr, o))) fl_log(FL_CGPS, hr, "failures_so_far=%ld rts=%u rtv0=%u dsv=%u samples=%u", (long)fl_fail[FL_CGPS],
        g ? g->NumRenderTargets : 0, g ? (unsigned)g->RTVFormats[0] : 0, g ? (unsigned)g->DSVFormat : 0, g ? (unsigned)g->SampleDesc.Count : 0);
    return hr; }
HK fl_CreateComputePipelineState(void *d, const D3D12_COMPUTE_PIPELINE_STATE_DESC *c, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateComputePipelineState(d, c, r, o);
    if (fl_note(FL_CCPS, fl_bad(hr, o))) fl_log(FL_CCPS, hr, "failures_so_far=%ld cs_len=%llu", (long)fl_fail[FL_CCPS], c ? (unsigned long long)c->CS.BytecodeLength : 0ull);
    return hr; }
HK fl_CreatePipelineState(void *d, const D3D12_PIPELINE_STATE_STREAM_DESC *s, REFIID r, void **o) {
    HRESULT hr = fl_r_CreatePipelineState(d, s, r, o);
    if (fl_note(FL_CPS2, fl_bad(hr, o))) fl_log(FL_CPS2, hr, "failures_so_far=%ld stream_size=%llu", (long)fl_fail[FL_CPS2], s ? (unsigned long long)s->SizeInBytes : 0ull);
    return hr; }
HK fl_CreateCommandList(void *d, UINT m, D3D12_COMMAND_LIST_TYPE t, void *a, void *p, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommandList(d, m, t, a, p, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_list(*o);
    if (fl_note(FL_CCL, fl_bad(hr, o))) fl_log(FL_CCL, hr, "type=%d node=%u", (int)t, m);
    return hr; }
HK fl_CreateCommandList1(void *d, UINT m, D3D12_COMMAND_LIST_TYPE t, UINT f, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommandList1(d, m, t, f, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_list(*o);
    if (fl_note(FL_CCL1, fl_bad(hr, o))) fl_log(FL_CCL1, hr, "type=%d node=%u flags=0x%x", (int)t, m, f);
    return hr; }
HK fl_CheckFeatureSupport(void *d, D3D12_FEATURE f, void *data, UINT sz) {
    HRESULT hr = fl_r_CheckFeatureSupport(d, f, data, sz);
    if (fl_note(FL_CFSUP, FAILED(hr))) fl_log(FL_CFSUP, hr, "feature=%d size=%u", (int)f, sz);
    return hr; }
HK fl_CreateDescriptorHeap(void *d, const D3D12_DESCRIPTOR_HEAP_DESC *h, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateDescriptorHeap(d, h, r, o);
    if (fl_note(FL_CDH, fl_bad(hr, o))) fl_log(FL_CDH, hr, "type=%d num=%u flags=0x%x", h ? (int)h->Type : -1, h ? h->NumDescriptors : 0, h ? (unsigned)h->Flags : 0);
    return hr; }
HK fl_CreateRootSignature(void *d, UINT m, const void *b, SIZE_T l, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateRootSignature(d, m, b, l, r, o);
    if (fl_note(FL_CRS, fl_bad(hr, o))) fl_log(FL_CRS, hr, "blob_len=%llu", (unsigned long long)l);
    return hr; }
HK fl_CreateCommittedResource(void *d, const D3D12_HEAP_PROPERTIES *hp, D3D12_HEAP_FLAGS hf, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommittedResource(d, hp, hf, rd, st, cv, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CCR, fl_bad(hr, o))) { char a[200], b[200]; fl_log(FL_CCR, hr, "%s heapflags=0x%x state=0x%x %s", fl_hp(a, sizeof a, hp), (unsigned)hf, (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateCommittedResource1(void *d, const D3D12_HEAP_PROPERTIES *hp, D3D12_HEAP_FLAGS hf, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, void *ps, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommittedResource1(d, hp, hf, rd, st, cv, ps, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CCR1, fl_bad(hr, o))) { char a[200], b[200]; fl_log(FL_CCR1, hr, "%s heapflags=0x%x state=0x%x %s", fl_hp(a, sizeof a, hp), (unsigned)hf, (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateCommittedResource2(void *d, const D3D12_HEAP_PROPERTIES *hp, D3D12_HEAP_FLAGS hf, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, void *ps, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommittedResource2(d, hp, hf, rd, st, cv, ps, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CCR2, fl_bad(hr, o))) { char a[200], b[200]; fl_log(FL_CCR2, hr, "%s heapflags=0x%x state=0x%x %s", fl_hp(a, sizeof a, hp), (unsigned)hf, (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateCommittedResource3(void *d, const D3D12_HEAP_PROPERTIES *hp, D3D12_HEAP_FLAGS hf, const D3D12_RESOURCE_DESC *rd, UINT layout, const D3D12_CLEAR_VALUE *cv, void *ps, UINT nc, const DXGI_FORMAT *cf, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateCommittedResource3(d, hp, hf, rd, layout, cv, ps, nc, cf, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CCR3, fl_bad(hr, o))) { char a[200], b[200]; fl_log(FL_CCR3, hr, "%s heapflags=0x%x layout=%u %s", fl_hp(a, sizeof a, hp), (unsigned)hf, layout, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateHeap(void *d, const D3D12_HEAP_DESC *h, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateHeap(d, h, r, o);
    if (fl_note(FL_CH, fl_bad(hr, o))) { char a[260]; fl_log(FL_CH, hr, "%s", fl_hd(a, sizeof a, h)); }
    return hr; }
HK fl_CreateHeap1(void *d, const D3D12_HEAP_DESC *h, void *ps, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateHeap1(d, h, ps, r, o);
    if (fl_note(FL_CH1, fl_bad(hr, o))) { char a[260]; fl_log(FL_CH1, hr, "%s", fl_hd(a, sizeof a, h)); }
    return hr; }
HK fl_CreatePlacedResource(void *d, void *h, UINT64 off, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, REFIID r, void **o) {
    HRESULT hr = fl_r_CreatePlacedResource(d, h, off, rd, st, cv, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CPR, fl_bad(hr, o))) { char b[200]; fl_log(FL_CPR, hr, "heap=%p off=%llu state=0x%x %s", h, (unsigned long long)off, (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreatePlacedResource1(void *d, void *h, UINT64 off, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, REFIID r, void **o) {
    HRESULT hr = fl_r_CreatePlacedResource1(d, h, off, rd, st, cv, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CPR1, fl_bad(hr, o))) { char b[200]; fl_log(FL_CPR1, hr, "heap=%p off=%llu state=0x%x %s", h, (unsigned long long)off, (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreatePlacedResource2(void *d, void *h, UINT64 off, const D3D12_RESOURCE_DESC *rd, UINT layout, const D3D12_CLEAR_VALUE *cv, UINT nc, const DXGI_FORMAT *cf, REFIID r, void **o) {
    HRESULT hr = fl_r_CreatePlacedResource2(d, h, off, rd, layout, cv, nc, cf, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CPR2, fl_bad(hr, o))) { char b[200]; fl_log(FL_CPR2, hr, "heap=%p off=%llu layout=%u %s", h, (unsigned long long)off, layout, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateReservedResource(void *d, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateReservedResource(d, rd, st, cv, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CRR, fl_bad(hr, o))) { char b[200]; fl_log(FL_CRR, hr, "state=0x%x %s", (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateReservedResource1(void *d, const D3D12_RESOURCE_DESC *rd, D3D12_RESOURCE_STATES st, const D3D12_CLEAR_VALUE *cv, void *ps, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateReservedResource1(d, rd, st, cv, ps, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CRR1, fl_bad(hr, o))) { char b[200]; fl_log(FL_CRR1, hr, "state=0x%x %s", (unsigned)st, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateReservedResource2(void *d, const D3D12_RESOURCE_DESC *rd, UINT layout, const D3D12_CLEAR_VALUE *cv, void *ps, UINT nc, const DXGI_FORMAT *cf, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateReservedResource2(d, rd, layout, cv, ps, nc, cf, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_res(*o);
    if (fl_note(FL_CRR2, fl_bad(hr, o))) { char b[200]; fl_log(FL_CRR2, hr, "layout=%u %s", layout, fl_res(b, sizeof b, rd)); }
    return hr; }
HK fl_CreateSharedHandle(void *d, void *obj, const SECURITY_ATTRIBUTES *sa, DWORD acc, LPCWSTR name, HANDLE *o) {
    HRESULT hr = fl_r_CreateSharedHandle(d, obj, sa, acc, name, o);
    if (fl_note(FL_CSH, fl_bad(hr, (void **)o))) fl_log(FL_CSH, hr, "obj=%p access=0x%lx", obj, (unsigned long)acc);
    return hr; }
HK fl_OpenSharedHandle(void *d, HANDLE h, REFIID r, void **o) {
    HRESULT hr = fl_r_OpenSharedHandle(d, h, r, o);
    if (fl_note(FL_OSH, fl_bad(hr, o))) fl_log(FL_OSH, hr, "handle=%p", h);
    return hr; }
HK fl_MakeResident(void *d, UINT n, void *const *p) {
    HRESULT hr = fl_r_MakeResident(d, n, p);
    if (fl_note(FL_MR, FAILED(hr))) fl_log(FL_MR, hr, "NumObjects=%u", n);
    return hr; }
HK fl_Evict(void *d, UINT n, void *const *p) {
    HRESULT hr = fl_r_Evict(d, n, p);
    if (fl_note(FL_EV, FAILED(hr))) fl_log(FL_EV, hr, "NumObjects=%u", n);
    return hr; }
HK fl_EnqueueMakeResident(void *d, UINT fl, UINT n, void *const *p, void *f, UINT64 v) {
    HRESULT hr = fl_r_EnqueueMakeResident(d, fl, n, p, f, v);
    if (fl_note(FL_EMR, FAILED(hr))) fl_log(FL_EMR, hr, "NumObjects=%u flags=0x%x fenceval=%llu", n, fl, (unsigned long long)v);
    return hr; }
HK fl_SetResidencyPriority(void *d, UINT n, void *const *p, const D3D12_RESIDENCY_PRIORITY *pr) {
    HRESULT hr = fl_r_SetResidencyPriority(d, n, p, pr);
    if (fl_note(FL_SRP, FAILED(hr))) fl_log(FL_SRP, hr, "NumObjects=%u", n);
    return hr; }
HK fl_CreateFence(void *d, UINT64 v, D3D12_FENCE_FLAGS f, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateFence(d, v, f, r, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_fence(*o);
    if (fl_note(FL_CFS, fl_bad(hr, o))) fl_log(FL_CFS, hr, "init=%llu flags=0x%x", (unsigned long long)v, (unsigned)f);
    return hr; }
HK fl_CreateQueryHeap(void *d, const D3D12_QUERY_HEAP_DESC *q, REFIID r, void **o) {
    HRESULT hr = fl_r_CreateQueryHeap(d, q, r, o);
    if (fl_note(FL_CQH, fl_bad(hr, o))) fl_log(FL_CQH, hr, "type=%d count=%u", q ? (int)q->Type : -1, q ? q->Count : 0);
    return hr; }
HK fl_GetDeviceRemovedReason(void *d) {
    HRESULT hr = fl_r_GetDeviceRemovedReason(d);
    if (fl_note(FL_GDRR, hr != S_OK) || (hr == S_OK && (fl_ok[FL_GDRR] <= 5 || fl_ok[FL_GDRR] % 500 == 0))) {
        char b[64]; snprintf(b, sizeof b, "GetDeviceRemovedReason returned 0x%08lx dev=%p", (unsigned long)hr, d);
        EnterCriticalSection(&fl_lock); fl_write(b); LeaveCriticalSection(&fl_lock);
    }
    return hr; }
// pipeline library
HK fl_LoadGraphicsPipeline(void *l, LPCWSTR n, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *g, REFIID r, void **o) {
    HRESULT hr = fl_r_LoadGraphicsPipeline(l, n, g, r, o);
    if (fl_note(FL_LGP, fl_bad(hr, o))) fl_log(FL_LGP, hr, "failures_so_far=%ld rts=%u dsv=%u", (long)fl_fail[FL_LGP], g ? g->NumRenderTargets : 0, g ? (unsigned)g->DSVFormat : 0);
    return hr; }
HK fl_LoadComputePipeline(void *l, LPCWSTR n, const D3D12_COMPUTE_PIPELINE_STATE_DESC *c, REFIID r, void **o) {
    HRESULT hr = fl_r_LoadComputePipeline(l, n, c, r, o);
    if (fl_note(FL_LCP, fl_bad(hr, o))) fl_log(FL_LCP, hr, "failures_so_far=%ld", (long)fl_fail[FL_LCP]);
    return hr; }
HK fl_LoadPipeline(void *l, LPCWSTR n, const D3D12_PIPELINE_STATE_STREAM_DESC *s, REFIID r, void **o) {
    HRESULT hr = fl_r_LoadPipeline(l, n, s, r, o);
    if (fl_note(FL_LP, fl_bad(hr, o))) fl_log(FL_LP, hr, "failures_so_far=%ld", (long)fl_fail[FL_LP]);
    return hr; }
HK fl_StorePipeline(void *l, LPCWSTR n, void *p) {
    HRESULT hr = fl_r_StorePipeline(l, n, p);
    if (fl_note(FL_STP, FAILED(hr))) fl_log(FL_STP, hr, "failures_so_far=%ld", (long)fl_fail[FL_STP]);
    return hr; }


// ---- A) ID3D12CommandQueue ----
HK fl_QSignal(void *q, void *f, UINT64 v) {
    HRESULT hr = fl_r_QSignal(q, f, v);
    if (fl_note(FL_QSignal, FAILED(hr))) fl_log(FL_QSignal, hr, "queue=%p fence=%p value=%llu", q, f, (unsigned long long)v);
    return hr; }
HK fl_QWait(void *q, void *f, UINT64 v) {
    HRESULT hr = fl_r_QWait(q, f, v);
    if (fl_note(FL_QWait, FAILED(hr))) fl_log(FL_QWait, hr, "queue=%p fence=%p value=%llu", q, f, (unsigned long long)v);
    return hr; }
HK fl_QGTF(void *q, UINT64 *f) {
    HRESULT hr = fl_r_QGTF(q, f);
    if (fl_note(FL_QGTF, FAILED(hr))) fl_log(FL_QGTF, hr, "queue=%p", q);
    return hr; }
HK fl_QGCC(void *q, UINT64 *g, UINT64 *c) {
    HRESULT hr = fl_r_QGCC(q, g, c);
    if (fl_note(FL_QGCC, FAILED(hr))) fl_log(FL_QGCC, hr, "queue=%p", q);
    return hr; }
static void fl_after_tile(int id, void *q, const char *what)
{
    HRESULT d = fl_dev && fl_r_GetDeviceRemovedReason ? fl_r_GetDeviceRemovedReason(fl_dev) : S_OK;
    if (d != S_OK && fl_note(id, 1)) fl_log(id, d, "DEVICE REMOVED right after %s queue=%p", what, q);
}
static void STDMETHODCALLTYPE fl_QUTM(void *q, void *res, UINT nrr, const D3D12_TILED_RESOURCE_COORDINATE *rsc, const D3D12_TILE_REGION_SIZE *rs, void *heap, UINT nr, const D3D12_TILE_RANGE_FLAGS *rf, const UINT *hro, const UINT *rtc, D3D12_TILE_MAPPING_FLAGS fl) {
    LONG n;
    fl_r_QUTM(q, res, nrr, rsc, rs, heap, nr, rf, hro, rtc, fl);
    n = InterlockedIncrement(&fl_ok[FL_QUTM]);
    if (n <= 50 || n % 1000 == 0) fl_info(FL_QUTM, "call=%ld queue=%p res=%p NumResourceRegions=%u NumRanges=%u heap=%p flags=0x%x", (long)n, q, res, nrr, nr, heap, (unsigned)fl);
    fl_after_tile(FL_QUTM, q, "UpdateTileMappings"); }
static void STDMETHODCALLTYPE fl_QCTM(void *q, void *dst, const D3D12_TILED_RESOURCE_COORDINATE *dc, void *src, const D3D12_TILED_RESOURCE_COORDINATE *sc, const D3D12_TILE_REGION_SIZE *rs, D3D12_TILE_MAPPING_FLAGS fl) {
    LONG n;
    fl_r_QCTM(q, dst, dc, src, sc, rs, fl);
    n = InterlockedIncrement(&fl_ok[FL_QCTM]);
    if (n <= 50 || n % 1000 == 0) fl_info(FL_QCTM, "call=%ld queue=%p dst=%p src=%p flags=0x%x", (long)n, q, dst, src, (unsigned)fl);
    fl_after_tile(FL_QCTM, q, "CopyTileMappings"); }
static void STDMETHODCALLTYPE fl_QECL(void *q, UINT n, void *const *l) {
    fl_r_QECL(q, n, l); InterlockedIncrement(&fl_ok[FL_QECL]); }

// ---- B) ID3D12Fence ----
HK fl_FSEOC(void *f, UINT64 v, HANDLE e) {
    HRESULT hr = fl_r_FSEOC(f, v, e);
    if (fl_note(FL_FSEOC, FAILED(hr))) fl_log(FL_FSEOC, hr, "fence=%p value=%llu event=%p", f, (unsigned long long)v, e);
    return hr; }
HK fl_FSignal(void *f, UINT64 v) {
    HRESULT hr = fl_r_FSignal(f, v);
    if (fl_note(FL_FSignal, FAILED(hr))) fl_log(FL_FSignal, hr, "fence=%p value=%llu", f, (unsigned long long)v);
    return hr; }

// ---- C) command list / allocator ----
HK fl_LClose(void *l) {
    HRESULT hr = fl_r_LClose(l);
    if (fl_note(FL_LClose, FAILED(hr))) fl_log(FL_LClose, hr, "list=%p", l);
    return hr; }
HK fl_LReset(void *l, void *a, void *p) {
    HRESULT hr = fl_r_LReset(l, a, p);
    if (fl_note(FL_LReset, FAILED(hr))) fl_log(FL_LReset, hr, "list=%p alloc=%p pso=%p", l, a, p);
    return hr; }
HK fl_AReset(void *a) {
    HRESULT hr = fl_r_AReset(a);
    if (fl_note(FL_AReset, FAILED(hr))) fl_log(FL_AReset, hr, "alloc=%p", a);
    return hr; }

// ---- D) ID3D12Resource::Map ----
HK fl_RMap(void *r, UINT sub, const D3D12_RANGE *rg, void **pp) {
    HRESULT hr = fl_r_RMap(r, sub, rg, pp);
    if (fl_note(FL_RMap, FAILED(hr))) {
        ID3D12Resource *res = (ID3D12Resource *)r; D3D12_RESOURCE_DESC d; D3D12_HEAP_PROPERTIES hp; D3D12_HEAP_FLAGS hf = 0; HRESULT h2;
        char a[220], b[200], rgs[64];
        memset(&d, 0, sizeof d); memset(&hp, 0, sizeof hp);
        res->lpVtbl->GetDesc(res, &d);
        h2 = res->lpVtbl->GetHeapProperties(res, &hp, &hf);
        if (rg) snprintf(rgs, sizeof rgs, "[%llu,%llu)", (unsigned long long)rg->Begin, (unsigned long long)rg->End); else snprintf(rgs, sizeof rgs, "NULL");
        fl_log(FL_RMap, hr, "res=%p subresource=%u range=%s %s heapflags=0x%x (GetHeapProperties hr=0x%08lx) %s", r, sub, rgs,
            FAILED(h2) ? "hp=unavailable" : fl_hp(a, sizeof a, &hp), (unsigned)hf, (unsigned long)h2, fl_res(b, sizeof b, &d));
    }
    return hr; }

// ---- E) DXGI ----
HK fl_AQVMI(void *a, UINT node, DXGI_MEMORY_SEGMENT_GROUP g, DXGI_QUERY_VIDEO_MEMORY_INFO *i) {
    HRESULT hr = fl_r_AQVMI(a, node, g, i); int bad = FAILED(hr);
    if (fl_note(FL_AQVMI, bad)) fl_log(FL_AQVMI, hr, "node=%u group=%d", node, (int)g);
    if (!bad && i) {
        LONG n = fl_ok[FL_AQVMI];
        if (n <= 20 || n % 200 == 0) fl_info(FL_AQVMI, "call=%ld node=%u group=%d Budget=%llu CurrentUsage=%llu AvailableForReservation=%llu CurrentReservation=%llu", (long)n, node, (int)g,
            (unsigned long long)i->Budget, (unsigned long long)i->CurrentUsage, (unsigned long long)i->AvailableForReservation, (unsigned long long)i->CurrentReservation);
    }
    return hr; }
HK fl_ASVMR(void *a, UINT node, DXGI_MEMORY_SEGMENT_GROUP g, UINT64 res) {
    HRESULT hr = fl_r_ASVMR(a, node, g, res); int bad = FAILED(hr);
    fl_info(FL_ASVMR, "node=%u group=%d reservation=%llu hr=0x%08lx", node, (int)g, (unsigned long long)res, (unsigned long)hr);
    if (fl_note(FL_ASVMR, bad)) fl_log(FL_ASVMR, hr, "node=%u group=%d reservation=%llu", node, (int)g, (unsigned long long)res);
    return hr; }
HK fl_ARVMB(void *a, HANDLE e, DWORD *cookie) {
    HRESULT hr = fl_r_ARVMB(a, e, cookie); int bad = FAILED(hr);
    fl_info(FL_ARVMB, "event=%p cookie=%lu hr=0x%08lx", e, (unsigned long)(!bad && cookie ? *cookie : 0), (unsigned long)hr);
    if (fl_note(FL_ARVMB, bad)) fl_log(FL_ARVMB, hr, "event=%p", e);
    return hr; }
HK fl_FCSC(void *f, IUnknown *dev, DXGI_SWAP_CHAIN_DESC *d, void **o) {
    HRESULT hr = fl_r_FCSC(f, dev, d, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_sc(*o);
    if (fl_note(FL_FCSC, fl_bad(hr, o))) fl_log(FL_FCSC, hr, "dev=%p %ux%u fmt=%u bufs=%u windowed=%d effect=%d flags=0x%x", dev,
        d ? d->BufferDesc.Width : 0, d ? d->BufferDesc.Height : 0, d ? (unsigned)d->BufferDesc.Format : 0, d ? d->BufferCount : 0, d ? (int)d->Windowed : -1, d ? (int)d->SwapEffect : -1, d ? d->Flags : 0);
    return hr; }
HK fl_FCSCH(void *f, IUnknown *dev, HWND h, const DXGI_SWAP_CHAIN_DESC1 *d, const DXGI_SWAP_CHAIN_FULLSCREEN_DESC *fs, void *ro, void **o) {
    HRESULT hr = fl_r_FCSCH(f, dev, h, d, fs, ro, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_sc(*o);
    if (fl_note(FL_FCSCH, fl_bad(hr, o))) fl_log(FL_FCSCH, hr, "dev=%p hwnd=%p %ux%u fmt=%u bufs=%u effect=%d flags=0x%x fullscreen=%d", dev, h,
        d ? d->Width : 0, d ? d->Height : 0, d ? (unsigned)d->Format : 0, d ? d->BufferCount : 0, d ? (int)d->SwapEffect : -1, d ? d->Flags : 0, fs ? (int)!fs->Windowed : -1);
    return hr; }
HK fl_FCSCC(void *f, IUnknown *dev, const DXGI_SWAP_CHAIN_DESC1 *d, void *ro, void **o) {
    HRESULT hr = fl_r_FCSCC(f, dev, d, ro, o);
    if (SUCCEEDED(hr) && o && *o) fl_obj_sc(*o);
    if (fl_note(FL_FCSCC, fl_bad(hr, o))) fl_log(FL_FCSCC, hr, "dev=%p %ux%u fmt=%u bufs=%u", dev, d ? d->Width : 0, d ? d->Height : 0, d ? (unsigned)d->Format : 0, d ? d->BufferCount : 0);
    return hr; }
HK fl_SPresent(void *s, UINT si, UINT fl) {
    HRESULT hr = fl_r_SPresent(s, si, fl);
    if (fl_note(FL_SPresent, FAILED(hr))) fl_log(FL_SPresent, hr, "sc=%p sync=%u flags=0x%x", s, si, fl);
    return hr; }
HK fl_SPresent1(void *s, UINT si, UINT fl, const DXGI_PRESENT_PARAMETERS *pp) {
    HRESULT hr = fl_r_SPresent1(s, si, fl, pp);
    if (fl_note(FL_SPresent1, FAILED(hr))) fl_log(FL_SPresent1, hr, "sc=%p sync=%u flags=0x%x", s, si, fl);
    return hr; }
HK fl_SResize(void *s, UINT n, UINT w, UINT h, DXGI_FORMAT f, UINT fl) {
    HRESULT hr = fl_r_SResize(s, n, w, h, f, fl);
    if (fl_note(FL_SResize, FAILED(hr))) fl_log(FL_SResize, hr, "sc=%p bufs=%u %ux%u fmt=%u flags=0x%x", s, n, w, h, (unsigned)f, fl);
    return hr; }
HK fl_SResize1(void *s, UINT n, UINT w, UINT h, DXGI_FORMAT f, UINT fl, const UINT *m, IUnknown *const *q) {
    HRESULT hr = fl_r_SResize1(s, n, w, h, f, fl, m, q);
    if (fl_note(FL_SResize1, FAILED(hr))) fl_log(FL_SResize1, hr, "sc=%p bufs=%u %ux%u fmt=%u flags=0x%x", s, n, w, h, (unsigned)f, fl);
    return hr; }
HK fl_SGetBuffer(void *s, UINT i, REFIID r, void **o) {
    HRESULT hr = fl_r_SGetBuffer(s, i, r, o);
    if (fl_note(FL_SGetBuffer, FAILED(hr))) fl_log(FL_SGetBuffer, hr, "sc=%p index=%u", s, i);
    return hr; }

#define FLP(vt, name) patch_slot((void **)&(vt)->name, (void *)fl_##name, (void **)&fl_r_##name)
static void fl_patch_lib(IUnknown *u, int lib1)
{
    void *p = NULL;
    if (SUCCEEDED(u->lpVtbl->QueryInterface(u, lib1 ? &IID_ID3D12PipelineLibrary1 : &IID_ID3D12PipelineLibrary, &p)) && p) {
        ID3D12PipelineLibraryVtbl *vt = *(ID3D12PipelineLibraryVtbl **)p;   // PipelineLibrary1 shares these slots, LoadPipeline follows
        FLP(vt, LoadGraphicsPipeline); FLP(vt, LoadComputePipeline); FLP(vt, StorePipeline);
        if (lib1) { ID3D12PipelineLibrary1Vtbl *v1 = *(ID3D12PipelineLibrary1Vtbl **)p; FLP(v1, LoadPipeline); }
        ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
    }
}
HK fl_CreatePipelineLibrary(void *d, const void *b, SIZE_T l, REFIID r, void **o) {
    HRESULT hr = fl_r_CreatePipelineLibrary(d, b, l, r, o);
    if (SUCCEEDED(hr) && o && *o) { fl_patch_lib((IUnknown *)*o, 0); fl_patch_lib((IUnknown *)*o, 1); }
    if (fl_note(FL_CPL, fl_bad(hr, o))) fl_log(FL_CPL, hr, "blob_len=%llu", (unsigned long long)l);
    return hr; }

// ---- faillog-2: per-object vtable patching ----
// Registry of the vtables patched so far (kind + table), so they can be re-applied after the shim's own patch_slot
// calls on a later device overwrite a slot, and a registry of object vtables already probed (avoids a QueryInterface per object).
enum { FK_Q, FK_F, FK_L, FK_A, FK_R, FK_FAC0, FK_FAC2, FK_AD3, FK_SC0, FK_SC1, FK_SC3, FK_N };
typedef struct { int kind; void **vt; } fl_vte;
static fl_vte fl_vts[96]; static int fl_nvts;
static void *fl_probed[FK_N][16]; static int fl_nprobed[FK_N];

// patch_slot, except that it refuses a slot whose current value is neither our hook nor the saved original: that means this
// interface's table holds a different implementation than the one we saved (a shared saved pointer would be called with the wrong object)
static void fl_slot(void **slot, void *hook, void **saved, const char *what)
{
    char b[160];
    if (*slot == hook) return;
    if (*saved && *slot != *saved) {
        snprintf(b, sizeof b, "SKIP slot %s: table %p holds %p, saved original is %p", what, (void *)slot, *slot, *saved);
        fl_write(b); return;
    }
    patch_slot(slot, hook, saved);
}
#define FLX(vt, slot, h) fl_slot((void **)&(vt)->slot, (void *)fl_##h, (void **)&fl_r_##h, #h)

static void fl_apply(int kind, void **vt)
{
    switch (kind) {
    case FK_Q: { ID3D12CommandQueueVtbl *v = (ID3D12CommandQueueVtbl *)vt;
        FLX(v, Signal, QSignal); FLX(v, Wait, QWait); FLX(v, GetTimestampFrequency, QGTF); FLX(v, GetClockCalibration, QGCC);
        FLX(v, UpdateTileMappings, QUTM); FLX(v, CopyTileMappings, QCTM); FLX(v, ExecuteCommandLists, QECL); break; }
    case FK_F: { ID3D12FenceVtbl *v = (ID3D12FenceVtbl *)vt; FLX(v, SetEventOnCompletion, FSEOC); FLX(v, Signal, FSignal); break; }
    case FK_L: { ID3D12GraphicsCommandListVtbl *v = (ID3D12GraphicsCommandListVtbl *)vt; FLX(v, Close, LClose); FLX(v, Reset, LReset); break; }
    case FK_A: { ID3D12CommandAllocatorVtbl *v = (ID3D12CommandAllocatorVtbl *)vt; FLX(v, Reset, AReset); break; }
    case FK_R: { ID3D12ResourceVtbl *v = (ID3D12ResourceVtbl *)vt; FLX(v, Map, RMap); break; }
    case FK_FAC0: { IDXGIFactoryVtbl *v = (IDXGIFactoryVtbl *)vt; FLX(v, CreateSwapChain, FCSC); break; }
    case FK_FAC2: { IDXGIFactory2Vtbl *v = (IDXGIFactory2Vtbl *)vt;   // superset of IDXGIFactory / 1, also valid for Factory3+
        FLX(v, CreateSwapChain, FCSC); FLX(v, CreateSwapChainForHwnd, FCSCH); FLX(v, CreateSwapChainForComposition, FCSCC); break; }
    case FK_AD3: { IDXGIAdapter3Vtbl *v = (IDXGIAdapter3Vtbl *)vt;
        FLX(v, QueryVideoMemoryInfo, AQVMI); FLX(v, SetVideoMemoryReservation, ASVMR); FLX(v, RegisterVideoMemoryBudgetChangeNotificationEvent, ARVMB); break; }
    case FK_SC0: { IDXGISwapChainVtbl *v = (IDXGISwapChainVtbl *)vt; FLX(v, Present, SPresent); FLX(v, ResizeBuffers, SResize); FLX(v, GetBuffer, SGetBuffer); break; }
    case FK_SC1: { IDXGISwapChain1Vtbl *v = (IDXGISwapChain1Vtbl *)vt; FLX(v, Present1, SPresent1); break; }
    case FK_SC3: { IDXGISwapChain3Vtbl *v = (IDXGISwapChain3Vtbl *)vt; FLX(v, ResizeBuffers1, SResize1); break; }
    }
}
static void fl_repatch_kind(int kind)
{
    int i;
    for (i = 0; i < fl_nvts; i++) if (fl_vts[i].kind == kind) fl_apply(kind, fl_vts[i].vt);
}
static void fl_repatch_all(void)
{
    int i;
    EnterCriticalSection(&fl_lock);
    for (i = 0; i < fl_nvts; i++) fl_apply(fl_vts[i].kind, fl_vts[i].vt);
    LeaveCriticalSection(&fl_lock);
}
// QueryInterface `obj` for each (iid, kind) entry and patch each distinct table once. `probe` is the registry key kind.
typedef struct { const IID *id; int kind; } fl_ent;
static void fl_obj(int probe, void *obj, const fl_ent *e, int n)
{
    void **vt0 = *(void ***)obj; int i, j;
    EnterCriticalSection(&fl_lock);
    for (i = 0; i < fl_nprobed[probe]; i++) if (fl_probed[probe][i] == (void *)vt0) { LeaveCriticalSection(&fl_lock); return; }
    if (fl_nprobed[probe] < 16) fl_probed[probe][fl_nprobed[probe]++] = (void *)vt0;
    for (i = 0; i < n; i++) {
        void *p = NULL; void **vt;
        if (FAILED(((IUnknown *)obj)->lpVtbl->QueryInterface((IUnknown *)obj, e[i].id, &p)) || !p) continue;
        vt = *(void ***)p;
        for (j = 0; j < fl_nvts; j++) if (fl_vts[j].kind == e[i].kind && fl_vts[j].vt == vt) break;
        if (j == fl_nvts && fl_nvts < (int)(sizeof fl_vts / sizeof *fl_vts)) {
            char b[96]; fl_vts[fl_nvts].kind = e[i].kind; fl_vts[fl_nvts].vt = vt; fl_nvts++;
            snprintf(b, sizeof b, "patching vtable kind=%d table=%p (obj=%p)", e[i].kind, (void *)vt, p); fl_write(b);
            fl_apply(e[i].kind, vt);
        }
        ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
    }
    LeaveCriticalSection(&fl_lock);
}
static void fl_obj_queue(void *o) {
    static const fl_ent e[] = { { &IID_ID3D12CommandQueue, FK_Q } };
    fl_obj(FK_Q, o, e, 1); fl_repatch_kind(FK_Q); }   // re-apply every time: inspect/shim may have re-patched a slot
static void fl_obj_fence(void *o) {
    static const fl_ent e[] = { { &IID_ID3D12Fence, FK_F }
#ifdef __ID3D12Fence1_INTERFACE_DEFINED__
        , { &IID_ID3D12Fence1, FK_F }
#endif
    };
    fl_obj(FK_F, o, e, sizeof e / sizeof *e); }
static void fl_obj_list(void *o) {
    static const fl_ent e[] = { { &IID_ID3D12GraphicsCommandList, FK_L }, { &IID_ID3D12GraphicsCommandList1, FK_L }, { &IID_ID3D12GraphicsCommandList2, FK_L },
        { &IID_ID3D12GraphicsCommandList3, FK_L }, { &IID_ID3D12GraphicsCommandList4, FK_L }, { &IID_ID3D12GraphicsCommandList5, FK_L }, { &IID_ID3D12GraphicsCommandList6, FK_L }
#ifdef __ID3D12GraphicsCommandList7_INTERFACE_DEFINED__
        , { &IID_ID3D12GraphicsCommandList7, FK_L }
#endif
    };
    static volatile LONG cnt;
    fl_obj(FK_L, o, e, sizeof e / sizeof *e);
    if ((InterlockedIncrement(&cnt) & 63) == 0) fl_repatch_kind(FK_L); }
static void fl_obj_alloc(void *o) {
    static const fl_ent e[] = { { &IID_ID3D12CommandAllocator, FK_A } };
    fl_obj(FK_A, o, e, 1); }
static void fl_obj_res(void *o) {   // all resources share one D3DMetal vtable, so this QIs only for an unseen table
    static const fl_ent e[] = { { &IID_ID3D12Resource, FK_R }
#ifdef __ID3D12Resource1_INTERFACE_DEFINED__
        , { &IID_ID3D12Resource1, FK_R }
#endif
    };
    fl_obj(FK_R, o, e, sizeof e / sizeof *e); }
static void fl_obj_sc(void *o) {
    static const fl_ent e[] = { { &IID_IDXGISwapChain, FK_SC0 }, { &IID_IDXGISwapChain1, FK_SC1 }, { &IID_IDXGISwapChain3, FK_SC3 } };
    fl_obj(FK_SC0, o, e, 3); }

// DXGI: create our own factory from the same builtin dxgi.dll the game uses and patch the (shared) vtables.
// Done on the first device patch, not in DllMain (loader lock).
static void fl_dxgi_init(void)
{
    typedef HRESULT (WINAPI *PFN)(UINT, REFIID, void **);
    static int done; HMODULE m; PFN f; void *fac = NULL, *ad = NULL; HRESULT hr; char b[160];
    static const fl_ent fe[] = { { &IID_IDXGIFactory, FK_FAC0 }, { &IID_IDXGIFactory2, FK_FAC2 }, { &IID_IDXGIFactory4, FK_FAC2 } };
    static const fl_ent ae[] = { { &IID_IDXGIAdapter3, FK_AD3 } };
    if (done) return; done = 1;
    m = LoadLibraryA("dxgi.dll"); f = m ? (PFN)GetProcAddress(m, "CreateDXGIFactory2") : NULL;
    if (!f) { EnterCriticalSection(&fl_lock); fl_write("DXGI hooks SKIPPED: dxgi.dll / CreateDXGIFactory2 unavailable"); LeaveCriticalSection(&fl_lock); return; }
    hr = f(0, &IID_IDXGIFactory4, &fac);
    if (FAILED(hr) || !fac) { snprintf(b, sizeof b, "DXGI hooks SKIPPED: CreateDXGIFactory2 hr=0x%08lx", (unsigned long)hr); EnterCriticalSection(&fl_lock); fl_write(b); LeaveCriticalSection(&fl_lock); return; }
    fl_obj(FK_FAC0, fac, fe, 3);
    hr = ((IDXGIFactory4 *)fac)->lpVtbl->EnumAdapters((IDXGIFactory4 *)fac, 0, (IDXGIAdapter **)&ad);
    if (SUCCEEDED(hr) && ad) { fl_obj(FK_AD3, ad, ae, 1); ((IUnknown *)ad)->lpVtbl->Release((IUnknown *)ad); }
    else { snprintf(b, sizeof b, "DXGI adapter hooks SKIPPED: EnumAdapters(0) hr=0x%08lx", (unsigned long)hr); EnterCriticalSection(&fl_lock); fl_write(b); LeaveCriticalSection(&fl_lock); }
    ((IUnknown *)fac)->lpVtbl->Release((IUnknown *)fac);
    EnterCriticalSection(&fl_lock); fl_write("DXGI hooks installed (factory/adapter3 tables; swapchain tables patched when the game creates its swapchain)"); LeaveCriticalSection(&fl_lock);
}

// level = highest ID3D12DeviceN interface this vtable belongs to (0 = ID3D12Device)
static void fl_patch_device_vtbl(void *iface, int level)
{
    ID3D12Device9Vtbl *vt = *(ID3D12Device9Vtbl **)iface;   // superset layout; fields are used only up to `level`
    FLP(vt, CreateCommandQueue); FLP(vt, CreateCommandAllocator); FLP(vt, CreateGraphicsPipelineState); FLP(vt, CreateComputePipelineState);
    FLP(vt, CreateCommandList); FLP(vt, CheckFeatureSupport); FLP(vt, CreateDescriptorHeap); FLP(vt, CreateRootSignature);
    FLP(vt, CreateCommittedResource); FLP(vt, CreateHeap); FLP(vt, CreatePlacedResource); FLP(vt, CreateReservedResource);
    FLP(vt, CreateSharedHandle); FLP(vt, OpenSharedHandle); FLP(vt, MakeResident); FLP(vt, Evict); FLP(vt, CreateFence);
    FLP(vt, GetDeviceRemovedReason); FLP(vt, CreateQueryHeap);
    if (level >= 1) { FLP(vt, CreatePipelineLibrary); FLP(vt, SetResidencyPriority); }
    if (level >= 2) FLP(vt, CreatePipelineState);
    if (level >= 3) FLP(vt, EnqueueMakeResident);
    if (level >= 4) { FLP(vt, CreateCommandList1); FLP(vt, CreateCommittedResource1); FLP(vt, CreateHeap1); FLP(vt, CreateReservedResource1); }
    if (level >= 8) { FLP(vt, CreateCommittedResource2); FLP(vt, CreatePlacedResource1); }
    if (level >= 9) FLP(vt, CreateCommandQueue1);
    if (level >= 10) {   // these headers stop at Device9: Device10 appends CreateCommittedResource3, CreatePlacedResource2, CreateReservedResource2
        void **raw = (void **)vt; size_t b = sizeof(ID3D12Device9Vtbl) / sizeof(void *);
        patch_slot(&raw[b + 0], (void *)fl_CreateCommittedResource3, (void **)&fl_r_CreateCommittedResource3);
        patch_slot(&raw[b + 1], (void *)fl_CreatePlacedResource2, (void **)&fl_r_CreatePlacedResource2);
        patch_slot(&raw[b + 2], (void *)fl_CreateReservedResource2, (void **)&fl_r_CreateReservedResource2);
    }
}
static void fl_patch_device(ID3D12Device *dev)
{
    static const GUID iid10 = { 0x517f8718, 0xaa66, 0x49f9, { 0xb0, 0x2b, 0xa7, 0xab, 0x89, 0xc0, 0x60, 0x31 } };
    const IID *ids[11] = { 0 }; int lv;
    if (!hb_debug) return;   // play build: the counting/logging wrappers are not installed (stride keeps its own vtable registry)
    ids[1] = &IID_ID3D12Device1; ids[2] = &IID_ID3D12Device2; ids[3] = &IID_ID3D12Device3; ids[4] = &IID_ID3D12Device4;
    ids[5] = &IID_ID3D12Device5; ids[6] = &IID_ID3D12Device6; ids[7] = &IID_ID3D12Device7; ids[8] = &IID_ID3D12Device8;
    ids[9] = &IID_ID3D12Device9; ids[10] = &iid10;
    fl_patch_device_vtbl(dev, 0);
    for (lv = 1; lv <= 10; lv++) {
        void *p = NULL;
        if (FAILED(dev->lpVtbl->QueryInterface(dev, ids[lv], &p)) || !p) continue;
        fl_patch_device_vtbl(p, lv); ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
    }
    if (fl_dev != dev) {   // keep the latest patched device (AddRef'd) for the DRR suffix / post-UpdateTileMappings check
        ID3D12Device *old = fl_dev; dev->lpVtbl->AddRef(dev); fl_dev = dev;
        if (old) old->lpVtbl->Release(old);
    }
    fl_repatch_all();   // re-apply object-level hooks the shim's patch_device may have overwritten
    fl_dxgi_init();
    if (!fl_thread_started) { fl_thread_started = 1; CloseHandle(CreateThread(NULL, 0, fl_thread, NULL, 0, NULL)); }
    EnterCriticalSection(&fl_lock); fl_write("device patched for failure logging"); LeaveCriticalSection(&fl_lock);
}
