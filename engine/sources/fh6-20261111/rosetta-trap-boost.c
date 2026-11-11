/* rosetta-trap-boost: raises Rosetta's exception server thread in a translated process.
 *
 * Every hardware exception taken by translated x86_64 code (ud2, int3, invalid opcodes, writes into
 * translated code pages) is serviced by one thread per process, com.apple.rosetta.exceptionserver,
 * which runs at default priority. When the game keeps the cores busy that thread waits for a core on
 * every exception: on an M4 Max with 14 busy threads a ud2 round trip measured 42-88 us instead of the
 * 18.6 us floor (scratchpad qosbench, 2026-11-10). This raises that thread to the QoS wineserver gives
 * THREAD_PRIORITY_HIGHEST and keeps it there. It changes no Wine thread and no game code.
 *
 * MGF_RBOOST=log  only writes the thread census, no boost (for an A/B).
 * ~/Library/Logs/MacGameFix/rosetta-trap-boost.mode, read every second, switches it while the game
 * runs: "off" puts the thread back to its default policy, "on" raises it again.
 * The census goes to ~/Library/Logs/MacGameFix/rosetta-trap-boost-<pid>.log every 5 s: each thread
 * that used more than 20 ms of CPU in the interval, with its name and current priority. */
#include <mach/mach.h>
#include <mach/thread_policy.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>

#include "faultcount.h"
#define SERVER_NAME "com.apple.rosetta.exceptionserver"

static int translated(void) {
    int v = 0; size_t s = sizeof v;
    return sysctlbyname("sysctl.proc_translated", &v, &s, NULL, 0) == 0 && v == 1;
}

static kern_return_t raise_thread(thread_t th, int up) {
    integer_t lq = up ? LATENCY_QOS_TIER_0 : LATENCY_QOS_TIER_UNSPECIFIED;
    integer_t tq = up ? THROUGHPUT_QOS_TIER_0 : THROUGHPUT_QOS_TIER_UNSPECIFIED;
    struct thread_extended_policy ext = { 1 };
    struct thread_precedence_policy prec = { up ? 5 : 0 };
    kern_return_t kr = thread_policy_set(th, THREAD_LATENCY_QOS_POLICY, (thread_policy_t)&lq, THREAD_LATENCY_QOS_POLICY_COUNT);
    thread_policy_set(th, THREAD_THROUGHPUT_QOS_POLICY, (thread_policy_t)&tq, THREAD_THROUGHPUT_QOS_POLICY_COUNT);
    thread_policy_set(th, THREAD_EXTENDED_POLICY, (thread_policy_t)&ext, THREAD_EXTENDED_POLICY_COUNT);
    thread_policy_set(th, THREAD_PRECEDENCE_POLICY, (thread_policy_t)&prec, THREAD_PRECEDENCE_POLICY_COUNT);
    return kr;
}

static int faults_file_on(void) {
    char p[1024]; const char *h = getenv("HOME"); struct stat st;
    if (!h) return 0;
    snprintf(p, sizeof p, "%s/Library/Logs/MacGameFix/rosetta-trap-boost.faults", h);
    return stat(p, &st) == 0;
}
struct seen { uint64_t id; uint64_t cpu_ns; uint64_t sys_ns; };

