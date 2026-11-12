#ifndef MGF_RBOOST_TELEMETRY
#define MGF_RBOOST_TELEMETRY 0
#endif
/* faultcount.h (diagnostic): counts the signals Wine's own handlers take, and the blocking or
 * yielding calls the process makes, so the census can show work the game never sees as an exception. */
#include <signal.h>
#include <stdatomic.h>
#include <sys/event.h>
#include <sys/select.h>
#include <poll.h>
#include <sched.h>
#include <dlfcn.h>
#include <mach/mach_vm.h>
#include <sys/ucontext.h>

enum { C_YIELD, C_NANOSLEEP, C_USLEEP, C_SELECT, C_POLL, C_KEVENT, C_KEVENT64, C_READ, C_WRITE, C_MACHMSG, C_SWTCHPRI, C_THSWITCH, C_N };
static const char *c_name[C_N] = { "sched_yield", "nanosleep", "usleep", "select", "poll", "kevent", "kevent64", "read", "write", "mach_msg", "swtch_pri", "thread_switch" };
static _Atomic uint64_t c_count[C_N];

static int my_sched_yield(void) { atomic_fetch_add_explicit(&c_count[C_YIELD], 1, memory_order_relaxed); return sched_yield(); }
static int my_nanosleep(const struct timespec *a, struct timespec *b) { atomic_fetch_add_explicit(&c_count[C_NANOSLEEP], 1, memory_order_relaxed); return nanosleep(a, b); }
static int my_usleep(useconds_t u) { atomic_fetch_add_explicit(&c_count[C_USLEEP], 1, memory_order_relaxed); return usleep(u); }
static int my_select(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *t) { atomic_fetch_add_explicit(&c_count[C_SELECT], 1, memory_order_relaxed); return select(n, r, w, e, t); }
static int my_poll(struct pollfd *f, nfds_t n, int t) { atomic_fetch_add_explicit(&c_count[C_POLL], 1, memory_order_relaxed); return poll(f, n, t); }
static int my_kevent(int kq, const struct kevent *c, int nc, struct kevent *e, int ne, const struct timespec *t) { atomic_fetch_add_explicit(&c_count[C_KEVENT], 1, memory_order_relaxed); return kevent(kq, c, nc, e, ne, t); }
static int my_kevent64(int kq, const struct kevent64_s *c, int nc, struct kevent64_s *e, int ne, unsigned f, const struct timespec *t) { atomic_fetch_add_explicit(&c_count[C_KEVENT64], 1, memory_order_relaxed); return kevent64(kq, c, nc, e, ne, f, t); }
static ssize_t my_read(int fd, void *b, size_t n) { atomic_fetch_add_explicit(&c_count[C_READ], 1, memory_order_relaxed); return read(fd, b, n); }
/* wineserver requests: a 64-byte request header written to the request pipe; the first int is the request code */
#include <sys/uio.h>
#define NREQ 512
static _Atomic uint64_t req_n[NREQ];
#define RT 256
static _Atomic uint64_t rt_id[RT], rt_n[RT];
static void note_req(const void *b, size_t n) {
    if (n != 64 || !b) return;
    int code = *(const int *)b;
    if (code < 0 || code >= NREQ) return;
    atomic_fetch_add_explicit(&req_n[code], 1, memory_order_relaxed);
    uint64_t t = 0; pthread_threadid_np(NULL, &t);
    unsigned h = (unsigned)(t * 0x9E3779B97F4A7C15ull >> 56) & (RT - 1);
    for (int i = 0; i < 16; i++, h = (h + 1) & (RT - 1)) {
        uint64_t k = atomic_load_explicit(&rt_id[h], memory_order_relaxed);
        if (k == t || (!k && atomic_compare_exchange_strong(&rt_id[h], &k, t)) || k == t) { atomic_fetch_add_explicit(&rt_n[h], 1, memory_order_relaxed); return; }
    }
}
static ssize_t my_write(int fd, const void *b, size_t n) { atomic_fetch_add_explicit(&c_count[C_WRITE], 1, memory_order_relaxed); note_req(b, n); return write(fd, b, n); }
static _Atomic uint64_t c_writev;
static ssize_t my_writev(int fd, const struct iovec *v, int c) { atomic_fetch_add_explicit(&c_writev, 1, memory_order_relaxed); if (c > 0) note_req(v[0].iov_base, v[0].iov_len); return writev(fd, v, c); }
static mach_msg_return_t my_mach_msg(mach_msg_header_t *m, mach_msg_option_t o, mach_msg_size_t s, mach_msg_size_t r, mach_port_name_t p, mach_msg_timeout_t t, mach_port_name_t n) { atomic_fetch_add_explicit(&c_count[C_MACHMSG], 1, memory_order_relaxed); return mach_msg(m, o, s, r, p, t, n); }

