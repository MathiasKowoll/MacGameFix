/*
 * wm-reader.c -- an IWMReader for DirectShow's WM ASF Reader, on FFmpeg.
 *
 * Linked into mgvf-asf-reader.dll. Wine's WM ASF Reader (qasf) opens a .wmv
 * through wmvcore's asynchronous IWMReader, and wine's reader prepares every
 * stream DECODED as it opens the file: with no decoder for the video -- WMV3
 * on any CrossOver without a staged codec -- the open fails, the filter has no
 * pins, and the game says "Failure to play movie" (Nioh, measured on CrossOver
 * Preview 27, 2026-10-14).
 *
 * So qasf's WMCreateReader is answered with this wrapper around wine's own
 * reader. It opens the file with wine's first, and if wine's succeeds every
 * later call is forwarded to it untouched. Only when wine's refuses does this
 * open the file itself -- FFmpeg's ASF demuxer and WMV1/2/3/VC-1 decoders --
 * and speak the reader's protocol to qasf: status from another thread, output
 * buffers borrowed through IWMReaderCallbackAdvanced::AllocateForOutput, and
 * decoded frames handed over with OnSample. Video goes out as YUV or RGB,
 * WMA audio as 16-bit PCM (NINJA GAIDEN 3's cutscenes carry both), each
 * output on its own thread.
 *
 * Part of MacGameVideoFix -- https://github.com/MathiasKowoll/MacGameVideoFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <wmsdkidl.h>
#include <stdio.h>
#include <stdarg.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>

#define LOGFILE "C:\\mgvf-asf-reader.log"

static LONG log_lines;

static void logf_(const char *fmt, ...)
{
    char buf[1024];
    int n;
    va_list ap;
    HANDLE h;
    DWORD w;

    if (InterlockedIncrement(&log_lines) > 200) return;
    n = snprintf(buf, sizeof(buf), "[wm-reader] ");
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof(buf) - n - 2, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof(buf) - 2) n = sizeof(buf) - 2;
    buf[n++] = '\r'; buf[n++] = '\n';
    h = CreateFileA(LOGFILE, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    WriteFile(h, buf, n, &w, NULL);
    CloseHandle(h);
}

/* In wmv-dmo.c. The kinds are its OUT_* order: NV12, YV12, IYUV, I420, YUY2,
 * UYVY, RGB32. */
void mgvf_write_420(int out, LONG stride, LONG width, LONG height, BOOL bottom_up,
                    const AVFrame *f, BYTE *dst);

#define FCC(a, b, c, d) \
    ((DWORD)(BYTE)(a) | ((DWORD)(BYTE)(b) << 8) | ((DWORD)(BYTE)(c) << 16) | ((DWORD)(BYTE)(d) << 24))
#define FOURCC_GUID(a, b, c, d) \
    { FCC(a, b, c, d), 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 } }

typedef struct
{
    RECT rcSource, rcTarget;
    DWORD dwBitRate, dwBitErrorRate;
    REFERENCE_TIME AvgTimePerFrame;
    BITMAPINFOHEADER bmiHeader;
} vih_t;

