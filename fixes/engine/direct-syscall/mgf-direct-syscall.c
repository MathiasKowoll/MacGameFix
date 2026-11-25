// A direct system call, or an exception, that Rosetta delivers on top of a suspend: engine
// patches 0028 and 0029 as a NotProton plugin, for the games that need them.
//
// Copy protection runs the syscall instruction from memory of its own, which Wine on macOS gets
// as SIGSYS. Under Rosetta 2 that SIGSYS does not wait for its turn: when SIGUSR1 reaches the
// thread at the same instruction (another thread suspending it, or the server with a system APC
// for it), SIGUSR1's frame is built first, with the thread just after the instruction and the
// system call not made, and then the SIGSYS either lands on top of that frame, before Wine's
// usr1_handler has run (its context is the signal trampoline's entry, on the signal stack), or
// never comes. Wine enters the system call from the trampoline's context in the first case, so
// usr1_handler never runs and the thread that suspended this one waits for ever; in the second
// the program goes on with the call's number where its result should be. The signal of an
// exception (a fault, an undefined instruction, a breakpoint) can land on top of SIGUSR1's frame
// the same way, and Wine ends the thread ("nested exception on signal stack").
//
// Patches 0028 and 0029 deal with it inside ntdll.so. This does the same from outside it, in the
// game's processes only, with handlers before Wine's (../mgf-signals.c), and without Wine's own
// structures: where 0028 sends the thread into Wine's system call dispatcher from the end of
// usr1_handler, this sends it back onto its syscall instruction, which raises its SIGSYS again,
// now on its own, and Wine's sigsys_handler makes the call as it always does.
//
//   - A SIGSYS on the signal stack (sigaltstack says where it is) came on top of another handler:
//     it is noted, with its system call number, and not passed on.
//   - A SIGSYS whose thread is not just past a syscall instruction came late, after the thread
//     was sent back onto it: it is ignored, as 0028 ignores one, and the instruction raises its own.
//   - Once Wine's SIGUSR1 handler has returned, the thread goes back onto its syscall instruction
//     when a SIGSYS was noted and the context is still where the handler began, with the same
//     number in rax. With none noted, only the thread's state is there to go by, as in 0028:
//     the two bytes before rip are 0f 05, rax could be a system call number, rcx is not rip (a
//     thread out of the dispatcher, or out of a host system call, has its return address there)
//     and r10 equals rcx, as after the mov r10,rcx every system call stub starts with, and the
//     code is not the host's (a Mach-O image or macOS's shared cache: libSystem's stubs start the
//     same way, and 0028 rules them out with is_inside_syscall).
//   - The signal of a fault, an undefined instruction or an arithmetic error that lands at the top
//     of the signal stack, with nothing on it yet, is ignored: the instruction has not run and
//     faults again once the other handler returns to it (0029). A breakpoint's has run, so it is
//     noted and the thread goes back onto its int3 once SIGUSR1's handler is done. A single step
//     delivered that way is ignored and not replayed, as in 0029.
//
// Rosetta only. The state of a thread is kept by its signal stack, one per thread, in a table
// that needs no lock. A runner whose ntdll still carries 0028 and 0029 does the same once more
// and finds nothing left to do; WINE_DIRECT_SYSCALL_DEFERRAL=0 turns its copy off.
//
// It is part of mgf-engine.dylib (../mgf-engine.c), which arms it in Forza Horizon 6.
// build-engine.sh builds it and runs its check, engine/tests/direct-syscall-suspend/suspend.c,
// under a runner without 0028 and 0029, with and without it.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../mgf_hooks.h"

#include <stdint.h>

#define TAG "direct-syscall"

#if defined(__x86_64__)

#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

#define TRAP_BPTFLT 3
#define THREADS 1024

static const struct np_plugin_api *api;

// What a thread has pending, found by its signal stack: 1 a SIGSYS noted (with its number), 2 a
// breakpoint.
static struct thread {
    uintptr_t stack;
    int pending;
    uint16_t id;
} threads[THREADS];
static unsigned entered, lost, late;

