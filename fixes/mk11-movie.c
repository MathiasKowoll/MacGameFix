/*
 * mk11-movie.c -- Mortal Kombat 11's movies: grey pictures with purple and
 * green bands, and choppy motion. Included by mk11-face-fix.c, which carries it.
 *
 * WHERE IT COMES FROM. The game reads its movies (the .scx files in Movies, MP4 with H.264
 * High 1080p and AAC) with a player of its own: it demuxes the file, creates
 * Media Foundation's H.264 decoder with CoCreateInstance(CLSID_CMSH264DecoderMFT),
 * feeds it one access unit per sample and draws what comes out as NV12. Two
 * things go wrong with CrossOver's decoder, which runs on GStreamer:
 *
 *   1. NV12 is not offered. CrossOver's winegstreamer leaves NV12 out of
 *      GetOutputAvailableType on macOS, so the first type is YV12; the game takes
 *      it and draws the planar picture as NV12, which is the grey picture with a
 *      purple top and a green bottom (measured: a decoded frame rendered as YV12
 *      is clean, the same bytes rendered as NV12 are the screenshot).
 *      SetOutputType still accepts NV12, so it is offered again here as type 0,
 *      a copy of the first type with the subtype changed.
 *
 *   2. Frames come out in decode order. The game's samples carry no usable time
 *      (measured: every frame handed out has the same one), and the
 *      movies use B-frame pyramids (decode order 0 4 2 1 3 8 6 5 7 ...). Windows'
 *      decoder hands frames out in display order regardless; CrossOver's needs
 *      the times to reorder, so it hands them out as decoded and the motion jerks
 *      back and forth. Each access unit's picture order count is read from its
 *      slice header here, a few decoded frames are held back, and the game is
 *      handed them in that order.
 *
 * The decode-order fault and the reordering were found and published first by
 * Anton Pavliuk (https://github.com/CyberDogFK/mk11-crossover-fix, MIT); this is
 * a separate implementation of the same idea.
 *
 * A stream this does not understand -- picture order count type 1, field coding,
 * a sample that is not Annex B -- is passed through as decoded and the log says so.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <mfapi.h>
#include <mftransform.h>
#include <mferror.h>

#define MFT_IDX(m) (offsetof(IMFTransformVtbl, m) / sizeof(void *))
#define MOVIE_DEPTH 3           /* frames held back; the movies need 2 (has_b_frames) */
#define MOVIE_DECODERS 4
#define MOVIE_PENDING 64

static const GUID clsid_h264_decoder = { 0x62ce7e72, 0x4c71, 0x4d20, { 0xb1, 0x5d, 0x45, 0x28, 0x31, 0xa8, 0x7d, 0x9d } };
static const GUID movie_nv12 = { 0x3231564e, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 } };
static const GUID movie_subtype = { 0xf7e34c9a, 0x42e8, 0x4714, { 0xb7, 0x4b, 0xcb, 0x29, 0xd7, 0x2c, 0x35, 0xe5 } };

static LONG movies_seen, nv12_offered;

/* From mfplat.dll, which the game imports; looked up rather than linked, so the
 * carrier keeps its import table. */
static HRESULT create_media_type(IMFMediaType **type)
{
    static HRESULT (WINAPI *create)(IMFMediaType **);
    if (!create)
    {
        HMODULE m = GetModuleHandleA("mfplat.dll");
        if (!m) m = LoadLibraryA("mfplat.dll");
        create = m ? (HRESULT (WINAPI *)(IMFMediaType **))(void *)GetProcAddress(m, "MFCreateMediaType") : NULL;
    }
    return create ? create(type) : E_NOTIMPL;
}

/* ---- reading the bitstream ---------------------------------------------------- */
typedef struct { const BYTE *p; size_t len, bit; } bits;

static UINT getbits(bits *b, int n)
{
    UINT v = 0;
    while (n-- > 0)
    {
        v <<= 1;
        if (b->bit < b->len * 8) v |= (b->p[b->bit / 8] >> (7 - b->bit % 8)) & 1;
        b->bit++;
    }
    return v;
}