static const GUID g_video   = FOURCC_GUID('v', 'i', 'd', 's');
static const GUID g_audio   = FOURCC_GUID('a', 'u', 'd', 's');
static const GUID g_pcm     = { 0x00000001, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 } };
static const GUID g_wfx     = { 0x05589f81, 0xc356, 0x11ce, { 0xbf, 0x01, 0x00, 0xaa, 0x00, 0x55, 0x59, 0x5a } };
static const GUID g_vih     = { 0x05589f80, 0xc356, 0x11ce, { 0xbf, 0x01, 0x00, 0xaa, 0x00, 0x55, 0x59, 0x5a } };
static const GUID g_unknown = { 0x00000000, 0x0000, 0x0000, { 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
static const GUID g_reader  = { 0x96406bd6, 0x2b2b, 0x11d3, { 0xb3, 0x6b, 0x00, 0xc0, 0x4f, 0x61, 0x08, 0xff } };
static const GUID g_advanced = { 0x96406bea, 0x2b2b, 0x11d3, { 0xb3, 0x6b, 0x00, 0xc0, 0x4f, 0x61, 0x08, 0xff } };
static const GUID g_header  = { 0x96406bda, 0x2b2b, 0x11d3, { 0xb3, 0x6b, 0x00, 0xc0, 0x4f, 0x61, 0x08, 0xff } };
static const GUID g_props   = { 0x96406bd7, 0x2b2b, 0x11d3, { 0xb3, 0x6b, 0x00, 0xc0, 0x4f, 0x61, 0x08, 0xff } };
static const GUID g_mprops  = { 0x96406bce, 0x2b2b, 0x11d3, { 0xb3, 0x6b, 0x00, 0xc0, 0x4f, 0x61, 0x08, 0xff } };
static const GUID g_cb_adv  = { 0x96406beb, 0x2b2b, 0x11d3, { 0xb3, 0x6b, 0x00, 0xc0, 0x4f, 0x61, 0x08, 0xff } };

#define NS_E_INVALID_OUTPUT_FORMAT ((HRESULT)0xC00D0BBDL)
#define ASF_E_BUFFERTOOSMALL       ((HRESULT)0xC00D07D1L)
#define ASF_E_NOTFOUND             ((HRESULT)0xC00D07F0L)

/* What the output pin offers, YUV first as wine's own reader does. The kind
 * is the converter's. */
static const struct { GUID sub; DWORD fourcc; WORD bits; int kind; } kinds[] =
{
    { FOURCC_GUID('N', 'V', '1', '2'), FCC('N', 'V', '1', '2'), 12, 0 },
    { FOURCC_GUID('Y', 'V', '1', '2'), FCC('Y', 'V', '1', '2'), 12, 1 },
    { FOURCC_GUID('Y', 'U', 'Y', '2'), FCC('Y', 'U', 'Y', '2'), 16, 4 },
    { FOURCC_GUID('U', 'Y', 'V', 'Y'), FCC('U', 'Y', 'V', 'Y'), 16, 5 },
    { { 0xe436eb7e, 0x524f, 0x11ce, { 0x9f, 0x53, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 } }, BI_RGB, 32, 6 },
};
#define N_KINDS (sizeof(kinds) / sizeof(kinds[0]))

/* --------------------------------------------------- IWMOutputMediaProps */

struct props
{
    IWMOutputMediaProps iface;
    LONG ref;
    WM_MEDIA_TYPE mt;
    vih_t vih;
};

static struct props *props_impl(IWMOutputMediaProps *i) { return CONTAINING_RECORD(i, struct props, iface); }

static HRESULT WINAPI pr_QueryInterface(IWMOutputMediaProps *iface, REFIID iid, void **out)
{
    if (IsEqualGUID(iid, &g_unknown) || IsEqualGUID(iid, &g_mprops) || IsEqualGUID(iid, &g_props))
    {
        *out = iface;
        IWMOutputMediaProps_AddRef(iface);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI pr_AddRef(IWMOutputMediaProps *iface) { return InterlockedIncrement(&props_impl(iface)->ref); }
static ULONG WINAPI pr_Release(IWMOutputMediaProps *iface)
{
    struct props *p = props_impl(iface);
    ULONG ref = InterlockedDecrement(&p->ref);
    if (!ref) free(p);
    return ref;
}
static HRESULT WINAPI pr_GetType(IWMOutputMediaProps *iface, GUID *type)
{
    *type = props_impl(iface)->mt.majortype;
    return S_OK;
}
static HRESULT WINAPI pr_GetMediaType(IWMOutputMediaProps *iface, WM_MEDIA_TYPE *mt, DWORD *size)
{
    struct props *p = props_impl(iface);
    DWORD need = sizeof(WM_MEDIA_TYPE) + p->mt.cbFormat;
    if (!size) return E_POINTER;
    if (!mt) { *size = need; return S_OK; }
    if (*size < need) { *size = need; return ASF_E_BUFFERTOOSMALL; }
    *mt = p->mt;
    mt->pbFormat = (BYTE *)(mt + 1);
    memcpy(mt->pbFormat, &p->vih, p->mt.cbFormat);
    *size = need;
    return S_OK;
}
static HRESULT WINAPI pr_SetMediaType(IWMOutputMediaProps *iface, WM_MEDIA_TYPE *mt)
{
    struct props *p = props_impl(iface);
    if (!mt) return E_POINTER;
    p->mt = *mt;
    p->mt.pUnk = NULL;
    p->mt.cbFormat = mt->cbFormat < sizeof(p->vih) ? mt->cbFormat : sizeof(p->vih);
    memset(&p->vih, 0, sizeof(p->vih));
    if (mt->pbFormat && p->mt.cbFormat) memcpy(&p->vih, mt->pbFormat, p->mt.cbFormat);
    p->mt.pbFormat = (BYTE *)&p->vih;
    return S_OK;
}
static HRESULT WINAPI pr_GetStreamGroupName(IWMOutputMediaProps *iface, WCHAR *name, WORD *len)
{
    if (len) *len = 0;
    return S_OK;
}
static HRESULT WINAPI pr_GetConnectionName(IWMOutputMediaProps *iface, WCHAR *name, WORD *len)
{
    if (len) *len = 0;
    return S_OK;
}

static IWMOutputMediaPropsVtbl props_vtbl =
{
    pr_QueryInterface, pr_AddRef, pr_Release, pr_GetType, pr_GetMediaType, pr_SetMediaType,
    pr_GetStreamGroupName, pr_GetConnectionName,
};

static struct props *props_new(int k, LONG w, LONG h, REFERENCE_TIME avg)
{
    struct props *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->iface.lpVtbl = &props_vtbl;
    p->ref = 1;
    p->vih.AvgTimePerFrame = avg;
    p->vih.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    p->vih.bmiHeader.biWidth = w;
    p->vih.bmiHeader.biHeight = h;
    p->vih.bmiHeader.biPlanes = 1;
    p->vih.bmiHeader.biBitCount = kinds[k].bits;
    p->vih.bmiHeader.biCompression = kinds[k].fourcc;
    p->vih.bmiHeader.biSizeImage = kinds[k].bits == 12
        ? (DWORD)(w * h + 2 * ((w + 1) / 2) * ((h + 1) / 2)) : (DWORD)(w * (kinds[k].bits / 8) * h);
    p->mt.majortype = g_video;
    p->mt.subtype = kinds[k].sub;
    p->mt.bFixedSizeSamples = TRUE;
    p->mt.lSampleSize = p->vih.bmiHeader.biSizeImage;
    p->mt.formattype = g_vih;
    p->mt.cbFormat = sizeof(vih_t);
    p->mt.pbFormat = (BYTE *)&p->vih;
    return p;
}

/* 16-bit PCM at the stream's own rate and channel count: the one audio type
 * offered, and the one qasf's DirectSound path takes. The WAVEFORMATEX sits
 * in the same storage the video's VIDEOINFOHEADER does. */
static struct props *props_new_audio(UINT32 rate, UINT32 channels)
{
    struct props *p = calloc(1, sizeof(*p));
    WAVEFORMATEX *w;
    if (!p) return NULL;
    p->iface.lpVtbl = &props_vtbl;
    p->ref = 1;
    w = (WAVEFORMATEX *)&p->vih;
    w->wFormatTag = WAVE_FORMAT_PCM;
    w->nChannels = (WORD)channels;
    w->nSamplesPerSec = rate;
    w->wBitsPerSample = 16;
    w->nBlockAlign = (WORD)(channels * 2);
    w->nAvgBytesPerSec = rate * channels * 2;
    w->cbSize = 0;
    p->mt.majortype = g_audio;
    p->mt.subtype = g_pcm;
    p->mt.bFixedSizeSamples = TRUE;
    p->mt.lSampleSize = w->nBlockAlign;
    p->mt.formattype = g_wfx;
    p->mt.cbFormat = sizeof(WAVEFORMATEX);
    p->mt.pbFormat = (BYTE *)&p->vih;
    return p;
}

/* ------------------------------------------------------------- the reader */

#define MAX_OUT 4
/* How far the demuxer may run ahead of an output that is not taking packets:
 * a renderer that holds its first sample while the graph prerolls stops its
 * output's thread, and the other outputs must still be fed past it. */
#define MAX_QUEUED 512

struct pnode { struct pnode *next; AVPacket *pkt; };

struct out
{
    int av_index;
    AVCodecContext *dec;
    BOOL audio;
    LONG width, height;         /* video */
    REFERENCE_TIME avg;
    int kind;                   /* converter kind */
    LONG stride;
    BOOL bottom_up;
    UINT32 rate, channels;      /* audio */
    QWORD next_audio;
    DWORD size;
    BOOL selected, allocate;
    struct props *current;
    struct pnode *head, *tail;  /* under wm->cs */
    int count;
    HANDLE wake;
    HANDLE thread;
    BOOL done;
};

struct wm
{
    IWMReader reader;
    IWMReaderAdvanced advanced;
    IWMHeaderInfo header;
    LONG ref;
    IWMReader *real;            /* wine's; everything goes to it unless it refused */
    BOOL own;
    CRITICAL_SECTION cs;
    IWMReaderCallback *cb;
    IWMReaderCallbackAdvanced *cb_adv;
    void *context;
    HANDLE file;
    AVFormatContext *fmt;
    AVIOContext *avio;
    struct out out[MAX_OUT];
    int n_out;
    LONGLONG duration;          /* 100 ns */
    HANDLE thread;              /* the demuxer */
    volatile LONG stop, paused, demux_eof, finished;
    HANDLE resume;
    QWORD start;
    LONG delivered;
};

static struct wm *from_reader(IWMReader *i) { return CONTAINING_RECORD(i, struct wm, reader); }
static struct wm *from_adv(IWMReaderAdvanced *i) { return CONTAINING_RECORD(i, struct wm, advanced); }
static struct wm *from_header(IWMHeaderInfo *i) { return CONTAINING_RECORD(i, struct wm, header); }

/* Status goes to the callback from another thread, after the call that caused
 * it has returned: qasf resets its status word after Open, Start and Stop
 * return, and then waits. A status sent from inside the call would be lost. */
struct posted { struct wm *wm; WMT_STATUS status; HRESULT hr; };

static DWORD WINAPI post_thread(void *arg)
{
    struct posted *p = arg;
    IWMReaderCallback_OnStatus(p->wm->cb, p->status, p->hr, WMT_TYPE_DWORD, NULL, p->wm->context);
    IWMReader_Release(&p->wm->reader);
    free(p);
    return 0;
}

static void post_status(struct wm *wm, WMT_STATUS status, HRESULT hr)
{
    struct posted *p = malloc(sizeof(*p));
    HANDLE t;
    if (!p || !wm->cb) { free(p); return; }
    p->wm = wm; p->status = status; p->hr = hr;
    IWMReader_AddRef(&wm->reader);
    if ((t = CreateThread(NULL, 0, post_thread, p, 0, NULL))) CloseHandle(t);
    else { IWMReader_Release(&wm->reader); free(p); }
}

static int io_read(void *opaque, uint8_t *buf, int size)
{
    struct wm *wm = opaque;
    DWORD got = 0;
    if (!ReadFile(wm->file, buf, (DWORD)size, &got, NULL)) return AVERROR(EIO);
    return got ? (int)got : AVERROR_EOF;
}

static int64_t io_seek(void *opaque, int64_t offset, int whence)
{
    struct wm *wm = opaque;
    LARGE_INTEGER to, now;
    DWORD how = FILE_BEGIN;
    if ((whence & ~AVSEEK_FORCE) == AVSEEK_SIZE)
    {
        LARGE_INTEGER size;
        return GetFileSizeEx(wm->file, &size) ? size.QuadPart : -1;
    }
    switch (whence & ~AVSEEK_FORCE)
    {
    case SEEK_SET: how = FILE_BEGIN; break;
    case SEEK_CUR: how = FILE_CURRENT; break;
    case SEEK_END: how = FILE_END; break;
    default: return -1;
    }
    to.QuadPart = offset;
    if (!SetFilePointerEx(wm->file, to, &now, how)) return -1;
    return now.QuadPart;
}

static void q_clear(struct wm *wm, struct out *o)
{
    struct pnode *n;
    EnterCriticalSection(&wm->cs);
    while ((n = o->head)) { o->head = n->next; av_packet_free(&n->pkt); free(n); }
    o->tail = NULL;
    o->count = 0;
    LeaveCriticalSection(&wm->cs);
}

static void close_own(struct wm *wm)
{
    int i;
    for (i = 0; i < wm->n_out; i++)
    {
        q_clear(wm, &wm->out[i]);
        if (wm->out[i].dec) avcodec_free_context(&wm->out[i].dec);
        if (wm->out[i].current) IWMOutputMediaProps_Release(&wm->out[i].current->iface);
        if (wm->out[i].wake) CloseHandle(wm->out[i].wake);
        memset(&wm->out[i], 0, sizeof(wm->out[i]));
    }
    wm->n_out = 0;
    if (wm->fmt) avformat_close_input(&wm->fmt);
    if (wm->avio) { av_freep(&wm->avio->buffer); avio_context_free(&wm->avio); }
    if (wm->file && wm->file != INVALID_HANDLE_VALUE) CloseHandle(wm->file);
    wm->file = NULL;
}

static BOOL is_video(enum AVCodecID id)
{
    return id == AV_CODEC_ID_WMV3 || id == AV_CODEC_ID_WMV2 || id == AV_CODEC_ID_WMV1 || id == AV_CODEC_ID_VC1;
}

static BOOL is_audio(enum AVCodecID id)
{
    return id == AV_CODEC_ID_WMAV2 || id == AV_CODEC_ID_WMAPRO;
}

static void use_kind(struct out *o, int k, const vih_t *vih)
{
    LONG stride = o->width;
    o->kind = kinds[k].kind;
    o->bottom_up = FALSE;
    if (vih)
    {
        if (vih->bmiHeader.biWidth > stride) stride = vih->bmiHeader.biWidth;
        if (kinds[k].fourcc == BI_RGB && vih->bmiHeader.biHeight > 0) o->bottom_up = TRUE;
    }
    else if (kinds[k].fourcc == BI_RGB) o->bottom_up = TRUE;
    o->stride = kinds[k].bits == 12 ? stride : stride * (kinds[k].bits / 8);
    o->size = kinds[k].bits == 12 ? (DWORD)(stride * o->height + stride * ((o->height + 1) / 2))
                                  : (DWORD)(o->stride * o->height);
}

static HRESULT open_own(struct wm *wm, const WCHAR *url)
{
    unsigned char *iobuf;
    unsigned i;

    wm->file = CreateFileW(url, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (wm->file == INVALID_HANDLE_VALUE) { wm->file = NULL; return HRESULT_FROM_WIN32(GetLastError()); }
    iobuf = av_malloc(64 * 1024);
    wm->avio = iobuf ? avio_alloc_context(iobuf, 64 * 1024, 0, wm, io_read, NULL, io_seek) : NULL;
    wm->fmt = avformat_alloc_context();
    if (!wm->avio || !wm->fmt) { if (!wm->avio) av_free(iobuf); goto fail; }
    wm->fmt->pb = wm->avio;
    wm->fmt->flags |= AVFMT_FLAG_CUSTOM_IO;
    if (avformat_open_input(&wm->fmt, NULL, av_find_input_format("asf"), NULL) < 0) goto fail;
    avformat_find_stream_info(wm->fmt, NULL);

    for (i = 0; i < wm->fmt->nb_streams && wm->n_out < MAX_OUT; i++)
    {
        AVStream *st = wm->fmt->streams[i];
        const AVCodec *codec;
        struct out *o = &wm->out[wm->n_out];
        BOOL video = is_video(st->codecpar->codec_id), audio = is_audio(st->codecpar->codec_id);
        if (!video && !audio)
        {
            logf_("stream %u (%s) is neither WMV nor WMA; skipped", i, avcodec_get_name(st->codecpar->codec_id));
            continue;
        }
        if (!(codec = avcodec_find_decoder(st->codecpar->codec_id)) || !(o->dec = avcodec_alloc_context3(codec)))
            continue;
        avcodec_parameters_to_context(o->dec, st->codecpar);
        o->dec->pkt_timebase = st->time_base;
        o->dec->thread_count = 1;
        if (avcodec_open2(o->dec, codec, NULL) < 0) { avcodec_free_context(&o->dec); continue; }
        o->av_index = (int)i;
        o->selected = TRUE;
        o->audio = audio;
        o->wake = CreateEventW(NULL, FALSE, FALSE, NULL);
        if (video)
        {
            o->width = st->codecpar->width;
            o->height = st->codecpar->height;
            o->avg = st->avg_frame_rate.num ? (REFERENCE_TIME)(10000000.0 * st->avg_frame_rate.den / st->avg_frame_rate.num)
                                            : 333667;
            o->current = props_new(0, o->width, o->height, o->avg);
            use_kind(o, 0, NULL);
            logf_("output %d: %s %ldx%ld", wm->n_out, codec->name, o->width, o->height);
        }
        else
        {
            o->rate = st->codecpar->sample_rate;
            o->channels = st->codecpar->ch_layout.nb_channels;
            o->current = props_new_audio(o->rate, o->channels);
            o->size = o->rate * o->channels * 2;
            logf_("output %d: %s %u Hz, %u channels, as 16-bit PCM", wm->n_out, codec->name, o->rate, o->channels);
        }
        wm->n_out++;
    }
    if (!wm->n_out) { logf_("no WMV, VC-1 or WMA stream in this file"); goto fail; }
    wm->duration = wm->fmt->duration > 0 ? wm->fmt->duration * 10 : 0;
    return S_OK;
fail:
    close_own(wm);
    return E_FAIL;
}

static QWORD to_hns(struct wm *wm, struct out *o, int64_t v)
{
    return (QWORD)av_rescale_q(v, wm->fmt->streams[o->av_index]->time_base, (AVRational){ 1, 10000000 });
}

/* One decoded frame, into a buffer qasf lends, and handed over. */
static void deliver_frame(struct wm *wm, struct out *o, int idx, AVFrame *f)
{
    INSSBuffer *buf = NULL;
    BYTE *dst = NULL;
    DWORD max = 0, len;
    HRESULT hr;
    QWORD t, dur;
    int64_t ts = f->best_effort_timestamp;

    if (o->audio)
    {
        int n = f->nb_samples, ch = f->ch_layout.nb_channels, i, c;
        enum AVSampleFormat packed = av_get_packed_sample_fmt(f->format);
        BOOL planar = av_sample_fmt_is_planar(f->format);
        if (n <= 0 || ch <= 0 || (UINT32)ch != o->channels ||
            (packed != AV_SAMPLE_FMT_FLT && packed != AV_SAMPLE_FMT_S16)) return;
        t = ts == AV_NOPTS_VALUE ? o->next_audio : to_hns(wm, o, ts);
        dur = (QWORD)n * 10000000 / (o->rate ? o->rate : 44100);
        o->next_audio = t + dur;
        len = (DWORD)n * ch * 2;
        if (t + dur < wm->start) return;
        if (!wm->cb_adv || !o->allocate) return;
        hr = IWMReaderCallbackAdvanced_AllocateForOutput(wm->cb_adv, idx, len, &buf, wm->context);
        if (FAILED(hr) || !buf) return;
        if (SUCCEEDED(INSSBuffer_GetBuffer(buf, &dst)) && SUCCEEDED(INSSBuffer_GetMaxLength(buf, &max)) && max >= len)
        {
            int16_t *out16 = (int16_t *)dst;
            for (i = 0; i < n; i++)
                for (c = 0; c < ch; c++)
                {
                    float v = packed == AV_SAMPLE_FMT_FLT
                        ? (planar ? ((const float *)f->extended_data[c])[i] : ((const float *)f->extended_data[0])[i * ch + c])
                        : (planar ? ((const int16_t *)f->extended_data[c])[i] : ((const int16_t *)f->extended_data[0])[i * ch + c]) / 32768.0f;
                    int x = (int)(v * 32767.0f + (v >= 0 ? 0.5f : -0.5f));
                    out16[i * ch + c] = (int16_t)(x > 32767 ? 32767 : x < -32768 ? -32768 : x);
                }
            INSSBuffer_SetLength(buf, len);
            IWMReaderCallback_OnSample(wm->cb, idx, t, dur, WM_SF_CLEANPOINT, buf, wm->context);
        }
        INSSBuffer_Release(buf);
        return;
    }

    t = ts == AV_NOPTS_VALUE ? 0 : to_hns(wm, o, ts);
    dur = f->duration > 0 ? to_hns(wm, o, f->duration) : (QWORD)o->avg;
    if (t + dur < wm->start || f->format != AV_PIX_FMT_YUV420P) return;
    if (!wm->cb_adv || !o->allocate)
    {
        static LONG said;
        if (InterlockedIncrement(&said) == 1) logf_("the caller did not ask to allocate output buffers; frames dropped");
        return;
    }
    hr = IWMReaderCallbackAdvanced_AllocateForOutput(wm->cb_adv, idx, o->size, &buf, wm->context);
    if (FAILED(hr) || !buf)
    {
        static LONG said;
        if (InterlockedIncrement(&said) <= 3) logf_("AllocateForOutput -> 0x%08lx", (unsigned long)hr);
        return;
    }
    if (SUCCEEDED(INSSBuffer_GetBuffer(buf, &dst)) && SUCCEEDED(INSSBuffer_GetMaxLength(buf, &max)) && max >= o->size)
    {
        mgvf_write_420(o->kind, o->stride, o->width, o->height, o->bottom_up, f, dst);
        INSSBuffer_SetLength(buf, o->size);
        hr = IWMReaderCallback_OnSample(wm->cb, idx, t, dur, WM_SF_CLEANPOINT, buf, wm->context);
        {
            LONG n = InterlockedIncrement(&wm->delivered);
            if (n == 1 || n == 100 || n == 1000)
                logf_("frame %ld delivered, %llu ms -> 0x%08lx", n, (unsigned long long)(t / 10000), (unsigned long)hr);
        }
    }
    INSSBuffer_Release(buf);
}

struct out_arg { struct wm *wm; int idx; };

/* Each output decodes and delivers on its own thread. A video renderer that
 * holds its first sample until the graph runs blocks only this thread; the
 * audio renderer, which must preroll before the graph can run, is still fed.
 * With one thread for both, wine's own ASF reader deadlocked exactly so. */
static DWORD WINAPI out_thread(void *arg)
{
    struct out_arg *a = arg;
    struct wm *wm = a->wm;
    struct out *o = &wm->out[a->idx];
    int idx = a->idx;
    AVFrame *f = av_frame_alloc();
    BOOL drained = FALSE;
    free(a);

    while (!wm->stop && f)
    {
        struct pnode *n;
        if (wm->paused) { WaitForSingleObject(wm->resume, 50); continue; }
        EnterCriticalSection(&wm->cs);
        if ((n = o->head)) { o->head = n->next; if (!o->head) o->tail = NULL; o->count--; }
        LeaveCriticalSection(&wm->cs);
        if (n)
        {
            avcodec_send_packet(o->dec, n->pkt);
            av_packet_free(&n->pkt);
            free(n);
            while (!wm->stop && avcodec_receive_frame(o->dec, f) >= 0) { deliver_frame(wm, o, idx, f); av_frame_unref(f); }
            continue;
        }
        if (wm->demux_eof && !drained)
        {
            avcodec_send_packet(o->dec, NULL);
            while (!wm->stop && avcodec_receive_frame(o->dec, f) >= 0) { deliver_frame(wm, o, idx, f); av_frame_unref(f); }
            drained = TRUE;
            /* The last output to finish says so, once, for all of them. */
            if (!wm->stop && InterlockedIncrement(&wm->finished) == wm->n_out)
            {
                IWMReaderCallback_OnStatus(wm->cb, WMT_END_OF_STREAMING, S_OK, WMT_TYPE_DWORD, NULL, wm->context);
                IWMReaderCallback_OnStatus(wm->cb, WMT_EOF, S_OK, WMT_TYPE_DWORD, NULL, wm->context);
            }
            continue;
        }
        WaitForSingleObject(o->wake, 50);
    }
    av_frame_free(&f);
    return 0;
}

/* The demuxer: STARTED, then one thread per output, then packets sorted into
 * their outputs' queues; STOPPED once every thread is gone. */
static DWORD WINAPI play_thread(void *arg)
{
    struct wm *wm = arg;
    AVPacket *pkt = av_packet_alloc();
    int i;

    IWMReaderCallback_OnStatus(wm->cb, WMT_STARTED, S_OK, WMT_TYPE_DWORD, NULL, wm->context);
    for (i = 0; i < wm->n_out; i++)
    {
        struct out_arg *a;
        if (!wm->out[i].selected) { InterlockedIncrement(&wm->finished); continue; }
        if (!(a = malloc(sizeof(*a)))) continue;
        a->wm = wm; a->idx = i;
        wm->out[i].thread = CreateThread(NULL, 0, out_thread, a, 0, NULL);
        if (!wm->out[i].thread) free(a);
    }
    while (!wm->stop && pkt && !wm->demux_eof)
    {
        struct out *dest = NULL;
        BOOL full = FALSE;
        if (wm->paused) { WaitForSingleObject(wm->resume, 50); continue; }
        EnterCriticalSection(&wm->cs);
        for (i = 0; i < wm->n_out; i++) if (wm->out[i].selected && wm->out[i].count >= MAX_QUEUED) full = TRUE;
        LeaveCriticalSection(&wm->cs);
        if (full) { Sleep(5); continue; }
        if (av_read_frame(wm->fmt, pkt) < 0) { wm->demux_eof = TRUE; break; }
        for (i = 0; i < wm->n_out; i++)
            if (wm->out[i].av_index == pkt->stream_index && wm->out[i].selected) dest = &wm->out[i];
        if (dest)
        {
            struct pnode *n = malloc(sizeof(*n));
            AVPacket *mine = av_packet_alloc();
            if (n && mine)
            {
                av_packet_move_ref(mine, pkt);
                n->pkt = mine; n->next = NULL;
                EnterCriticalSection(&wm->cs);
                if (dest->tail) dest->tail->next = n; else dest->head = n;
                dest->tail = n;
                dest->count++;
                LeaveCriticalSection(&wm->cs);
                SetEvent(dest->wake);
            }
            else { free(n); av_packet_free(&mine); }
        }
        av_packet_unref(pkt);
    }
    av_packet_free(&pkt);
    for (i = 0; i < wm->n_out; i++) if (wm->out[i].wake) SetEvent(wm->out[i].wake);
    while (!wm->stop) WaitForSingleObject(wm->resume, 50);
    for (i = 0; i < wm->n_out; i++)
        if (wm->out[i].thread)
        {
            SetEvent(wm->out[i].wake);
            WaitForSingleObject(wm->out[i].thread, INFINITE);
            CloseHandle(wm->out[i].thread);
            wm->out[i].thread = NULL;
        }
    IWMReaderCallback_OnStatus(wm->cb, WMT_STOPPED, S_OK, WMT_TYPE_DWORD, NULL, wm->context);
    return 0;
}

static void join_player(struct wm *wm)
{
    if (!wm->thread) return;
    wm->stop = TRUE;
    SetEvent(wm->resume);
    WaitForSingleObject(wm->thread, INFINITE);
    CloseHandle(wm->thread);
    wm->thread = NULL;
}

/* ---------------------------------------------------------------- IWMReader */

static HRESULT WINAPI rd_QueryInterface(IWMReader *iface, REFIID iid, void **out)
{
    struct wm *wm = from_reader(iface);
    if (IsEqualGUID(iid, &g_unknown) || IsEqualGUID(iid, &g_reader)) *out = &wm->reader;
    else if (wm->own && IsEqualGUID(iid, &g_advanced)) *out = &wm->advanced;
    else if (wm->own && IsEqualGUID(iid, &g_header)) *out = &wm->header;
    else if (!wm->own) return IWMReader_QueryInterface(wm->real, iid, out);
    else { *out = NULL; return E_NOINTERFACE; }
    IWMReader_AddRef(&wm->reader);
    return S_OK;
}

static ULONG WINAPI rd_AddRef(IWMReader *iface) { return InterlockedIncrement(&from_reader(iface)->ref); }

static ULONG WINAPI rd_Release(IWMReader *iface)
{
    struct wm *wm = from_reader(iface);
    ULONG ref = InterlockedDecrement(&wm->ref);
    if (!ref)
    {
        join_player(wm);
        close_own(wm);
        if (wm->cb_adv) IWMReaderCallbackAdvanced_Release(wm->cb_adv);
        if (wm->cb) IWMReaderCallback_Release(wm->cb);
        if (wm->real) IWMReader_Release(wm->real);
        CloseHandle(wm->resume);
        DeleteCriticalSection(&wm->cs);
        free(wm);
    }
    return ref;
}

static HRESULT WINAPI rd_Open(IWMReader *iface, const WCHAR *url, IWMReaderCallback *cb, void *context)
{
    struct wm *wm = from_reader(iface);
    HRESULT hr = IWMReader_Open(wm->real, url, cb, context), mine;
    if (SUCCEEDED(hr)) return hr;
    if (!url || !cb) return hr;
    mine = open_own(wm, url);
    {
        static LONG said;
        if (InterlockedIncrement(&said) <= 5 || FAILED(mine))
            logf_("wine's reader refused %ls (0x%08lx); ours -> 0x%08lx", url, (unsigned long)hr, (unsigned long)mine);
    }
    if (FAILED(mine)) return hr;
    wm->own = TRUE;
    wm->cb = cb; IWMReaderCallback_AddRef(cb);
    if (FAILED(IWMReaderCallback_QueryInterface(cb, &g_cb_adv, (void **)&wm->cb_adv))) wm->cb_adv = NULL;
    wm->context = context;
    post_status(wm, WMT_OPENED, S_OK);
    return S_OK;
}

static HRESULT WINAPI rd_Close(IWMReader *iface)
{
    struct wm *wm = from_reader(iface);
    if (!wm->own) return IWMReader_Close(wm->real);
    join_player(wm);
    close_own(wm);
    post_status(wm, WMT_CLOSED, S_OK);
    return S_OK;
}

static HRESULT WINAPI rd_GetOutputCount(IWMReader *iface, DWORD *count)
{
    struct wm *wm = from_reader(iface);
    if (!wm->own) return IWMReader_GetOutputCount(wm->real, count);
    *count = wm->n_out;
    return S_OK;
}

static HRESULT WINAPI rd_GetOutputProps(IWMReader *iface, DWORD output, IWMOutputMediaProps **props)
{
    struct wm *wm = from_reader(iface);
    struct props *p;
    if (!wm->own) return IWMReader_GetOutputProps(wm->real, output, props);
    if (output >= (DWORD)wm->n_out) return E_INVALIDARG;
    if (!(p = calloc(1, sizeof(*p)))) return E_OUTOFMEMORY;
    *p = *wm->out[output].current;
    p->ref = 1;
    p->mt.pbFormat = (BYTE *)&p->vih;
    *props = &p->iface;
    return S_OK;
}

static HRESULT WINAPI rd_SetOutputProps(IWMReader *iface, DWORD output, IWMOutputMediaProps *props)
{
    struct wm *wm = from_reader(iface);
    struct props *p;
    WM_MEDIA_TYPE *mt;
    DWORD size = 0;
    unsigned k;
    if (!wm->own) return IWMReader_SetOutputProps(wm->real, output, props);
    if (output >= (DWORD)wm->n_out || !props) return E_INVALIDARG;
    if (FAILED(IWMOutputMediaProps_GetMediaType(props, NULL, &size)) || !(mt = malloc(size))) return E_FAIL;
    if (FAILED(IWMOutputMediaProps_GetMediaType(props, mt, &size))) { free(mt); return E_FAIL; }
    if (wm->out[output].audio)
    {
        if (!IsEqualGUID(&mt->subtype, &g_pcm)) { free(mt); logf_("SetOutputProps: audio other than PCM"); return NS_E_INVALID_OUTPUT_FORMAT; }
        free(mt);
        return S_OK;
    }
    for (k = 0; k < N_KINDS; k++) if (IsEqualGUID(&mt->subtype, &kinds[k].sub)) break;
    if (k == N_KINDS) { free(mt); logf_("SetOutputProps: a subtype not offered"); return NS_E_INVALID_OUTPUT_FORMAT; }
    if (!(p = props_new(k, wm->out[output].width, wm->out[output].height, wm->out[output].avg))) { free(mt); return E_OUTOFMEMORY; }
    pr_SetMediaType(&p->iface, mt);
    EnterCriticalSection(&wm->cs);
    if (wm->out[output].current) IWMOutputMediaProps_Release(&wm->out[output].current->iface);
    wm->out[output].current = p;
    use_kind(&wm->out[output], (int)k,
             IsEqualGUID(&mt->formattype, &g_vih) && mt->cbFormat >= sizeof(vih_t) ? (const vih_t *)mt->pbFormat : NULL);
    LeaveCriticalSection(&wm->cs);
    logf_("output %lu: kind %d, stride %ld, %lu bytes a frame", (unsigned long)output, wm->out[output].kind,
          wm->out[output].stride, (unsigned long)wm->out[output].size);
    free(mt);
    return S_OK;
}

static HRESULT WINAPI rd_GetOutputFormatCount(IWMReader *iface, DWORD output, DWORD *count)
{
    struct wm *wm = from_reader(iface);
    if (!wm->own) return IWMReader_GetOutputFormatCount(wm->real, output, count);
    if (output >= (DWORD)wm->n_out) return E_INVALIDARG;
    *count = wm->out[output].audio ? 1 : N_KINDS;
    return S_OK;
}

static HRESULT WINAPI rd_GetOutputFormat(IWMReader *iface, DWORD output, DWORD index, IWMOutputMediaProps **props)
{
    struct wm *wm = from_reader(iface);
    struct props *p;
    if (!wm->own) return IWMReader_GetOutputFormat(wm->real, output, index, props);
    if (output >= (DWORD)wm->n_out) return E_INVALIDARG;
    if (wm->out[output].audio)
    {
        if (index) return NS_E_INVALID_OUTPUT_FORMAT;
        if (!(p = props_new_audio(wm->out[output].rate, wm->out[output].channels))) return E_OUTOFMEMORY;
        *props = &p->iface;
        return S_OK;
    }
    if (index >= N_KINDS) return NS_E_INVALID_OUTPUT_FORMAT;
    if (!(p = props_new((int)index, wm->out[output].width, wm->out[output].height, wm->out[output].avg)))
        return E_OUTOFMEMORY;
    *props = &p->iface;
    return S_OK;
}

static HRESULT WINAPI rd_Start(IWMReader *iface, QWORD start, QWORD duration, float rate, void *context)
{
    struct wm *wm = from_reader(iface);
    int i;
    if (!wm->own) return IWMReader_Start(wm->real, start, duration, rate, context);
    join_player(wm);
    wm->context = context;
    wm->start = start;
    if (av_seek_frame(wm->fmt, -1, (int64_t)(start / 10), AVSEEK_FLAG_BACKWARD) < 0)
        avformat_seek_file(wm->fmt, -1, INT64_MIN, 0, 0, 0);
    for (i = 0; i < wm->n_out; i++)
    {
        avcodec_flush_buffers(wm->out[i].dec);
        q_clear(wm, &wm->out[i]);
        wm->out[i].next_audio = start;
    }
    wm->stop = FALSE;
    wm->paused = FALSE;
    wm->demux_eof = FALSE;
    wm->finished = 0;
    ResetEvent(wm->resume);
    wm->thread = CreateThread(NULL, 0, play_thread, wm, 0, NULL);
    return wm->thread ? S_OK : E_FAIL;
}

static HRESULT WINAPI rd_Stop(IWMReader *iface)
{
    struct wm *wm = from_reader(iface);
    if (!wm->own) return IWMReader_Stop(wm->real);
    if (wm->thread) { wm->stop = TRUE; SetEvent(wm->resume); }
    else post_status(wm, WMT_STOPPED, S_OK);
    return S_OK;
}

static HRESULT WINAPI rd_Pause(IWMReader *iface)
{
    struct wm *wm = from_reader(iface);
    if (!wm->own) return IWMReader_Pause(wm->real);
    wm->paused = TRUE;
    return S_OK;
}

static HRESULT WINAPI rd_Resume(IWMReader *iface)
{
    struct wm *wm = from_reader(iface);
    if (!wm->own) return IWMReader_Resume(wm->real);
    wm->paused = FALSE;
    SetEvent(wm->resume);
    return S_OK;
}

static IWMReaderVtbl reader_vtbl =
{
    rd_QueryInterface, rd_AddRef, rd_Release, rd_Open, rd_Close, rd_GetOutputCount,
    rd_GetOutputProps, rd_SetOutputProps, rd_GetOutputFormatCount, rd_GetOutputFormat,
    rd_Start, rd_Stop, rd_Pause, rd_Resume,
};

/* -------------------------------------------------------- IWMReaderAdvanced */

static HRESULT WINAPI ad_QueryInterface(IWMReaderAdvanced *i, REFIID iid, void **out)
{ return rd_QueryInterface(&from_adv(i)->reader, iid, out); }
static ULONG WINAPI ad_AddRef(IWMReaderAdvanced *i) { return rd_AddRef(&from_adv(i)->reader); }
static ULONG WINAPI ad_Release(IWMReaderAdvanced *i) { return rd_Release(&from_adv(i)->reader); }
static HRESULT WINAPI ad_SetUserProvidedClock(IWMReaderAdvanced *i, BOOL v) { return v ? E_NOTIMPL : S_OK; }
static HRESULT WINAPI ad_GetUserProvidedClock(IWMReaderAdvanced *i, BOOL *v) { *v = FALSE; return S_OK; }
static HRESULT WINAPI ad_DeliverTime(IWMReaderAdvanced *i, QWORD t) { return E_NOTIMPL; }
static HRESULT WINAPI ad_SetManualStreamSelection(IWMReaderAdvanced *i, BOOL v) { return S_OK; }
static HRESULT WINAPI ad_GetManualStreamSelection(IWMReaderAdvanced *i, BOOL *v) { *v = FALSE; return S_OK; }

static HRESULT WINAPI ad_SetStreamsSelected(IWMReaderAdvanced *i, WORD count, WORD *numbers, WMT_STREAM_SELECTION *sel)
{
    struct wm *wm = from_adv(i);
    WORD k;
    /* qasf numbers its outputs from 1, stream n being output n - 1. */
    for (k = 0; k < count; k++)
        if (numbers[k] >= 1 && numbers[k] <= wm->n_out)
            wm->out[numbers[k] - 1].selected = sel[k] != WMT_OFF;
    return S_OK;
}
static HRESULT WINAPI ad_GetStreamSelected(IWMReaderAdvanced *i, WORD n, WMT_STREAM_SELECTION *sel)
{
    struct wm *wm = from_adv(i);
    if (n < 1 || n > wm->n_out) return E_INVALIDARG;
    *sel = wm->out[n - 1].selected ? WMT_ON : WMT_OFF;
    return S_OK;
}
static HRESULT WINAPI ad_SetReceiveSelectionCallbacks(IWMReaderAdvanced *i, BOOL v) { return S_OK; }
static HRESULT WINAPI ad_GetReceiveSelectionCallbacks(IWMReaderAdvanced *i, BOOL *v) { *v = FALSE; return S_OK; }
static HRESULT WINAPI ad_SetReceiveStreamSamples(IWMReaderAdvanced *i, WORD n, BOOL v) { return v ? E_NOTIMPL : S_OK; }
static HRESULT WINAPI ad_GetReceiveStreamSamples(IWMReaderAdvanced *i, WORD n, BOOL *v) { *v = FALSE; return S_OK; }
static HRESULT WINAPI ad_SetAllocateForOutput(IWMReaderAdvanced *i, DWORD o, BOOL v)
{
    struct wm *wm = from_adv(i);
    if (o >= (DWORD)wm->n_out) return E_INVALIDARG;
    wm->out[o].allocate = v;
    return S_OK;
}
static HRESULT WINAPI ad_GetAllocateForOutput(IWMReaderAdvanced *i, DWORD o, BOOL *v)
{
    struct wm *wm = from_adv(i);
    if (o >= (DWORD)wm->n_out) return E_INVALIDARG;
    *v = wm->out[o].allocate;
    return S_OK;
}
static HRESULT WINAPI ad_SetAllocateForStream(IWMReaderAdvanced *i, WORD n, BOOL v) { return v ? E_NOTIMPL : S_OK; }
static HRESULT WINAPI ad_GetAllocateForStream(IWMReaderAdvanced *i, WORD n, BOOL *v) { *v = FALSE; return S_OK; }
static HRESULT WINAPI ad_GetStatistics(IWMReaderAdvanced *i, WM_READER_STATISTICS *s) { return E_NOTIMPL; }
static HRESULT WINAPI ad_SetClientInfo(IWMReaderAdvanced *i, WM_READER_CLIENTINFO *c) { return S_OK; }
static HRESULT WINAPI ad_GetMaxOutputSampleSize(IWMReaderAdvanced *i, DWORD o, DWORD *max)
{
    struct wm *wm = from_adv(i);
    if (o >= (DWORD)wm->n_out) return E_INVALIDARG;
    *max = wm->out[o].size;
    return S_OK;
}
static HRESULT WINAPI ad_GetMaxStreamSampleSize(IWMReaderAdvanced *i, WORD n, DWORD *max) { return E_NOTIMPL; }
static HRESULT WINAPI ad_NotifyLateDelivery(IWMReaderAdvanced *i, QWORD t) { return S_OK; }

static IWMReaderAdvancedVtbl advanced_vtbl =
{
    ad_QueryInterface, ad_AddRef, ad_Release, ad_SetUserProvidedClock, ad_GetUserProvidedClock,
    ad_DeliverTime, ad_SetManualStreamSelection, ad_GetManualStreamSelection, ad_SetStreamsSelected,
    ad_GetStreamSelected, ad_SetReceiveSelectionCallbacks, ad_GetReceiveSelectionCallbacks,
    ad_SetReceiveStreamSamples, ad_GetReceiveStreamSamples, ad_SetAllocateForOutput,
    ad_GetAllocateForOutput, ad_SetAllocateForStream, ad_GetAllocateForStream, ad_GetStatistics,
    ad_SetClientInfo, ad_GetMaxOutputSampleSize, ad_GetMaxStreamSampleSize, ad_NotifyLateDelivery,
};

/* ------------------------------------------------------------ IWMHeaderInfo */

static HRESULT WINAPI hd_QueryInterface(IWMHeaderInfo *i, REFIID iid, void **out)
{ return rd_QueryInterface(&from_header(i)->reader, iid, out); }
static ULONG WINAPI hd_AddRef(IWMHeaderInfo *i) { return rd_AddRef(&from_header(i)->reader); }
static ULONG WINAPI hd_Release(IWMHeaderInfo *i) { return rd_Release(&from_header(i)->reader); }
static HRESULT WINAPI hd_GetAttributeCount(IWMHeaderInfo *i, WORD s, WORD *n) { *n = 1; return S_OK; }
static HRESULT WINAPI hd_GetAttributeByIndex(IWMHeaderInfo *i, WORD index, WORD *s, WCHAR *name, WORD *nlen,
                                             WMT_ATTR_DATATYPE *type, BYTE *value, WORD *len) { return E_NOTIMPL; }
static HRESULT WINAPI hd_GetAttributeByName(IWMHeaderInfo *i, WORD *stream, const WCHAR *name,
                                            WMT_ATTR_DATATYPE *type, BYTE *value, WORD *len)
{
    struct wm *wm = from_header(i);
    if (!name || !len) return E_POINTER;
    if (lstrcmpW(name, L"Duration")) return ASF_E_NOTFOUND;
    if (type) *type = WMT_TYPE_QWORD;
    if (!value) { *len = sizeof(QWORD); return S_OK; }
    if (*len < sizeof(QWORD)) { *len = sizeof(QWORD); return ASF_E_BUFFERTOOSMALL; }
    *(QWORD *)value = (QWORD)wm->duration;
    *len = sizeof(QWORD);
    return S_OK;
}
static HRESULT WINAPI hd_SetAttribute(IWMHeaderInfo *i, WORD s, const WCHAR *n, WMT_ATTR_DATATYPE t,
                                      const BYTE *v, WORD l) { return E_NOTIMPL; }
static HRESULT WINAPI hd_GetMarkerCount(IWMHeaderInfo *i, WORD *n) { *n = 0; return S_OK; }
static HRESULT WINAPI hd_GetMarker(IWMHeaderInfo *i, WORD idx, WCHAR *n, WORD *l, QWORD *t) { return E_NOTIMPL; }
static HRESULT WINAPI hd_AddMarker(IWMHeaderInfo *i, LPCWSTR_WMSDK_TYPE_SAFE n, QWORD t) { return E_NOTIMPL; }
static HRESULT WINAPI hd_RemoveMarker(IWMHeaderInfo *i, WORD idx) { return E_NOTIMPL; }
static HRESULT WINAPI hd_GetScriptCount(IWMHeaderInfo *i, WORD *n) { *n = 0; return S_OK; }
static HRESULT WINAPI hd_GetScript(IWMHeaderInfo *i, WORD idx, WCHAR *t, WORD *tl, WCHAR *c, WORD *cl, QWORD *time)
{ return E_NOTIMPL; }
static HRESULT WINAPI hd_AddScript(IWMHeaderInfo *i, LPCWSTR_WMSDK_TYPE_SAFE t, LPCWSTR_WMSDK_TYPE_SAFE c, QWORD time)
{ return E_NOTIMPL; }
static HRESULT WINAPI hd_RemoveScript(IWMHeaderInfo *i, WORD idx) { return E_NOTIMPL; }

static IWMHeaderInfoVtbl header_vtbl =
{
    hd_QueryInterface, hd_AddRef, hd_Release, hd_GetAttributeCount, hd_GetAttributeByIndex,
    hd_GetAttributeByName, hd_SetAttribute, hd_GetMarkerCount, hd_GetMarker, hd_AddMarker,
    hd_RemoveMarker, hd_GetScriptCount, hd_GetScript, hd_AddScript, hd_RemoveScript,
};

/* Wrap wine's reader. The wrapper owns the reference it is given. */
__declspec(dllexport) HRESULT WINAPI MGVF_WrapWMReader(IWMReader *real, IWMReader **out)
{
    struct wm *wm;
    if (!real || !out) return E_POINTER;
    if (!(wm = calloc(1, sizeof(*wm)))) return E_OUTOFMEMORY;
    wm->reader.lpVtbl = &reader_vtbl;
    wm->advanced.lpVtbl = &advanced_vtbl;
    wm->header.lpVtbl = &header_vtbl;
    wm->ref = 1;
    wm->real = real;
    wm->resume = CreateEventW(NULL, FALSE, FALSE, NULL);
    InitializeCriticalSection(&wm->cs);
    *out = &wm->reader;
    return S_OK;
}