static struct thread *mine(uintptr_t stack) {
    unsigned i = (unsigned)(stack >> 12) % THREADS;
    for (unsigned n = 0; n < THREADS; n++, i = (i + 1) % THREADS) {
        uintptr_t have = __atomic_load_n(&threads[i].stack, __ATOMIC_ACQUIRE), none = 0;
        if (have == stack) return &threads[i];
        if (!have && __atomic_compare_exchange_n(&threads[i].stack, &none, stack, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
            return &threads[i];
        if (none == stack) return &threads[i];
    }
    return NULL;
}

// The thread's signal stack, as Wine set it up.
static int signal_stack(uintptr_t *lo, uintptr_t *hi) {
    stack_t ss;
    if (sigaltstack(NULL, &ss) || (ss.ss_flags & SS_DISABLE) || !ss.ss_sp) return 0;
    *lo = (uintptr_t)ss.ss_sp;
    *hi = *lo + ss.ss_size;
    return 1;
}

static int read_code(uintptr_t at, unsigned char *buf, unsigned len) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(mach_task_self(), at, len, (mach_vm_address_t)buf, &got) == KERN_SUCCESS && got == len;
}

// Whether code at `at` is the host's: a Mach-O image or macOS's shared cache, where a syscall
// instruction is a host system call (Wine's own, from inside a Windows one: 0028 asks
// is_inside_syscall). A Windows module is a .dll or .exe; a copy protection's stub is in memory
// that maps no file.
static int host_code(uintptr_t at) {
    char path[1024];
    size_t n;
    if (proc_regionfilename(getpid(), at, path, sizeof(path)) <= 0) return 0;
    path[sizeof(path) - 1] = 0;
    n = strlen(path);
    if (n >= 4 && (!strcasecmp(path + n - 4, ".dll") || !strcasecmp(path + n - 4, ".exe"))) return 0;
    return 1;
}

// At 1, 10, 100... times, so the count shows in NotProton's log.
static void note(const char *what, unsigned *count) {
    unsigned n = __atomic_add_fetch(count, 1, __ATOMIC_RELAXED), p = 1;
    while (p < n && p <= 100000000) p *= 10;
    if (p == n) api->log(TAG, "%s %u time%s", what, n, n == 1 ? "" : "s");
}

static int on_sys(int sig, siginfo_t *info, ucontext_t *uc) {
    _STRUCT_X86_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
    uintptr_t lo, hi, sp = ss->__rsp;
    unsigned char insn[2];
    struct thread *t;
    (void)sig; (void)info;
    if (signal_stack(&lo, &hi) && sp >= lo && sp < hi && (t = mine(lo))) {
        t->id = (uint16_t)ss->__rax;
        t->pending = 1;
        return 1;  // the SIGUSR1 handler under it sends the thread back onto its syscall
    }
    // A SIGSYS that came late, after the thread was sent back onto its syscall instruction: the
    // thread is not just past one. It runs the instruction again and gets a SIGSYS of its own.
    if (ss->__rcx == ss->__rip || !read_code(ss->__rip - 2, insn, 2) || insn[0] != 0x0f || insn[1] != 0x05) {
        note("late SIGSYS with no system call to make, ignored:", &late);
        return 1;
    }
    return 0;
}

// A signal at the top of the signal stack, with nothing on it yet: it came on top of another handler.
static struct thread *ahead(ucontext_t *uc) {
    uintptr_t lo, hi, sp = uc->uc_mcontext->__ss.__rsp;
    if (!signal_stack(&lo, &hi) || sp >= hi || sp < hi - 0x80) return NULL;
    return mine(lo);
}

static int on_fault(int sig, siginfo_t *info, ucontext_t *uc) {
    (void)sig; (void)info;
    return ahead(uc) != NULL;  // the instruction has not run: it faults again
}

static int on_trap(int sig, siginfo_t *info, ucontext_t *uc) {
    struct thread *t = ahead(uc);
    (void)sig; (void)info;
    if (!t) return 0;
    if (uc->uc_mcontext->__es.__trapno == TRAP_BPTFLT) t->pending = 2;  // the int3 has run
    return 1;
}

static void after_usr1(int sig, siginfo_t *info, ucontext_t *uc, uintptr_t pc) {
    _STRUCT_X86_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
    uintptr_t lo, hi;
    unsigned char insn[2];
    struct thread *t;
    int noted;
    (void)sig; (void)info;
    if (!signal_stack(&lo, &hi) || !(t = mine(lo))) return;
    noted = t->pending;
    t->pending = 0;
    if (noted == 2) {
        if (ss->__rip == pc && read_code(pc - 1, insn, 1) && insn[0] == 0xcc) ss->__rip = pc - 1;
        return;
    }
    if (ss->__rip == pc &&
        (noted ? (uint16_t)ss->__rax == t->id
               : (ss->__rcx != pc && ss->__rcx == ss->__r10 && ss->__rax < 0x3000 && !host_code(pc))) &&
        !(ss->__rsp >= lo && ss->__rsp < hi) && read_code(pc - 2, insn, 2) && insn[0] == 0x0f && insn[1] == 0x05) {
        ss->__rip = pc - 2;
        note(noted ? "system call sent again, its SIGSYS came on top of a suspend:"
                   : "system call sent again, its SIGSYS never came:",
             &entered);
    } else if (noted) {
        note("system call not made (SIGSYS on top of a handler, the thread moved):", &lost);
    }
}

static void arm(const struct mach_header_64 *mh, intptr_t slide) {
    int translated = 0;
    size_t size = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) || !translated) {
        api->log(TAG, "not under Rosetta, not armed");
        return;
    }
    if (!mgf_signal_first(api, mh, slide, SIGSYS, on_sys) || !mgf_signal_after(api, mh, slide, SIGUSR1, after_usr1) ||
        !mgf_signal_first(api, mh, slide, SIGSEGV, on_fault) || !mgf_signal_first(api, mh, slide, SIGBUS, on_fault) ||
        !mgf_signal_first(api, mh, slide, SIGILL, on_fault) || !mgf_signal_first(api, mh, slide, SIGFPE, on_fault) ||
        !mgf_signal_first(api, mh, slide, SIGTRAP, on_trap)) {
        api->log(TAG, "cannot put handlers before Wine's, not armed");
        return;
    }
    api->log(TAG, "a direct system call or an exception Rosetta delivers on top of a suspend is replayed after it");
}

#else

static const struct np_plugin_api *api;
static void arm(const struct mach_header_64 *mh, intptr_t slide) { (void)mh; (void)slide; }

#endif

// mgf-engine.dylib (../mgf-engine.c) arms this for the games that need it.
void mgf_direct_syscall_arm(const struct np_plugin_api *with, const struct mach_header_64 *mh, intptr_t slide) {
    api = with;
    arm(mh, slide);
}