static void *worker(void *arg) {
    (void)arg;
    pthread_setname_np("mgf.rosetta-trap-boost");
    const char *mode = getenv("MGF_RBOOST");
    int boost = !(mode && !strcmp(mode, "log"));
    char path[1024]; FILE *log = NULL;
    const char *home = getenv("HOME");
    if (home) {
        snprintf(path, sizeof path, "%s/Library/Logs/MacGameFix", home); mkdir(path, 0755);
        snprintf(path, sizeof path, "%s/Library/Logs/MacGameFix/rosetta-trap-boost-%d.log", home, getpid());
    }
    static struct seen prev[4096]; int nprev = 0;
    int boosted = 0, applied = -1, trapmode = 0;
    static uint64_t raised_id[64]; int nraised = 0;
    static uint64_t prev_ill[ST];
    char modepath[1024] = "";
    if (home) snprintf(modepath, sizeof modepath, "%s/Library/Logs/MacGameFix/rosetta-trap-boost.mode", home);
    for (unsigned tick = 0;; tick++) {
        sleep(1);
        if (*modepath) {
            FILE *m = fopen(modepath, "r"); char b[8] = "";
            if (m) { if (fgets(b, sizeof b, m)) { boost = strncmp(b, "off", 3) != 0; trapmode = strncmp(b, "trap", 4) == 0; } fclose(m); }
        }
        thread_act_array_t th; mach_msg_type_number_t n;
        if (task_threads(mach_task_self(), &th, &n) != KERN_SUCCESS) continue;
        int census = tick % 5 == 4;
        uint64_t hot[16]; int nhot = 0;
        for (int k = 0; k < ST; k++) { uint64_t v = atomic_load(&st_n[k]); if (v - prev_ill[k] > 200 && nhot < 16) hot[nhot++] = atomic_load(&st_id[k]); prev_ill[k] = v; }
        static struct seen cur[4096]; int ncur = 0;
        if (census && !log && home && n > (getenv("MGF_RBOOST_MINTHREADS") ? atoi(getenv("MGF_RBOOST_MINTHREADS")) : 30)) {   /* only processes with a game's thread count */
            log = fopen(path, "a");
            if (log) fprintf(log, "# pid %d mode %s\n", getpid(), boost ? "boost" : "log");
        }
        if (census && log) {
            static task_events_info_data_t pe; static int have;
            task_events_info_data_t e; mach_msg_type_number_t ec = TASK_EVENTS_INFO_COUNT;
            time_t t = time(NULL);
            fprintf(log, "@ %.8s threads %u boost %s raised %d", ctime(&t) + 11, n, boost ? "on" : "off", boosted);
            if (task_info(mach_task_self(), TASK_EVENTS_INFO, (task_info_t)&e, &ec) == KERN_SUCCESS) {
                if (have) fprintf(log, " | per s: faults %d cow %d msg_sent %d msg_rcvd %d mach_sc %d unix_sc %d csw %d",
                    (e.faults - pe.faults) / 5, (e.cow_faults - pe.cow_faults) / 5, (e.messages_sent - pe.messages_sent) / 5,
                    (e.messages_received - pe.messages_received) / 5, (e.syscalls_mach - pe.syscalls_mach) / 5,
                    (e.syscalls_unix - pe.syscalls_unix) / 5, (e.csw - pe.csw) / 5);
                pe = e; have = 1;
            }
            fprintf(log, "\n");
            if (getenv("MGF_RBOOST_FAULTS") || faults_file_on()) {
                static uint64_t pc[C_N], pw[NSIGW]; int wr = tick > 20 ? wrap_handlers() : 0;
                fprintf(log, "  signals/s:");
                for (int k = 0; k < NSIGW; k++) { uint64_t v = atomic_load(&w_count[k]); fprintf(log, " %s %llu%s", w_name[k], (v - pw[k]) / 5, w_orig[k] ? "" : "(unwrapped)"); pw[k] = v; }
                if (wr) fprintf(log, " [wrapped %d]", wr);
                fprintf(log, " | trap threads:");
                {   static uint64_t pst[ST]; uint64_t d[ST];
                    for (int k = 0; k < ST; k++) { uint64_t v = atomic_load(&st_n[k]); d[k] = v - pst[k]; pst[k] = v; }
                    for (int r = 0; r < 4; r++) { int b = -1; uint64_t bn = 0; for (int k = 0; k < ST; k++) if (d[k] > bn) { bn = d[k]; b = k; }
                        if (b < 0 || bn < 25) break; fprintf(log, " %llx:%llu", atomic_load(&st_id[b]), bn / 5); d[b] = 0; } }
                fprintf(log, " raised %d", nraised);
                fprintf(log, "\n  calls/s:");
                for (int k = 0; k < C_N; k++) { uint64_t v = atomic_load(&c_count[k]); if (v - pc[k] >= 5) fprintf(log, " %s %llu", c_name[k], (v - pc[k]) / 5); pc[k] = v; }
                fprintf(log, "\n");
                {   static uint64_t pr[NREQ]; uint64_t d[NREQ], tot = 0;
                    for (int k = 0; k < NREQ; k++) { uint64_t v = atomic_load(&req_n[k]); d[k] = v - pr[k]; pr[k] = v; tot += d[k]; }
                    fprintf(log, "  server requests/s %llu (writev %llu/s):", tot / 5, atomic_exchange(&c_writev, 0) / 5);
                    for (int r = 0; r < 10; r++) { int b = -1; uint64_t bn = 0; for (int k = 0; k < NREQ; k++) if (d[k] > bn) { bn = d[k]; b = k; }
                        if (b < 0 || bn < 25) break; fprintf(log, " req%d %llu", b, bn / 5); d[b] = 0; }
                    fprintf(log, "\n  request threads/s:");
                    for (int r = 0; r < 6; r++) { int b = -1; uint64_t bn = 0; for (int k = 0; k < RT; k++) { uint64_t v = atomic_load(&rt_n[k]); if (v > bn) { bn = v; b = k; } }
                        if (b < 0 || bn < 25) break; fprintf(log, " %llx:%llu", atomic_load(&rt_id[b]), bn / 5); atomic_store(&rt_n[b], 0); }
                    for (int k = 0; k < RT; k++) atomic_store(&rt_n[k], 0);
                    fprintf(log, "\n");
                }
                /* top fault pages this interval */
                for (int r = 0; r < 6; r++) {
                    int best = -1; uint64_t bn = 0;
                    for (int k = 0; k < PG; k++) { uint64_t v = atomic_load(&pg_n[k]); if (v > bn) { bn = v; best = k; } }
                    if (best < 0 || bn < 25) break;
                    uint64_t page = atomic_load(&pg_addr[best]) << 12;
                    mach_vm_address_t ra = page; mach_vm_size_t rs = 0; vm_region_basic_info_data_64_t ri; mach_msg_type_number_t ric = VM_REGION_BASIC_INFO_COUNT_64; mach_port_t on;
                    int ok = mach_vm_region(mach_task_self(), &ra, &rs, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&ri, &ric, &on) == KERN_SUCCESS;
                    Dl_info di; const char *img = dladdr((void *)page, &di) && di.dli_fname ? di.dli_fname : "-";
                    fprintf(log, "  fault page %#llx x%llu/s  region %#llx+%#llx prot %d/%d  %s\n", page, bn / 5,
                            ok ? (unsigned long long)ra : 0ull, ok ? (unsigned long long)rs : 0ull, ok ? ri.protection : -1, ok ? ri.max_protection : -1, img);
                    atomic_store(&pg_n[best], 0);
                }
                for (int k = 0; k < PG; k++) { atomic_store(&pg_n[k], 0); }
            }
        }
        for (unsigned i = 0; i < n; i++) {
            thread_extended_info_data_t x; mach_msg_type_number_t c = THREAD_EXTENDED_INFO_COUNT;
            thread_identifier_info_data_t id; mach_msg_type_number_t ic = THREAD_IDENTIFIER_INFO_COUNT;
            if (thread_info(th[i], THREAD_EXTENDED_INFO, (thread_info_t)&x, &c) == KERN_SUCCESS &&
                thread_info(th[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&id, &ic) == KERN_SUCCESS) {
                if (!strcmp(x.pth_name, SERVER_NAME) && (applied != boost || (boost && x.pth_curpri < 40))) {
                    if (raise_thread(th[i], boost) == KERN_SUCCESS) { boosted += boost; applied = boost;
                        if (log) { time_t t = time(NULL); fprintf(log, "! %.8s server %s (pri was %d)\n", ctime(&t) + 11, boost ? "raised" : "default", x.pth_curpri); fflush(log); } }
                }
                {   int is_hot = 0, was_raised = -1;
                    for (int k = 0; k < nhot; k++) if (hot[k] == id.thread_id) is_hot = 1;
                    for (int k = 0; k < nraised; k++) if (raised_id[k] == id.thread_id) was_raised = k;
                    if (trapmode && is_hot && was_raised < 0 && nraised < 64 && strcmp(x.pth_name, SERVER_NAME)) {
                        if (raise_thread(th[i], 1) == KERN_SUCCESS) { raised_id[nraised++] = id.thread_id;
                            if (log) { time_t t = time(NULL); fprintf(log, "! %.8s trapping thread %llx raised (pri was %d)\n", ctime(&t) + 11, id.thread_id, x.pth_curpri); fflush(log); } }
                    } else if (!trapmode && was_raised >= 0) {
                        integer_t lq = LATENCY_QOS_TIER_1, tq = THROUGHPUT_QOS_TIER_1; struct thread_precedence_policy pr = { 0 };
                        thread_policy_set(th[i], THREAD_LATENCY_QOS_POLICY, (thread_policy_t)&lq, THREAD_LATENCY_QOS_POLICY_COUNT);
                        thread_policy_set(th[i], THREAD_THROUGHPUT_QOS_POLICY, (thread_policy_t)&tq, THREAD_THROUGHPUT_QOS_POLICY_COUNT);
                        thread_policy_set(th[i], THREAD_PRECEDENCE_POLICY, (thread_policy_t)&pr, THREAD_PRECEDENCE_POLICY_COUNT);
                        raised_id[was_raised] = raised_id[--nraised];
                        if (log) { time_t t = time(NULL); fprintf(log, "! %.8s trapping thread %llx back to normal\n", ctime(&t) + 11, id.thread_id); fflush(log); }
                    }
                }
                if (census && ncur < 4096) {
                    uint64_t cpu = x.pth_user_time + x.pth_system_time, was = 0, swas = 0;
                    for (int k = 0; k < nprev; k++) if (prev[k].id == id.thread_id) { was = prev[k].cpu_ns; swas = prev[k].sys_ns; break; }
                    cur[ncur].id = id.thread_id; cur[ncur].cpu_ns = cpu; cur[ncur].sys_ns = x.pth_system_time; ncur++;
                    if (log && was && cpu - was > 20000000ull)
                        fprintf(log, "  tid %llx pri %d/%d cpu %4llu ms sys %4llu ms  %s\n", id.thread_id, x.pth_curpri,
                                x.pth_priority, (cpu - was) / 1000000ull, (x.pth_system_time - swas) / 1000000ull, x.pth_name);
                }
            }
            mach_port_deallocate(mach_task_self(), th[i]);
        }
        vm_deallocate(mach_task_self(), (vm_address_t)th, n * sizeof(thread_t));
        if (census) { memcpy(prev, cur, ncur * sizeof *cur); nprev = ncur; if (log) fflush(log); }
    }
    return NULL;
}

__attribute__((constructor)) static void start(void) {
    if (!translated()) return;
    pthread_attr_t a; pthread_attr_init(&a);
    pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
    pthread_t t; pthread_create(&t, &a, worker, NULL);
    pthread_attr_destroy(&a);
}
