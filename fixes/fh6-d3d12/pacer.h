// pacer: shortens the stop Rosetta makes when its store of translated code fills up.
//
// Forza Horizon 6's protection rewrites code all the time. Under Rosetta every rewritten piece that runs
// again is translated again, the translator's store fills, and Rosetta empties it in one go. While it does,
// every thread that needs the translator waits: at rest that is a stop of 100-170 ms every ~10 s, with the
// main thread and the protection's threads silent from the same instant to the same instant and the threads
// that take no traps running on. Rosetta alone does it, with no Wine and no game
// (tools/rosetta-store-stop/trapfreeze.c), and there the stop lasts about 0.4 us per translation held.
//
// So this keeps a thread that runs large functions never seen before. They fill the store with few
// translations, Rosetta empties it more often, and each time it holds less. Played 2026-11-16 on a MacBook
// Pro M4 Max, standing in the world, 75-90 s a setting, the frame rate the same in all of them:
//   off           2-4 stops of 125-175 ms, and the game's usual gap of ~55 ms every 1.4 s
//   40            one gap of 101 ms, none between 65 and 100 ms, the usual gap ~61 ms
//   50            longest 89 ms            65   longest 82 ms, 26 gaps a minute of 65-100 ms
//   25            one of 103 ms, 18 a minute of 65-100 ms          15   12 stops of 100-129 ms
//   100           no long stop, but a gap of ~90 ms every 1.1 s: worse than off
//   40 with functions of 1024 bytes   stops of up to 247 ms: worse than off, small functions add translations
// More is not better: the thread takes the translator from the game's own threads.
//
// MGF_FH6_ROSETTA_PACER=<duty>[,<bytes>] turns it on: the share of each 10 ms it works, 1-100, and the
// size of each function, 2048-65536 bytes (4096 if left out). Without the variable, or with 0, no thread is
// started. The value that suits depends on the processor, so there is no default; 40 is what was played.
// While C:\mgf\pacer.txt exists, "<duty> [bytes]" in it replaces the variable's values, read twice a second,
// so a value can be looked for without starting the game again. Every ten seconds a line goes to
// C:\mgf\fh6-pacer-<pid>.log: the system time, the settings, the functions made and the longest single
// function (write, translate, run), which is a stop as this thread saw it.
//
// Rosetta only. Where the processor is ARM64 for Windows too (the FEX side), nothing is started.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef MGF_PACER_H
#define MGF_PACER_H

#define PACER_REGION ((SIZE_T)64 << 20)

static unsigned pacer_env_duty, pacer_env_bytes;

static unsigned pacer_clamp_bytes(unsigned b) { return !b ? 4096 : b < 2048 ? 2048 : b > 65536 ? 65536 : b; }
static inline LONGLONG pacer_now(void) { LARGE_INTEGER q; QueryPerformanceCounter(&q); return q.QuadPart; }

static DWORD WINAPI pacer_thread(LPVOID unused)
{
    static const unsigned char body[4] = { 0xf3, 0x0f, 0xb8, 0xc1 };     // popcnt eax, ecx
    static char path[MAX_PATH];
    unsigned char *region = NULL;
    SIZE_T offset = 0;
    unsigned duty = pacer_env_duty, bytes = pacer_env_bytes, value = 1;
    unsigned long long made = 0, made_logged = 0;
    LONGLONG freq, last_read = 0, last_log, worst = 0;
    LARGE_INTEGER f;
    FILE *log;

    (void)unused;
    QueryPerformanceFrequency(&f); freq = f.QuadPart;
    CreateDirectoryA("C:\\mgf", NULL);
    snprintf(path, sizeof path, "C:\\mgf\\fh6-pacer-%lu.log", (unsigned long)GetCurrentProcessId());
    log = fopen(path, "w");
    if (log) { fprintf(log, "# fh6 pacer (see pacer.h): filetime duty bytes made_since_last longest_us\n"); fflush(log); }
    last_log = pacer_now();
    for (;;) {
        LONGLONG now = pacer_now(), slice;
        if ((now - last_read) * 2 >= freq) {
            FILE *c = fopen("C:\\mgf\\pacer.txt", "r");
            unsigned d = pacer_env_duty, b = pacer_env_bytes;
            if (c) { b = 0; if (fscanf(c, "%u %u", &d, &b) < 1) d = 0; fclose(c); }
            duty = d > 100 ? 100 : d; bytes = pacer_clamp_bytes(b);
            last_read = now;
        }
        if (log && (now - last_log) >= 10 * freq) {
            FILETIME ft; GetSystemTimePreciseAsFileTime(&ft);
            fprintf(log, "%llu %u %u %llu %lld\n", ((unsigned long long)ft.dwHighDateTime << 32) | ft.dwLowDateTime, duty, bytes,
                    made - made_logged, (long long)(worst * 1000000 / freq));
            fflush(log); made_logged = made; worst = 0; last_log = now;
        }
        if (!duty) { Sleep(100); continue; }
        if (!region) {
            region = VirtualAlloc(NULL, PACER_REGION, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
            if (!region) { if (log) { fprintf(log, "# no memory for the region\n"); fflush(log); } return 0; }
        }
        slice = now;
        do {      // duty percent of 10 ms
            unsigned char *p;
            unsigned n = 0;
            LONGLONG t0 = pacer_now(), t;
            if (offset + bytes > PACER_REGION) offset = 0;
            p = region + offset; offset += bytes;
            p[n++] = 0xb8; memcpy(p + n, &value, 4); n += 4;       // mov eax, value: makes every function new
            while (n + sizeof body + 1 <= bytes) { memcpy(p + n, body, sizeof body); n += sizeof body; }
            p[n] = 0xc3;
            ((unsigned (*)(void))p)();
            value += 3; made++;
            t = pacer_now() - t0; if (t > worst) worst = t;
        } while ((pacer_now() - slice) * 10000 < (LONGLONG)duty * freq);
        if (duty < 100) Sleep((100 - duty) / 10);
    }
}

static void pacer_init(void)
{
    char v[32];
    USHORT process = 0, native = 0;
    DWORD n = GetEnvironmentVariableA("MGF_FH6_ROSETTA_PACER", v, sizeof v);
    unsigned d = 0, b = 0;

    if (!n || n >= sizeof v || sscanf(v, "%u,%u", &d, &b) < 1 || !d) return;
    {   // by name: the headers this is built with only declare it for a newer Windows
        BOOL (WINAPI *is_wow64_2)(HANDLE, USHORT *, USHORT *) = (void *)GetProcAddress(GetModuleHandleA("kernel32.dll"), "IsWow64Process2");
        if (is_wow64_2 && is_wow64_2(GetCurrentProcess(), &process, &native) && native == IMAGE_FILE_MACHINE_ARM64) return;
    }
    pacer_env_duty = d > 100 ? 100 : d; pacer_env_bytes = pacer_clamp_bytes(b);
    CloseHandle(CreateThread(NULL, 0, pacer_thread, NULL, 0, NULL));
}
#endif