static UINT getue(bits *b)
{
    int zeros = 0;
    while (!getbits(b, 1) && zeros < 32) zeros++;
    return zeros ? (1u << zeros) - 1 + getbits(b, zeros) : 0;
}

static int getse(bits *b)
{
    UINT v = getue(b);
    return v & 1 ? (int)((v + 1) / 2) : -(int)(v / 2);
}

static BOOL overrun(const bits *b) { return b->bit > b->len * 8; }

/* The start of a NAL unit's payload with its emulation-prevention bytes taken out. */
static size_t unescape_nal(const BYTE *src, size_t len, BYTE *dst, size_t max)
{
    size_t i, n = 0, zeros = 0;
    for (i = 0; i < len && n < max; i++)
    {
        if (zeros >= 2 && src[i] == 3) { zeros = 0; continue; }
        zeros = src[i] ? 0 : zeros + 1;
        dst[n++] = src[i];
    }
    return n;
}

typedef struct
{
    IMFTransform *t;
    BOOL off, have_sps;
    int frame_num_bits, poc_lsb_bits, poc_type, separate_planes;
    int prev_msb, prev_lsb;
    LONGLONG epoch, decode_index;
    LONGLONG pending[MOVIE_PENDING];
    int head, count;
    struct { LONGLONG key; BYTE *data; DWORD len, cap; } held[MOVIE_DEPTH + 1];
    int nheld;
    BOOL draining;
    LONG frames, moved;
} movie_decoder;

static movie_decoder decoders[MOVIE_DECODERS];
static CRITICAL_SECTION movie_cs;
static int next_slot;

static void skip_scaling_list(bits *b, int size)
{
    int last = 8, next = 8, j;
    for (j = 0; j < size; j++)
    {
        if (next) next = (last + getse(b) + 256) % 256;
        last = next ? next : last;
    }
}

/* What the slice header needs from a sequence parameter set. FALSE for one
 * whose order cannot be read here. */
static BOOL read_sps(movie_decoder *d, const BYTE *nal, size_t len)
{
    BYTE buf[256];
    bits b;
    UINT profile;
    b.p = buf; b.len = unescape_nal(nal + 1, len - 1, buf, sizeof(buf)); b.bit = 0;
    profile = getbits(&b, 8);
    getbits(&b, 16);                    /* constraint flags, level */
    getue(&b);                          /* seq_parameter_set_id */
    d->separate_planes = 0;
    if (profile == 100 || profile == 110 || profile == 122 || profile == 244 || profile == 44 || profile == 83
            || profile == 86 || profile == 118 || profile == 128 || profile == 138 || profile == 139
            || profile == 134 || profile == 135)
    {
        UINT chroma = getue(&b);
        if (chroma == 3) d->separate_planes = getbits(&b, 1);
        getue(&b); getue(&b);           /* bit depths */
        getbits(&b, 1);                 /* qpprime_y_zero_transform_bypass_flag */
        if (getbits(&b, 1))             /* seq_scaling_matrix_present_flag */
        {
            int i;
            for (i = 0; i < (chroma != 3 ? 8 : 12); i++)
                if (getbits(&b, 1)) skip_scaling_list(&b, i < 6 ? 16 : 64);
        }
    }
    d->frame_num_bits = (int)getue(&b) + 4;
    d->poc_type = (int)getue(&b);
    if (d->poc_type == 0) d->poc_lsb_bits = (int)getue(&b) + 4;
    else if (d->poc_type == 1) return FALSE;
    getue(&b);                          /* max_num_ref_frames */
    getbits(&b, 1);                     /* gaps_in_frame_num_value_allowed_flag */
    getue(&b); getue(&b);               /* picture size in macroblocks */
    if (!getbits(&b, 1)) return FALSE;  /* frame_mbs_only_flag: field coding not handled */
    return !overrun(&b) && d->frame_num_bits <= 16 && (d->poc_type != 0 || d->poc_lsb_bits <= 16);
}

