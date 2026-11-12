// pso_trace: when and how long the game's pipeline creations take, for one diagnostic run.
// MGF_FH6_PSO_TRACE=1 turns it on; otherwise it costs one branch per creation and writes nothing.
// Each creation through the hooked device and pipeline-library calls is stored in memory (start and
// duration on the performance counter, thread, kind, vertex and pixel shader hashes, result); a thread
// of its own writes what is new to C:\mgf\fh6-pso-<pid>.log every two seconds, with an anchor line
// that pairs the counter with the system time, so the records can be laid beside Metal's timeline.
// Nothing is written from the game's own threads. Records past the buffer are counted, not kept.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef MGF_PSO_TRACE_H
#define MGF_PSO_TRACE_H

enum { PT_GRAPHICS, PT_COMPUTE, PT_STREAM, PT_LOAD_GRAPHICS, PT_LOAD_STREAM };
static const char pt_kind[] = "GCSLM";   // L/M: loaded from an ID3D12PipelineLibrary
#define PT_CAPACITY 262144
struct pt_record { LONGLONG start, ticks; UINT64 vs, ps, desc, obj; DWORD tid; LONG hr; LONG kind; volatile LONG ready; };
static struct pt_record *pt_records;
static volatile LONG pt_next, pt_dropped;
static int pso_trace;

static inline LONGLONG pt_now(void) { LARGE_INTEGER q; QueryPerformanceCounter(&q); return q.QuadPart; }

// The description's own hash: every field the game passed, with shaders, input layout, stream output and
// cached blob hashed by content and the root signature by identity. Two creations with the same hash asked
// for the same pipeline. Fields are hashed one by one so padding bytes never enter it.
#define PT_FNV 1099511628211ull
static UINT64 pt_mix(UINT64 h, const void *p, SIZE_T n)
{
    const UINT8 *b = p; SIZE_T i;
    for (i = 0; i < n; i++) h = (h ^ b[i]) * PT_FNV;
    return h;
}
#define PT_F(h, x) ((h) = pt_mix((h), &(x), sizeof(x)))
static UINT64 pt_str(UINT64 h, const char *s) { return s ? pt_mix(h, s, strlen(s) + 1) : pt_mix(h, "", 1); }
static UINT64 pt_code(UINT64 h, D3D12_SHADER_BYTECODE b)
{
    PT_F(h, b.BytecodeLength);
    if (!b.pShaderBytecode || !b.BytecodeLength) return h;
    if (b.BytecodeLength >= 20 && !memcmp(b.pShaderBytecode, "DXBC", 4)) return pt_mix(h, (const UINT8 *)b.pShaderBytecode + 4, 16);
    return pt_mix(h, b.pShaderBytecode, b.BytecodeLength);
}
static UINT64 pt_hash_graphics(const D3D12_GRAPHICS_PIPELINE_STATE_DESC *d)
{
    UINT64 h = 14695981039346656037ull; UINT i;
    if (!d) return 0;
    PT_F(h, d->pRootSignature);
    h = pt_code(h, d->VS); h = pt_code(h, d->PS); h = pt_code(h, d->DS); h = pt_code(h, d->HS); h = pt_code(h, d->GS);
    PT_F(h, d->StreamOutput.NumEntries); PT_F(h, d->StreamOutput.NumStrides); PT_F(h, d->StreamOutput.RasterizedStream);
    for (i = 0; d->StreamOutput.pSODeclaration && i < d->StreamOutput.NumEntries; i++) {
        const D3D12_SO_DECLARATION_ENTRY *e = &d->StreamOutput.pSODeclaration[i];
        PT_F(h, e->Stream); h = pt_str(h, e->SemanticName); PT_F(h, e->SemanticIndex);
        PT_F(h, e->StartComponent); PT_F(h, e->ComponentCount); PT_F(h, e->OutputSlot);
    }
    if (d->StreamOutput.pBufferStrides) h = pt_mix(h, d->StreamOutput.pBufferStrides, sizeof(UINT) * d->StreamOutput.NumStrides);
    PT_F(h, d->BlendState.AlphaToCoverageEnable); PT_F(h, d->BlendState.IndependentBlendEnable);
    for (i = 0; i < 8; i++) {
        const D3D12_RENDER_TARGET_BLEND_DESC *t = &d->BlendState.RenderTarget[i];
        PT_F(h, t->BlendEnable); PT_F(h, t->LogicOpEnable); PT_F(h, t->SrcBlend); PT_F(h, t->DestBlend); PT_F(h, t->BlendOp);
        PT_F(h, t->SrcBlendAlpha); PT_F(h, t->DestBlendAlpha); PT_F(h, t->BlendOpAlpha); PT_F(h, t->LogicOp); PT_F(h, t->RenderTargetWriteMask);
    }
    PT_F(h, d->SampleMask);
    PT_F(h, d->RasterizerState);   // eleven 4-byte fields, no padding
    PT_F(h, d->DepthStencilState.DepthEnable); PT_F(h, d->DepthStencilState.DepthWriteMask); PT_F(h, d->DepthStencilState.DepthFunc);
    PT_F(h, d->DepthStencilState.StencilEnable); PT_F(h, d->DepthStencilState.StencilReadMask); PT_F(h, d->DepthStencilState.StencilWriteMask);
    PT_F(h, d->DepthStencilState.FrontFace); PT_F(h, d->DepthStencilState.BackFace);   // four enums each
    PT_F(h, d->InputLayout.NumElements);
    for (i = 0; d->InputLayout.pInputElementDescs && i < d->InputLayout.NumElements; i++) {
        const D3D12_INPUT_ELEMENT_DESC *e = &d->InputLayout.pInputElementDescs[i];
        h = pt_str(h, e->SemanticName); PT_F(h, e->SemanticIndex); PT_F(h, e->Format); PT_F(h, e->InputSlot);
        PT_F(h, e->AlignedByteOffset); PT_F(h, e->InputSlotClass); PT_F(h, e->InstanceDataStepRate);
    }
    PT_F(h, d->IBStripCutValue); PT_F(h, d->PrimitiveTopologyType); PT_F(h, d->NumRenderTargets); PT_F(h, d->RTVFormats);
    PT_F(h, d->DSVFormat); PT_F(h, d->SampleDesc); PT_F(h, d->NodeMask); PT_F(h, d->CachedPSO.CachedBlobSizeInBytes);
    if (d->CachedPSO.pCachedBlob) h = pt_mix(h, d->CachedPSO.pCachedBlob, d->CachedPSO.CachedBlobSizeInBytes);
    PT_F(h, d->Flags);
    return h ? h : 1;
}
static UINT64 pt_hash_compute(const D3D12_COMPUTE_PIPELINE_STATE_DESC *d)
{
    UINT64 h = 14695981039346656037ull;
    if (!d) return 0;
    PT_F(h, d->pRootSignature); h = pt_code(h, d->CS); PT_F(h, d->NodeMask); PT_F(h, d->CachedPSO.CachedBlobSizeInBytes);
    if (d->CachedPSO.pCachedBlob) h = pt_mix(h, d->CachedPSO.pCachedBlob, d->CachedPSO.CachedBlobSizeInBytes);
    PT_F(h, d->Flags);
    return h ? h : 1;
}
#define PT_OBJ(hr, out) (SUCCEEDED(hr) && (out) ? (UINT64)(ULONG_PTR)*(out) : 0)

