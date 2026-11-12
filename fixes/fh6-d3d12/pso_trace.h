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
struct pt_record { LONGLONG start, ticks; UINT64 vs, ps; DWORD tid; LONG hr; LONG kind; volatile LONG ready; };
static struct pt_record *pt_records;
static volatile LONG pt_next, pt_dropped;
static int pso_trace;

static inline LONGLONG pt_now(void) { LARGE_INTEGER q; QueryPerformanceCounter(&q); return q.QuadPart; }

static void pt_add(int kind, LONGLONG start, UINT64 vs, UINT64 ps, HRESULT hr)
{
    LONGLONG end = pt_now();
    LONG i = InterlockedIncrement(&pt_next) - 1;
    struct pt_record *r;
    if (i >= PT_CAPACITY) { InterlockedIncrement(&pt_dropped); return; }
    r = &pt_records[i];
    r->start = start; r->ticks = end - start; r->vs = vs; r->ps = ps;
    r->tid = GetCurrentThreadId(); r->hr = (LONG)hr; r->kind = kind;
    InterlockedExchange(&r->ready, 1);
}

static DWORD WINAPI pt_writer(LPVOID path)
{
    FILE *f = fopen((const char *)path, "w");
    LARGE_INTEGER freq; LONG done = 0;
    if (!f) return 0;
    QueryPerformanceFrequency(&freq);
    fprintf(f, "# fh6 pso trace: kind start_qpc duration_us tid vs ps hr (G graphics, C compute, S stream, L/M library load)\n");
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
            fprintf(f, "%c %lld %lld %lu %016llx %016llx %08lx\n", pt_kind[r->kind], (long long)r->start,
                    (long long)(r->ticks * 1000000 / freq.QuadPart), (unsigned long)r->tid,
                    (unsigned long long)r->vs, (unsigned long long)r->ps, (unsigned long)r->hr);
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