/* The display order key of the picture in an Annex B access unit, or -1. */
static LONGLONG access_unit_key(movie_decoder *d, const BYTE *p, size_t len)
{
    size_t i = 0;
    while (i + 3 < len)
    {
        size_t start, end;
        int type, ref;
        if (p[i] || p[i + 1] || p[i + 2] != 1) { i++; continue; }
        start = i + 3;
        for (end = start; end + 2 < len && (p[end] || p[end + 1] || p[end + 2] > 1); end++)
            ;
        if (end + 2 >= len) end = len;
        i = end;
        if (start >= end) continue;
        type = p[start] & 0x1f;
        ref = (p[start] >> 5) & 3;
        if (type == 7)
        {
            if (!(d->have_sps = read_sps(d, p + start, end - start))) return -1;
        }
        else if ((type == 1 || type == 5) && d->have_sps)
        {
            BYTE buf[64];
            bits b;
            int max_lsb, lsb, msb;
            b.p = buf; b.len = unescape_nal(p + start + 1, end - start - 1, buf, sizeof(buf)); b.bit = 0;
            getue(&b);                  /* first_mb_in_slice */
            getue(&b);                  /* slice_type */
            getue(&b);                  /* pic_parameter_set_id */
            if (d->separate_planes) getbits(&b, 2);
            getbits(&b, d->frame_num_bits);
            if (type == 5)
            {
                getue(&b);              /* idr_pic_id */
                d->prev_msb = d->prev_lsb = 0;
                d->epoch++;
            }
            if (overrun(&b)) return -1;
            if (d->poc_type == 2)       /* display order is decode order */
                return (d->epoch << 32) + (d->decode_index++ & 0x7fffffff);
            max_lsb = 1 << d->poc_lsb_bits;
            lsb = (int)getbits(&b, d->poc_lsb_bits);
            if (overrun(&b)) return -1;
            if (lsb < d->prev_lsb && d->prev_lsb - lsb >= max_lsb / 2) msb = d->prev_msb + max_lsb;
            else if (lsb > d->prev_lsb && lsb - d->prev_lsb > max_lsb / 2) msb = d->prev_msb - max_lsb;
            else msb = d->prev_msb;
            if (ref) { d->prev_msb = msb; d->prev_lsb = lsb; }
            return (d->epoch << 32) + (LONGLONG)(msb + lsb) + 0x40000000;
        }
    }
    return -1;
}

/* ---- the decoder's state --------------------------------------------------------- */
static movie_decoder *decoder_of(IMFTransform *t)
{
    int i;
    for (i = 0; i < MOVIE_DECODERS; i++) if (decoders[i].t == t) return &decoders[i];
    return NULL;
}

/* A fresh state for a decoder just created. The game makes one per movie and the
 * next often lands at the same address, so nothing of the last one may remain;
 * with every slot taken, the oldest goes. Frame buffers are kept for reuse. */
static void adopt(IMFTransform *t)
{
    movie_decoder *d = decoder_of(t);
    struct { BYTE *data; DWORD cap; } keep[MOVIE_DEPTH + 1];
    int i;
    if (!d)
    {
        for (i = 0; i < MOVIE_DECODERS && !d; i++) if (!decoders[i].t) d = &decoders[i];
        if (!d) { d = &decoders[next_slot]; next_slot = (next_slot + 1) % MOVIE_DECODERS; }
    }
    if (d->frames)
        log_msg("movie: %ld frames, %ld handed out in a different order than decoded", d->frames, d->moved);
    for (i = 0; i <= MOVIE_DEPTH; i++) { keep[i].data = d->held[i].data; keep[i].cap = d->held[i].cap; }
    memset(d, 0, sizeof(*d));
    for (i = 0; i <= MOVIE_DEPTH; i++) { d->held[i].data = keep[i].data; d->held[i].cap = keep[i].cap; }
    d->t = t;
}

