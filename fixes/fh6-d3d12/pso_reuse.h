// pso_reuse: one pipeline object per graphics pipeline description.
//
// Forza Horizon 6 asks D3D12 for about 22,500 graphics pipelines on entering the world, and 30% of them
// are exact repeats of a description it asked for earlier and still holds (measured 2026-11-12: 6,856 of
// 22,516, 2.1 s of the 11.6 s D3DMetal spent creating them). D3DMetal builds a new object every time.
// This hands back the object made for the first request instead, so a repeat costs a lookup.
//
// The key is every field of the description the game passed, written out field by field (padding never
// enters it): shaders by their DXBC container hash and length, input layout and stream output by content,
// the root signature by identity. A hit compares the whole key, not only its hash. The cache keeps a
// reference to each pipeline and to its root signature, so a root signature's address cannot be reused by
// a different one while an entry names it. Descriptions this cannot key with certainty are created as
// before: a shader without a DXBC hash, or a cached blob.
//
// MGF_FH6_PSO_REUSE=0 turns it off. It is also off with the debug and inspection paths, which count every
// creation.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef MGF_PSO_REUSE_H
#define MGF_PSO_REUSE_H

static int pso_reuse = 1;
static volatile LONG pr_hits, pr_misses;

typedef struct { UINT8 *p; SIZE_T n, cap; BOOL ok; } PrKey;
typedef struct PrEntry { struct PrEntry *next; UINT64 hash; SIZE_T len; ID3D12PipelineState *obj; IUnknown *root; UINT8 key[]; } PrEntry;
#define PR_BUCKETS 65536
static PrEntry **pr_table;
static SRWLOCK pr_lock = SRWLOCK_INIT;

