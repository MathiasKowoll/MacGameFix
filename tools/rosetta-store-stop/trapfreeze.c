/* trapfreeze.c: Rosetta stops every thread that needs its translator, now and then, when code is rewritten
 * all the time. No Wine and no game: this is what Forza Horizon 6 shows at rest (fixes/fh6-d3d12/pacer.h).
 *
 *   clang -O2 -arch x86_64 -o trapfreeze trapfreeze.c -lpthread        (x86_64, so it runs under Rosetta)
 *   ./trapfreeze <seconds> <trappers> <writers> <pages> [code bytes] [writes a second per writer] [mode]
 *                [jit traps] [fillers] [filler bytes] [filler instruction in hex]
 *
 * What the game's protection does:
 *   trappers  threads that execute an undefined instruction over and over; a SIGILL handler steps over it.
 *             Each measures how long one trap takes, from the instruction to the instruction after it.
 *             With [jit traps] 1 the instruction sits in memory mapped at run time, as the game's does.
 *   writers   threads that rewrite a small function in one of <pages> pages of writable, executable memory
 *             and call it, so the translator has to throw away what it had for that page and translate again.
 *             Each measures how long one rewrite and call takes.
 *   a clock   thread that sleeps 1 ms at a time and takes no trap, to tell a stop of the translator's users
 *             from a stop of the whole process.
 *   fillers   threads that call large functions never seen before: the countermeasure pacer.h uses.
 * mode: 0 pages taken in turn (default), 1 at random, 2 every call lands on code never seen before (the
 * function moves forward through the page region instead of being rewritten in place).
 * Every second: traps and rewrites done, and the slowest of each. At the end: every trap or rewrite that took
 * 20 ms or more, with its time, so stops shared by several threads can be read off.
 *
 * Measured 2026-11-16, MacBook Pro M4 Max, macOS 27.2:
 *   ./trapfreeze 90 2 3 4096 64 0 1 1      every ~15 s (~800,000 rewrites) both trappers and all three writers
 *                                          stop at the same instant for 325-360 ms; the clock is never late
 *   ... 4096 512 0 1 1                     every ~7 s (~215,000 rewrites), 85-97 ms
 *   ... 64 64 0 1 1                        64 pages instead of 4096: ~200 ms
 *   ./trapfreeze 100 3 1 4096 64 0 1 1     one writer: only the writer stops (~500 ms every ~24 s)
 *   ./trapfreeze 45 2 3 4096 64 0 1 1 1 4096 F30FB8C1
 *                                          one filler of 4096-byte functions of popcnt: the slowest trap in
 *                                          45 s is 6 ms instead of 318, and the writers and trappers do a
 *                                          quarter to a third of the work they did, the filler taking the
 *                                          translator from them
 * So the stop lasts about 0.4 us per translation held since the last one, whatever their size.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE
#include <mach/mach_time.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ucontext.h>
#include <unistd.h>

#define MAX_THREADS 32
#define MAX_EVENTS 4096
struct event { double at, took; };
struct worker
{
    char kind; int index;
    volatile unsigned long long count;
    volatile double worst;                    /* this second */
    struct event events[MAX_EVENTS]; int nevents;
    char pad[64];
};
static struct worker workers[MAX_THREADS];
static int nworkers, mode;
static volatile int stop;
static double t_start;
static size_t pages, code_bytes = 64;
static double write_rate;

static double now(void)
{
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info( &tb );
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
}
static void note( struct worker *w, double t0, double t1 )
{
    double took = t1 - t0;
    w->count++;
    if (took > w->worst) w->worst = took;
    if (took >= 0.020 && w->nevents < MAX_EVENTS) { w->events[w->nevents].at = t0 - t_start; w->events[w->nevents++].took = took; }
}