/* Back to the start of a stream; the frame buffers are kept for reuse. */
static void restart(movie_decoder *d)
{
    if (d->frames)
        log_msg("movie: %ld frames, %ld handed out in a different order than decoded", d->frames, d->moved);
    d->nheld = d->head = d->count = 0;
    d->prev_msb = d->prev_lsb = 0;
    d->decode_index = 0;
    d->frames = d->moved = 0;
    d->draining = FALSE;
    d->off = FALSE;
}

/* The bytes of a sample's first buffer into `slot` (to_sample FALSE), or back. */
static BOOL move_frame(IMFSample *s, BYTE **data, DWORD *len, DWORD *cap, BOOL to_sample)
{
    IMFMediaBuffer *b = NULL;
    BYTE *p;
    DWORD max = 0, cur = 0;
    BOOL ok = FALSE;
    if (FAILED(IMFSample_GetBufferByIndex(s, 0, &b)) || !b) return FALSE;
    if (SUCCEEDED(IMFMediaBuffer_Lock(b, &p, &max, &cur)))
    {
        if (to_sample)
        {
            if (*len <= max) { memcpy(p, *data, *len); IMFMediaBuffer_SetCurrentLength(b, *len); ok = TRUE; }
        }
        else
        {
            if (cur > *cap)
            {
                BYTE *n = realloc(*data, cur);
                if (n) { *data = n; *cap = cur; }
            }
            if (cur <= *cap) { memcpy(*data, p, cur); *len = cur; ok = TRUE; }
        }
        IMFMediaBuffer_Unlock(b);
    }
    IMFMediaBuffer_Release(b);
    return ok;
}

/* Hands the game the held frame that comes first in display order. */
static HRESULT hand_out(movie_decoder *d, MFT_OUTPUT_DATA_BUFFER *out, DWORD *status)
{
    int i, best = 0;
    BOOL ok;
    BYTE *data;
    DWORD cap;
    for (i = 1; i < d->nheld; i++) if (d->held[i].key < d->held[best].key) best = i;
    ok = move_frame(out->pSample, &d->held[best].data, &d->held[best].len, &d->held[best].cap, TRUE);
    if (best) d->moved++;
    /* The rest stay oldest first; the emptied buffer goes to the end for reuse. */
    data = d->held[best].data; cap = d->held[best].cap;
    memmove(&d->held[best], &d->held[best + 1], (size_t)(d->nheld - best - 1) * sizeof(d->held[0]));
    d->nheld--;
    d->held[d->nheld].data = data; d->held[d->nheld].cap = cap; d->held[d->nheld].len = 0;
    out->dwStatus = 0;
    if (status) *status = 0;
    return ok ? S_OK : E_FAIL;
}