static void pr_put(PrKey *k, const void *src, SIZE_T n)
{
    if (!k->ok) return;
    if (k->n + n > k->cap) {
        SIZE_T cap = k->cap ? k->cap * 2 : 1024; UINT8 *p;
        while (cap < k->n + n) cap *= 2;
        if (!(p = realloc(k->p, cap))) { k->ok = FALSE; return; }
        k->p = p; k->cap = cap;
    }
    memcpy(k->p + k->n, src, n); k->n += n;
}
#define PR_F(k, x) pr_put((k), &(x), sizeof(x))
static void pr_str(PrKey *k, const char *s) { if (s) pr_put(k, s, strlen(s) + 1); else pr_put(k, "", 1); }
static void pr_code(PrKey *k, D3D12_SHADER_BYTECODE b)
{
    static const UINT8 zero[16];
    PR_F(k, b.BytecodeLength);
    if (!b.pShaderBytecode || !b.BytecodeLength) return;
    // DXBC containers carry a 16-byte hash of their contents at offset 4; without one there is no
    // identity cheaper than the whole shader, so the description is not keyed.
    if (b.BytecodeLength < 32 || memcmp(b.pShaderBytecode, "DXBC", 4) || !memcmp((const UINT8 *)b.pShaderBytecode + 4, zero, 16)) { k->ok = FALSE; return; }
    pr_put(k, (const UINT8 *)b.pShaderBytecode + 4, 16);
}
static BOOL pr_key_graphics(const D3D12_GRAPHICS_PIPELINE_STATE_DESC *d, PrKey *k)
{
    UINT i;
    k->p = NULL; k->n = k->cap = 0; k->ok = TRUE;
    if (!d || d->CachedPSO.pCachedBlob || d->CachedPSO.CachedBlobSizeInBytes) return k->ok = FALSE;
    PR_F(k, d->pRootSignature);
    pr_code(k, d->VS); pr_code(k, d->PS); pr_code(k, d->DS); pr_code(k, d->HS); pr_code(k, d->GS);
    PR_F(k, d->StreamOutput.NumEntries); PR_F(k, d->StreamOutput.NumStrides); PR_F(k, d->StreamOutput.RasterizedStream);
    for (i = 0; i < d->StreamOutput.NumEntries; i++) {
        const D3D12_SO_DECLARATION_ENTRY *e;
        if (!d->StreamOutput.pSODeclaration) { k->ok = FALSE; break; }
        e = &d->StreamOutput.pSODeclaration[i];
        PR_F(k, e->Stream); pr_str(k, e->SemanticName); PR_F(k, e->SemanticIndex);
        PR_F(k, e->StartComponent); PR_F(k, e->ComponentCount); PR_F(k, e->OutputSlot);
    }
    if (d->StreamOutput.NumStrides) {
        if (d->StreamOutput.pBufferStrides) pr_put(k, d->StreamOutput.pBufferStrides, sizeof(UINT) * d->StreamOutput.NumStrides);
        else k->ok = FALSE;
    }
    PR_F(k, d->BlendState.AlphaToCoverageEnable); PR_F(k, d->BlendState.IndependentBlendEnable);
    for (i = 0; i < 8; i++) {
        const D3D12_RENDER_TARGET_BLEND_DESC *t = &d->BlendState.RenderTarget[i];
        PR_F(k, t->BlendEnable); PR_F(k, t->LogicOpEnable); PR_F(k, t->SrcBlend); PR_F(k, t->DestBlend); PR_F(k, t->BlendOp);
        PR_F(k, t->SrcBlendAlpha); PR_F(k, t->DestBlendAlpha); PR_F(k, t->BlendOpAlpha); PR_F(k, t->LogicOp); PR_F(k, t->RenderTargetWriteMask);
    }
    PR_F(k, d->SampleMask);
    PR_F(k, d->RasterizerState.FillMode); PR_F(k, d->RasterizerState.CullMode); PR_F(k, d->RasterizerState.FrontCounterClockwise);
    PR_F(k, d->RasterizerState.DepthBias); PR_F(k, d->RasterizerState.DepthBiasClamp); PR_F(k, d->RasterizerState.SlopeScaledDepthBias);
    PR_F(k, d->RasterizerState.DepthClipEnable); PR_F(k, d->RasterizerState.MultisampleEnable); PR_F(k, d->RasterizerState.AntialiasedLineEnable);
    PR_F(k, d->RasterizerState.ForcedSampleCount); PR_F(k, d->RasterizerState.ConservativeRaster);
    PR_F(k, d->DepthStencilState.DepthEnable); PR_F(k, d->DepthStencilState.DepthWriteMask); PR_F(k, d->DepthStencilState.DepthFunc);
    PR_F(k, d->DepthStencilState.StencilEnable); PR_F(k, d->DepthStencilState.StencilReadMask); PR_F(k, d->DepthStencilState.StencilWriteMask);
    PR_F(k, d->DepthStencilState.FrontFace.StencilFailOp); PR_F(k, d->DepthStencilState.FrontFace.StencilDepthFailOp);
    PR_F(k, d->DepthStencilState.FrontFace.StencilPassOp); PR_F(k, d->DepthStencilState.FrontFace.StencilFunc);
    PR_F(k, d->DepthStencilState.BackFace.StencilFailOp); PR_F(k, d->DepthStencilState.BackFace.StencilDepthFailOp);
    PR_F(k, d->DepthStencilState.BackFace.StencilPassOp); PR_F(k, d->DepthStencilState.BackFace.StencilFunc);
    PR_F(k, d->InputLayout.NumElements);
    for (i = 0; i < d->InputLayout.NumElements; i++) {
        const D3D12_INPUT_ELEMENT_DESC *e;
        if (!d->InputLayout.pInputElementDescs) { k->ok = FALSE; break; }
        e = &d->InputLayout.pInputElementDescs[i];
        pr_str(k, e->SemanticName); PR_F(k, e->SemanticIndex); PR_F(k, e->Format); PR_F(k, e->InputSlot);
        PR_F(k, e->AlignedByteOffset); PR_F(k, e->InputSlotClass); PR_F(k, e->InstanceDataStepRate);
    }
    PR_F(k, d->IBStripCutValue); PR_F(k, d->PrimitiveTopologyType); PR_F(k, d->NumRenderTargets);
    for (i = 0; i < 8; i++) PR_F(k, d->RTVFormats[i]);
    PR_F(k, d->DSVFormat); PR_F(k, d->SampleDesc.Count); PR_F(k, d->SampleDesc.Quality); PR_F(k, d->NodeMask); PR_F(k, d->Flags);
    if (!k->ok) { free(k->p); k->p = NULL; }
    return k->ok;
}
static void pr_free(PrKey *k) { free(k->p); k->p = NULL; }
static UINT64 pr_hash(const PrKey *k)
{
    UINT64 h = 14695981039346656037ull; SIZE_T i;
    for (i = 0; i < k->n; i++) h = (h ^ k->p[i]) * 1099511628211ull;
    return h;
}
static PrEntry *pr_find_locked(const PrKey *k, UINT64 h)
{
    PrEntry *e;
    for (e = pr_table[h & (PR_BUCKETS - 1)]; e; e = e->next)
        if (e->hash == h && e->len == k->n && !memcmp(e->key, k->p, k->n)) return e;
    return NULL;
}
// TRUE when the description was made before: *out then holds that pipeline, as riid, with its own reference.
static BOOL pr_lookup(const PrKey *k, UINT64 h, REFIID riid, void **out, HRESULT *hr)
{
    PrEntry *e; ID3D12PipelineState *obj = NULL;
    AcquireSRWLockShared(&pr_lock);
    if ((e = pr_find_locked(k, h))) { obj = e->obj; obj->lpVtbl->AddRef(obj); }
    ReleaseSRWLockShared(&pr_lock);
    if (!obj) { InterlockedIncrement(&pr_misses); return FALSE; }
    *hr = obj->lpVtbl->QueryInterface(obj, riid, out);
    obj->lpVtbl->Release(obj);
    if (FAILED(*hr)) return FALSE;   // created normally instead
    InterlockedIncrement(&pr_hits);
    return TRUE;
}
static void pr_insert(const PrKey *k, UINT64 h, void *made, ID3D12RootSignature *root)
{
    PrEntry *e; ID3D12PipelineState *obj = NULL;
    if (!made || FAILED(((IUnknown *)made)->lpVtbl->QueryInterface((IUnknown *)made, &IID_ID3D12PipelineState, (void **)&obj)) || !obj) return;
    if (!(e = malloc(sizeof *e + k->n))) { obj->lpVtbl->Release(obj); return; }
    e->hash = h; e->len = k->n; e->obj = obj; e->root = (IUnknown *)root; memcpy(e->key, k->p, k->n);
    if (e->root) e->root->lpVtbl->AddRef(e->root);
    AcquireSRWLockExclusive(&pr_lock);
    if (pr_find_locked(k, h)) {   // another thread made the same one meanwhile; keep the first
        ReleaseSRWLockExclusive(&pr_lock);
        if (e->root) e->root->lpVtbl->Release(e->root);
        obj->lpVtbl->Release(obj); free(e); return;
    }
    e->next = pr_table[h & (PR_BUCKETS - 1)]; pr_table[h & (PR_BUCKETS - 1)] = e;
    ReleaseSRWLockExclusive(&pr_lock);
}
static void pr_init(void)
{
    char v[8];
    if (GetEnvironmentVariableA("MGF_FH6_PSO_REUSE", v, sizeof v) == 1 && v[0] == '0') pso_reuse = 0;
    if (pso_reuse && !(pr_table = calloc(PR_BUCKETS, sizeof *pr_table))) pso_reuse = 0;
}
#endif