static void on_sigill( int sig, siginfo_t *info, void *ctx )
{
    ucontext_t *uc = ctx;
    (void)sig; (void)info;
    uc->uc_mcontext->__ss.__rip += 2;        /* ud2 */
}
static int jit_traps;
static void *trapper( void *arg )
{
    struct worker *w = arg;
    /* jit_traps: the undefined instruction sits in memory mapped at run time, like the game's, and not in
     * this program's own code, which Rosetta translated ahead of time */
    unsigned char *page = NULL;
    if (jit_traps)
    {
        page = mmap( NULL, 4096, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0 );
        if (page == MAP_FAILED) { perror( "mmap" ); return NULL; }
        page[0] = 0x0f; page[1] = 0x0b; page[2] = 0xc3;          /* ud2 ; ret */
    }
    while (!stop)
    {
        double t0 = now();
        if (page) ((void (*)(void))page)();
        else __asm__ volatile( "ud2" );
        note( w, t0, now() );
    }
    return NULL;
}

static size_t emit( unsigned char *p, unsigned value )
{   /* mov eax, value ; add eax, 1 ... ; ret : code_bytes long, returns value + the number of adds */
    size_t n = 0, adds = code_bytes > 6 ? (code_bytes - 6) / 5 : 0, i;
    p[n++] = 0xb8; memcpy( p + n, &value, 4 ); n += 4;
    for (i = 0; i < adds; i++) { unsigned one = 1; p[n++] = 0x05; memcpy( p + n, &one, 4 ); n += 4; }
    p[n++] = 0xc3;
    return adds;
}
static void *writer( void *arg )
{
    struct worker *w = arg;
    size_t size = pages * 4096, page = 0, offset = 0;
    unsigned char *region = mmap( NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0 );
    unsigned value = 1, seed = 12345 + w->index;
    double next = now();

    if (region == MAP_FAILED) { perror( "mmap" ); return NULL; }
    while (!stop)
    {
        unsigned char *p;
        size_t adds;
        double t0;

        if (write_rate > 0)
        {
            while (now() < next && !stop) ;          /* spin: a sleep would hide a stop */
            next += 1.0 / write_rate;
        }
        if (mode == 2)
        {
            if (offset + code_bytes > size) offset = 0;
            p = region + offset; offset += code_bytes;
        }
        else
        {
            if (mode == 1) { seed = seed * 1103515245 + 12345; page = (seed >> 8) % pages; }
            else page = (page + 1) % pages;
            p = region + page * 4096;
        }
        t0 = now();
        adds = emit( p, value );
        if (((unsigned (*)(void))p)() != value + adds) { fprintf( stderr, "writer %d: stale code ran\n", w->index ); }
        note( w, t0, now() );
        value += 7;
    }
    return NULL;
}
/* a filler: code that is always new and large, so the translator's store fills with few, big translations.
 * To see whether the stop gets shorter when the store is emptied more often with less in it. */
static size_t filler_bytes = 4096, filler_len;
static unsigned char filler_insn[16];
static void *filler( void *arg )
{
    struct worker *w = arg;
    size_t size = 64 << 20, offset = 0;
    unsigned char *region = mmap( NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0 );
    unsigned value = 3;

    if (region == MAP_FAILED) { perror( "mmap" ); return NULL; }
    while (!stop)
    {
        unsigned char *p = region + offset;
        size_t n = 0, adds = (filler_bytes - 6) / 5, i;
        double t0 = now();

        if (filler_len)
        {   /* a chosen instruction repeated; the 4-byte value in front makes every function new */
            p[n++] = 0xb8; memcpy( p + n, &value, 4 ); n += 4;
            for (i = 0; n + filler_len + 1 <= filler_bytes; i++) { memcpy( p + n, filler_insn, filler_len ); n += filler_len; }
            p[n++] = 0xc3;
            ((unsigned (*)(void))p)();
        }
        else
        {
        p[n++] = 0xb8; memcpy( p + n, &value, 4 ); n += 4;
        for (i = 0; i < adds; i++) { unsigned one = 1; p[n++] = 0x05; memcpy( p + n, &one, 4 ); n += 4; }
        p[n++] = 0xc3;
        if (((unsigned (*)(void))p)() != value + adds) fprintf( stderr, "filler: stale code ran\n" );
        }
        note( w, t0, now() );
        value += 3;
        offset += filler_bytes;
        if (offset + filler_bytes > size) offset = 0;
    }
    return NULL;
}
static void *clock_thread( void *arg )
{
    struct worker *w = arg;
    while (!stop)
    {
        double t0 = now();
        usleep( 1000 );
        note( w, t0 + 0.001, now() );            /* what it overslept by */
    }
    return NULL;
}