/* ---- the decoder's methods ---------------------------------------------------------- */
static HRESULT STDMETHODCALLTYPE movie_GetOutputAvailableType(IMFTransform *t, DWORD stream, DWORD index,
        IMFMediaType **type)
{
    HRESULT (STDMETHODCALLTYPE *real)(IMFTransform *, DWORD, DWORD, IMFMediaType **)
            = orig_fn(t, MFT_IDX(GetOutputAvailableType));
    IMFMediaType *first = NULL, *nv12 = NULL;
    GUID sub = { 0 };
    if (!type || FAILED(real(t, stream, 0, &first)) || !first) return real(t, stream, index, type);
    if (SUCCEEDED(IMFMediaType_GetGUID(first, &movie_subtype, &sub)) && IsEqualGUID(&sub, &movie_nv12))
    {
        IMFMediaType_Release(first);
        return real(t, stream, index, type);
    }
    if (index) { IMFMediaType_Release(first); return real(t, stream, index - 1, type); }
    if (FAILED(create_media_type(&nv12)) || !nv12) { *type = first; return S_OK; }
    IMFMediaType_CopyAllItems(first, (IMFAttributes *)nv12);
    IMFMediaType_SetGUID(nv12, &movie_subtype, &movie_nv12);
    IMFMediaType_Release(first);
    if (!InterlockedExchange(&nv12_offered, 1)) log_msg("movie: the H.264 decoder offers no NV12; it is offered first");
    *type = nv12;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE movie_ProcessInput(IMFTransform *t, DWORD stream, IMFSample *s, DWORD flags)
{
    HRESULT (STDMETHODCALLTYPE *real)(IMFTransform *, DWORD, IMFSample *, DWORD) = orig_fn(t, MFT_IDX(ProcessInput));
    movie_decoder *d, saved;
    IMFMediaBuffer *b = NULL;
    LONGLONG key = -1;
    HRESULT hr;
    EnterCriticalSection(&movie_cs);
    d = decoder_of(t);
    if (!d || d->off || !s || FAILED(IMFSample_ConvertToContiguousBuffer(s, &b)) || !b)
    {
        LeaveCriticalSection(&movie_cs);
        return real(t, stream, s, flags);
    }
    {
        BYTE *p;
        DWORD len = 0;
        saved = *d;
        if (SUCCEEDED(IMFMediaBuffer_Lock(b, &p, NULL, &len)))
        {
            key = access_unit_key(d, p, len);
            IMFMediaBuffer_Unlock(b);
        }
        IMFMediaBuffer_Release(b);
    }
    hr = real(t, stream, s, flags);
    if (FAILED(hr))
    {
        /* Not taken: the same access unit comes again. */
        d->have_sps = saved.have_sps; d->prev_msb = saved.prev_msb; d->prev_lsb = saved.prev_lsb;
        d->epoch = saved.epoch; d->decode_index = saved.decode_index;
    }
    else if (key < 0 || d->count == MOVIE_PENDING)
    {
        log_msg("movie: the frame order cannot be read from this stream; frames are left as decoded");
        d->off = TRUE;
    }
    else
    {
        d->pending[(d->head + d->count++) % MOVIE_PENDING] = key;
        d->draining = FALSE;
    }
    LeaveCriticalSection(&movie_cs);
    return hr;
}

static HRESULT STDMETHODCALLTYPE movie_ProcessOutput(IMFTransform *t, DWORD flags, DWORD count,
        MFT_OUTPUT_DATA_BUFFER *out, DWORD *status)
{
    HRESULT (STDMETHODCALLTYPE *real)(IMFTransform *, DWORD, DWORD, MFT_OUTPUT_DATA_BUFFER *, DWORD *)
            = orig_fn(t, MFT_IDX(ProcessOutput));
    movie_decoder *d;
    HRESULT hr;
    EnterCriticalSection(&movie_cs);
    d = decoder_of(t);
    if (!d || d->off || count != 1 || !out || !out[0].pSample)
    {
        LeaveCriticalSection(&movie_cs);
        return real(t, flags, count, out, status);
    }
    hr = real(t, flags, count, out, status);
    if (hr == S_OK)
    {
        int n = d->nheld;
        if (!d->count || !move_frame(out[0].pSample, &d->held[n].data, &d->held[n].len, &d->held[n].cap, FALSE))
        {
            /* More frames than access units: the decoder is not one frame per
             * sample after all. What is held goes first, then frames as decoded. */
            log_msg("movie: decoder output does not line up with its input; frames are left as decoded");
            d->off = TRUE;
            LeaveCriticalSection(&movie_cs);
            return hr;
        }
        d->held[n].key = d->pending[d->head];
        d->head = (d->head + 1) % MOVIE_PENDING;
        d->count--;
        d->nheld++;
        d->frames++;
        if (d->nheld > MOVIE_DEPTH) hr = hand_out(d, &out[0], status);
        else { out[0].dwStatus = 0; hr = MF_E_TRANSFORM_NEED_MORE_INPUT; }
    }
    else if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT && d->draining && d->nheld)
        hr = hand_out(d, &out[0], status);
    LeaveCriticalSection(&movie_cs);
    return hr;
}