// desc is the game's description, hashed after the end time is taken so the hash is not in the duration.
static void pt_add(int kind, LONGLONG start, UINT64 vs, UINT64 ps, HRESULT hr, const void *d, UINT64 obj)
{
    LONGLONG end = pt_now();
    UINT64 desc = kind == PT_GRAPHICS || kind == PT_LOAD_GRAPHICS ? pt_hash_graphics(d) : kind == PT_COMPUTE ? pt_hash_compute(d) : 0;
    LONG i = InterlockedIncrement(&pt_next) - 1;
    struct pt_record *r;
    if (i >= PT_CAPACITY) { InterlockedIncrement(&pt_dropped); return; }
    r = &pt_records[i];
    r->start = start; r->ticks = end - start; r->vs = vs; r->ps = ps; r->desc = desc; r->obj = obj;
    r->tid = GetCurrentThreadId(); r->hr = (LONG)hr; r->kind = kind;
    InterlockedExchange(&r->ready, 1);
}

static DWORD WINAPI pt_writer(LPVOID path)
{
    FILE *f = fopen((const char *)path, "w");
    LARGE_INTEGER freq; LONG done = 0;
    if (!f) return 0;
    QueryPerformanceFrequency(&freq);
    fprintf(f, "# fh6 pso trace: kind start_qpc duration_us tid vs ps hr desc object (G graphics, C compute, S stream, L/M library load; desc 0 = not hashed)\n");
    fprintf(f, "# qpc_frequency %lld\n", (long long)freq.QuadPart);
    for (;;) {
        FILETIME ft; LONGLONG q = pt_now(); LONG n = pt_next;
        GetSystemTimePreciseAsFileTime(&ft);
        // Anchor: this counter value is this UTC time (FILETIME, 100 ns since 1601).
        fprintf(f, "A %lld %llu dropped %ld\n", (long long)q,
                ((unsigned long long)ft.dwHighDateTime << 32) | ft.dwLowDateTime, (long)pt_dropped);
        if (n > PT_CAPACITY) n = PT_CAPACITY;
        while (done < n && pt_records[done].ready) {
            const struct pt_record *r = &pt_records[done++];
            fprintf(f, "%c %lld %lld %lu %016llx %016llx %08lx %016llx %llx\n", pt_kind[r->kind], (long long)r->start,
                    (long long)(r->ticks * 1000000 / freq.QuadPart), (unsigned long)r->tid,
                    (unsigned long long)r->vs, (unsigned long long)r->ps, (unsigned long)r->hr,
                    (unsigned long long)r->desc, (unsigned long long)r->obj);
        }
        fflush(f);
        Sleep(2000);
    }
    return 0;
}

static void pt_init(void)
{
    static char path[MAX_PATH];
    char v[8];
    pso_trace = GetEnvironmentVariableA("MGF_FH6_PSO_TRACE", v, sizeof v) == 1 && v[0] == '1';
    if (!pso_trace) return;
    pt_records = VirtualAlloc(NULL, sizeof(struct pt_record) * PT_CAPACITY, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!pt_records) { pso_trace = 0; return; }
    CreateDirectoryA("C:\\mgf", NULL);
    snprintf(path, sizeof path, "C:\\mgf\\fh6-pso-%lu.log", (unsigned long)GetCurrentProcessId());
    CloseHandle(CreateThread(NULL, 0, pt_writer, path, 0, NULL));
}
#endif