int main( int argc, char **argv )
{
    double seconds = argc > 1 ? atof( argv[1] ) : 30;
    int trappers = argc > 2 ? atoi( argv[2] ) : 3, writers = argc > 3 ? atoi( argv[3] ) : 1, fillers = 0, i, e, sec;
    pthread_t th[MAX_THREADS];
    struct sigaction sa;
    unsigned long long last[MAX_THREADS] = {0};

    pages = argc > 4 ? strtoul( argv[4], NULL, 0 ) : 1024;
    if (argc > 5) code_bytes = strtoul( argv[5], NULL, 0 );
    if (argc > 6) write_rate = atof( argv[6] );
    if (argc > 7) mode = atoi( argv[7] );
    if (argc > 8) jit_traps = atoi( argv[8] );
    if (argc > 9) fillers = atoi( argv[9] );
    if (argc > 10) filler_bytes = strtoul( argv[10], NULL, 0 );
    if (argc > 11) for (const char *h = argv[11]; h[0] && h[1] && filler_len < sizeof(filler_insn); h += 2)
    { unsigned b; sscanf( h, "%2x", &b ); filler_insn[filler_len++] = b; }
    if (code_bytes < 6) code_bytes = 6;
    if (code_bytes > 4096) code_bytes = 4096;
    if (trappers + writers + 1 > MAX_THREADS) return 2;

    memset( &sa, 0, sizeof(sa) );
    sa.sa_sigaction = on_sigill; sa.sa_flags = SA_SIGINFO;
    sigaction( SIGILL, &sa, NULL );
    t_start = now();
    for (i = 0; i < trappers; i++) { workers[nworkers].kind = 'T'; workers[nworkers].index = i; pthread_create( &th[nworkers], NULL, trapper, &workers[nworkers] ); nworkers++; }
    for (i = 0; i < writers; i++) { workers[nworkers].kind = 'W'; workers[nworkers].index = i; pthread_create( &th[nworkers], NULL, writer, &workers[nworkers] ); nworkers++; }
    for (i = 0; i < fillers; i++) { workers[nworkers].kind = 'F'; workers[nworkers].index = i; pthread_create( &th[nworkers], NULL, filler, &workers[nworkers] ); nworkers++; }
    workers[nworkers].kind = 'C'; pthread_create( &th[nworkers], NULL, clock_thread, &workers[nworkers] ); nworkers++;

    printf( "%d trappers, %d writers, %zu pages (%zu MB), %zu code bytes, %s, mode %d\n", trappers, writers, pages, pages * 4096 >> 20,
            code_bytes, write_rate > 0 ? "paced" : "as fast as it goes", mode );
    if (jit_traps) printf( "the trap is in memory mapped at run time\n" );
    printf( "  sec    traps/s  slowest trap   rewrites/s  slowest rewrite   clock late by\n" );
    for (sec = 1; sec <= (int)seconds; sec++)
    {
        unsigned long long traps = 0, writes = 0;
        double wt = 0, ww = 0, wc = 0;
        sleep( 1 );
        for (i = 0; i < nworkers; i++)
        {
            unsigned long long c = workers[i].count, d = c - last[i];
            double worst = workers[i].worst;
            last[i] = c; workers[i].worst = 0;
            if (workers[i].kind == 'T') { traps += d; if (worst > wt) wt = worst; }
            else if (workers[i].kind == 'W') { writes += d; if (worst > ww) ww = worst; }
            else if (worst > wc) wc = worst;
        }
        printf( "%5d %10llu %10.2f ms %12llu %12.2f ms %12.2f ms\n", sec, traps, wt * 1e3, writes, ww * 1e3, wc * 1e3 );
        fflush( stdout );
    }
    stop = 1;
    for (i = 0; i < nworkers; i++) pthread_join( th[i], NULL );
    printf( "took 20 ms or more:\n" );
    for (i = 0; i < nworkers; i++)
        for (e = 0; e < workers[i].nevents; e++)
            printf( "  %c%d at %8.3f s for %7.1f ms\n", workers[i].kind, workers[i].index, workers[i].events[e].at, workers[i].events[e].took * 1e3 );
    return 0;
}