static HRESULT STDMETHODCALLTYPE movie_ProcessMessage(IMFTransform *t, MFT_MESSAGE_TYPE msg, ULONG_PTR param)
{
    HRESULT (STDMETHODCALLTYPE *real)(IMFTransform *, MFT_MESSAGE_TYPE, ULONG_PTR) = orig_fn(t, MFT_IDX(ProcessMessage));
    movie_decoder *d;
    EnterCriticalSection(&movie_cs);
    if ((d = decoder_of(t)))
    {
        if (msg == MFT_MESSAGE_COMMAND_FLUSH || msg == MFT_MESSAGE_NOTIFY_START_OF_STREAM
                || msg == MFT_MESSAGE_NOTIFY_BEGIN_STREAMING)
            restart(d);
        else if (msg == MFT_MESSAGE_COMMAND_DRAIN)
            d->draining = TRUE;
    }
    LeaveCriticalSection(&movie_cs);
    return real(t, msg, param);
}

/* ---- the decoder's creation ---------------------------------------------------------- */
typedef HRESULT (WINAPI *cocreate_fn)(REFCLSID, LPUNKNOWN, DWORD, REFIID, LPVOID *);
static cocreate_fn real_CoCreateInstance;

static HRESULT WINAPI movie_CoCreateInstance(REFCLSID clsid, LPUNKNOWN outer, DWORD ctx, REFIID iid, LPVOID *out)
{
    HRESULT hr = real_CoCreateInstance(clsid, outer, ctx, iid, out);
    IMFTransform *t = NULL;
    if (FAILED(hr) || !clsid || !out || !*out || !IsEqualGUID(clsid, &clsid_h264_decoder)) return hr;
    if (SUCCEEDED(IUnknown_QueryInterface((IUnknown *)*out, &IID_IMFTransform, (void **)&t)) && t)
    {
        EnterCriticalSection(&movie_cs);
        adopt(t);
        LeaveCriticalSection(&movie_cs);
        hook_slot(t, MFT_IDX(GetOutputAvailableType), (void *)movie_GetOutputAvailableType);
        hook_slot(t, MFT_IDX(ProcessInput), (void *)movie_ProcessInput);
        hook_slot(t, MFT_IDX(ProcessOutput), (void *)movie_ProcessOutput);
        hook_slot(t, MFT_IDX(ProcessMessage), (void *)movie_ProcessMessage);
        IMFTransform_Release(t);
        if (InterlockedIncrement(&movies_seen) <= 3) log_msg("movie: H.264 decoder %p taken in hand", *out);
    }
    return hr;
}

/* The executable's import of CoCreateInstance, by name. */
static int redirect_cocreate(void)
{
    BYTE *base = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    DWORD rva = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    IMAGE_IMPORT_DESCRIPTOR *imp;
    int n = 0;
    InitializeCriticalSection(&movie_cs);
    if (!rva) return 0;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + rva); imp->Name; ++imp)
    {
        IMAGE_THUNK_DATA *orig, *iat;
        if (lstrcmpiA((const char *)base + imp->Name, "ole32.dll") != 0) continue;
        orig = (IMAGE_THUNK_DATA *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        iat = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
        for (; orig->u1.AddressOfData; ++orig, ++iat)
        {
            DWORD old;
            if (IMAGE_SNAP_BY_ORDINAL(orig->u1.Ordinal)
                    || lstrcmpA((const char *)((IMAGE_IMPORT_BY_NAME *)(base + orig->u1.AddressOfData))->Name,
                                "CoCreateInstance")
                    || (void *)(ULONG_PTR)iat->u1.Function == (void *)movie_CoCreateInstance)
                continue;
            if (!VirtualProtect(&iat->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) continue;
            if (!real_CoCreateInstance) real_CoCreateInstance = (cocreate_fn)(ULONG_PTR)iat->u1.Function;
            iat->u1.Function = (ULONG_PTR)movie_CoCreateInstance;
            VirtualProtect(&iat->u1.Function, sizeof(void *), old, &old);
            n++;
        }
    }
    return n;
}