static boolean_t my_swtch_pri(int p) { atomic_fetch_add_explicit(&c_count[C_SWTCHPRI], 1, memory_order_relaxed); return swtch_pri(p); }
static kern_return_t my_thread_switch(mach_port_name_t t, int o, mach_msg_timeout_t m) { atomic_fetch_add_explicit(&c_count[C_THSWITCH], 1, memory_order_relaxed); return thread_switch(t, o, m); }

#define INTERPOSE(r, o) __attribute__((used)) static const struct { const void *rep; const void *orig; } _ip_##o __attribute__((section("__DATA,__interpose"))) = { (const void *)r, (const void *)o };
#if MGF_RBOOST_TELEMETRY && !defined(MGF_RBOOST_TEST)
INTERPOSE(my_sched_yield, sched_yield) INTERPOSE(my_nanosleep, nanosleep) INTERPOSE(my_usleep, usleep)
INTERPOSE(my_select, select) INTERPOSE(my_poll, poll) INTERPOSE(my_kevent, kevent) INTERPOSE(my_kevent64, kevent64)
INTERPOSE(my_read, read) INTERPOSE(my_write, write) INTERPOSE(my_writev, writev) INTERPOSE(my_mach_msg, mach_msg)
INTERPOSE(my_swtch_pri, swtch_pri) INTERPOSE(my_thread_switch, thread_switch)
#endif

/* signal wrappers: count, remember the faulting page, then run Wine's handler unchanged */
#define NSIGW 4
static const int w_sig[NSIGW] = { SIGSEGV, SIGBUS, SIGILL, SIGTRAP };
static const char *w_name[NSIGW] = { "SIGSEGV", "SIGBUS", "SIGILL", "SIGTRAP" };
static void (*w_orig[NSIGW])(int, siginfo_t *, void *);
static _Atomic uint64_t w_count[NSIGW];
#define PG 512
static _Atomic uint64_t pg_addr[PG], pg_n[PG];
static void note_page(uint64_t a) {
    uint64_t p = a >> 12; unsigned h = (unsigned)(p * 0x9E3779B97F4A7C15ull >> 55) & (PG - 1);
    for (int i = 0; i < 8; i++, h = (h + 1) & (PG - 1)) {
        uint64_t k = atomic_load_explicit(&pg_addr[h], memory_order_relaxed);
        if (k == p || (!k && atomic_compare_exchange_strong(&pg_addr[h], &k, p)) || k == p) { atomic_fetch_add_explicit(&pg_n[h], 1, memory_order_relaxed); return; }
    }
}
#define ST 256
static _Atomic uint64_t st_id[ST], st_n[ST];
static void note_ill_thread(void) {
    uint64_t t = 0; pthread_threadid_np(NULL, &t);
    unsigned h = (unsigned)(t * 0x9E3779B97F4A7C15ull >> 56) & (ST - 1);
    for (int i = 0; i < 16; i++, h = (h + 1) & (ST - 1)) {
        uint64_t k = atomic_load_explicit(&st_id[h], memory_order_relaxed);
        if (k == t || (!k && atomic_compare_exchange_strong(&st_id[h], &k, t)) || k == t) { atomic_fetch_add_explicit(&st_n[h], 1, memory_order_relaxed); return; }
    }
}
#define W(i) static void w_##i(int s, siginfo_t *si, void *uc) { if (MGF_RBOOST_TELEMETRY) atomic_fetch_add_explicit(&w_count[i], 1, memory_order_relaxed); \
    if (MGF_RBOOST_TELEMETRY && i < 2 && si) note_page((uint64_t)si->si_addr); if (i == 2) note_ill_thread(); w_orig[i](s, si, uc); }
W(0) W(1) W(2) W(3)
static void (*w_fn[NSIGW])(int, siginfo_t *, void *) = { w_0, w_1, w_2, w_3 };

/* wrap whatever SA_SIGINFO handler is installed now; returns how many were (re)wrapped */
static int wrap_handlers(void) {
    int done = 0;
    for (int i = 0; i < NSIGW; i++) {
        struct sigaction cur;
        if (sigaction(w_sig[i], NULL, &cur) || !(cur.sa_flags & SA_SIGINFO)) continue;
        if (cur.sa_sigaction == w_fn[i] || !cur.sa_sigaction) continue;
        w_orig[i] = cur.sa_sigaction;
        struct sigaction nw = cur; nw.sa_sigaction = w_fn[i];
        if (!sigaction(w_sig[i], &nw, NULL)) done++;
    }
    return done;
}
