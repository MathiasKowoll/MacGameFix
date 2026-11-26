// Rosetta made to look like the x86 CPU copy protection expects: engine patches 0017, 0019 and
// 0020 as a NotProton plugin, for the games that need them, without 0017's execution
// breakpoints.
//
// Under Rosetta 2 a Denuvo-protected game can spin one core and never open a window (Phantom
// Blade Zero, STAR WARS: Galactic Racer). What it checks, and what this does about it, in the
// game's processes only, from outside ntdll.so:
//
//   - CPUID leaf 7. Rosetta reports EBX 0x128 (BMI1, AVX2, BMI2) and ECX 0. Three of the
//     missing features are really there or emulated here: CLFLUSHOPT (Rosetta runs it), CLWB
//     and RDPID. The Rosetta runtime keeps its CPUID leaves as a table of {eax, ebx, ecx, edx}
//     rows in its own read-only image in every translated process; the leaf-7 row of this
//     process's copy gets the three bits (0017, on by default as 0020 made it).
//   - CLWB (66 0F AE /6, memory operand) raises an invalid opcode. It only asks the CPU to write
//     a cache line back, so stepping over it is all it does (0017).
//   - RDPID raises an invalid opcode, and Rosetta's RDTSCP returns a constant where a CPU gives
//     the processor number; protection that falls back to it walks off a per-processor table.
//     RDPID is run here with the number NtGetCurrentProcessorNumber gives (0017).
//   - An access through a non-canonical address is a general protection fault on x86, which
//     Windows reports as an access violation at -1; Rosetta delivers a page fault with the real
//     address, and the protection's handler then retries forever. The fault is passed on to
//     Wine as the general protection fault it would be (0017).
//   - After self-modifying code Rosetta can skip a CPUID the code just decrypted, and run its
//     second byte, 0xa2, as mov [imm64], al, which faults on the eight bytes after it. That
//     fault, with 0f a2 just before RIP and the address those bytes hold, is the CPUID: it is
//     run here and the thread resumes after it (0019).
//
//   - Rosetta gives a thread no debug registers. A program that arms an execution breakpoint
//     (Dr0-3 with Dr7) through a thread context expects the debug exception when the thread gets
//     there; Denuvo's handler of a deliberate fault arms one on the faulting instruction and
//     continues, and without it the fault repeats for ever (Phantom Blade Zero stays on one core
//     and never opens its window: with CodeWeavers' ntdll.so plus 0017 alone it starts, without
//     the breakpoints it does not). As in 0017: a fault at an armed breakpoint is reported as the
//     debug exception the CPU raises first; a breakpoint on an instruction that does not fault
//     takes the execute permission from its page, and a thread that enters the page is stepped
//     with the trap flag until it reaches the breakpoint (reported) or leaves the page (guarded
//     again); Dr7 reads with bit 10 set while a breakpoint is enabled, as on hardware.
//     Wine keeps each thread's debug registers in its TEB (amd64_thread_data, GdiTebBatch, 0x2f0):
//     they are read there, at the points where they can change (NtContinue, NtContinueEx and
//     NtSetContextThread through ntdll.so's syscall table, and after a suspend, where another
//     thread's context is applied), and the exception is raised through Wine's own SIGTRAP
//     handler, whose frame then gets Dr6 as the hardware leaves it (0017).
//
// The handlers go before Wine's (../mgf-signals.c); each answers only for what it recognises and
// passes everything else on, unchanged but for the general protection fault. A runner that still
// carries 0017 does the same after us and finds nothing left to do: its own table scan sees the
// leaf already changed and leaves it.
//
// It is part of mgf-engine.dylib (../mgf-engine.c), which arms it in Phantom Blade Zero.
// build-engine.sh builds it and runs its check (check.c): a Windows program that reads leaf 7 and
// runs CLWB, RDPID and a non-canonical read, under a runner without 0017, with and without it.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../mgf_hooks.h"

#include <stdint.h>
#include <string.h>

#define TAG "rosetta-cpu"

#if defined(__x86_64__)

#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <sys/mman.h>
#include <sys/sysctl.h>

// The x86 trap numbers Rosetta puts in the exception state, as Wine reads them (TRAP_sig).
#define TRAP_PRIVINFLT 6
#define TRAP_PROTFLT 13
#define TRAP_PAGEFLT 14

#define CLFLUSHOPT_CLWB 0x01800000u  // leaf 7 EBX bits 23 and 24
#define RDPID 0x00400000u            // leaf 7 ECX bit 22

static const struct np_plugin_api *api;
static unsigned (*processor_number)(void);  // NtGetCurrentProcessorNumber, host ABI
static unsigned cpuid7_ebx, cpuid7_ecx;     // the bits this process's leaf 7 got
static unsigned clwbs, rdpids;

// Reads up to `len` bytes at `at` without faulting: what is readable from the start.
static unsigned read_code(uintptr_t at, unsigned char *buf, unsigned len) {
    unsigned done = 0;
    while (done < len) {
        uintptr_t from = at + done;
        unsigned chunk = (unsigned)(0x1000 - (from & 0xfff));
        mach_vm_size_t got = 0;
        if (chunk > len - done) chunk = len - done;
        if (mach_vm_read_overwrite(mach_task_self(), from, chunk, (mach_vm_address_t)(buf + done), &got) != KERN_SUCCESS)
            break;
        done += (unsigned)got;
        if (got < chunk) break;
    }
    return done;
}

// At 1, 10, 100... emulations, so their count shows in NotProton's log: each costs a trap.
static void note(const char *what, unsigned *count) {
    unsigned n = __atomic_add_fetch(count, 1, __ATOMIC_RELAXED), p = 1;
    while (p < n && p <= 100000000) p *= 10;
    if (p == n) api->log(TAG, "emulated %s %u time%s", what, n, n == 1 ? "" : "s");
}

static uint64_t *reg(ucontext_t *uc, unsigned r) {
    _STRUCT_X86_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
    switch (r) {
    case 0: return &ss->__rax;
    case 1: return &ss->__rcx;
    case 2: return &ss->__rdx;
    case 3: return &ss->__rbx;
    case 4: return &ss->__rsp;
    case 5: return &ss->__rbp;
    case 6: return &ss->__rsi;
    case 7: return &ss->__rdi;
    case 8: return &ss->__r8;
    case 9: return &ss->__r9;
    case 10: return &ss->__r10;
    case 11: return &ss->__r11;
    case 12: return &ss->__r12;
    case 13: return &ss->__r13;
    case 14: return &ss->__r14;
    default: return &ss->__r15;
    }
}

// CLWB: 66 [REX] 0F AE /6 with a memory operand; only where leaf 7 says CLWB is there.
static int clwb(ucontext_t *uc, const unsigned char *b, unsigned len) {
    unsigned pos = 1, mod, rm;
    if (!(cpuid7_ebx & (1u << 24)) || len < 4 || b[0] != 0x66) return 0;
    if ((b[pos] & 0xf0) == 0x40) pos++;
    if (len < pos + 3 || b[pos] != 0x0f || b[pos + 1] != 0xae) return 0;
    mod = b[pos + 2] >> 6;
    rm = b[pos + 2] & 7;
    if (mod == 3 || ((b[pos + 2] >> 3) & 7) != 6) return 0;
    pos += 3;
    if (rm == 4) {  // SIB
        if (len < pos + 1) return 0;
        if (mod == 0 && (b[pos] & 7) == 5) pos += 4;  // disp32, no base
        pos++;
    } else if (mod == 0 && rm == 5) pos += 4;  // rip-relative disp32
    if (mod == 1) pos += 1;
    else if (mod == 2) pos += 4;
    if (pos > len) return 0;
    uc->uc_mcontext->__ss.__rip += pos;
    note("CLWB", &clwbs);
    return 1;
}

// RDPID: F3 [REX] 0F C7 /7, register operand; only where leaf 7 says RDPID is there.
static int rdpid(ucontext_t *uc, const unsigned char *b, unsigned len) {
    unsigned pos = 1, r;
    unsigned char rex = 0;
    if (!(cpuid7_ecx & RDPID) || len < 4 || b[0] != 0xf3) return 0;
    if ((b[pos] & 0xf0) == 0x40) rex = b[pos++];
    if (len < pos + 3 || b[pos] != 0x0f || b[pos + 1] != 0xc7 || (b[pos + 2] & 0xf8) != 0xf8) return 0;
    r = (b[pos + 2] & 7) | ((rex & 1) << 3);
    *reg(uc, r) = processor_number();
    uc->uc_mcontext->__ss.__rip += pos + 3;
    note("RDPID", &rdpids);
    return 1;
}

// --- Execution breakpoints (0017's HRAVA_HW_EXEC_BREAKPOINT) ---------------------------------

#define TRAP_TRCTRAP 1
#define EFLAGS_TF 0x100u
#define EFLAGS_RF 0x10000u
#define CONTEXT_AMD64 0x00100000u
#define CONTEXT_CONTROL_FLAGS (CONTEXT_AMD64 | 0x1u)
#define CONTEXT_DEBUG_FLAGS (CONTEXT_AMD64 | 0x10u)
#define CTX_FLAGS 0x30   // CONTEXT, x86-64: ContextFlags
#define CTX_DR6 0x68
#define CTX_DR7 0x70
#define CTX_RIP 0xf8
#define REC_AT 0x4f0     // Wine's exc_stack_layout: the EXCEPTION_RECORD after the CONTEXT
#define SINGLE_STEP 0x80000004u
#define TEB_DR 0x2f0     // amd64_thread_data in GdiTebBatch: dr0 dr1 dr2 dr3 dr6 dr7

struct dr_data {
    uint64_t dr[4], dr6, dr7;
};

struct sw_breakpoint {
    uintptr_t addr, teb;
    int prot;      // the page's protection, with execute permission
    int armed;
    int guarded;   // execute permission removed
};

static struct sw_breakpoint breakpoints[16];
static uintptr_t dr_threads[64];   // TEBs of the threads with an execution breakpoint enabled
static uintptr_t stepping[16];     // TEBs of the threads stepping through a breakpoint page
static int lock;
static unsigned raised, stepped;
static void (*wine_trap)(int, siginfo_t *, void *);  // Wine's SIGTRAP handler, installed after arm
static int breakpoints_on;
static long (*query_memory)(void *, const void *, unsigned, void *, size_t, size_t *);  // NtQueryVirtualMemory
static uintptr_t old_continue, old_continue_ex, old_set_context;

static uintptr_t current_teb(void) {
    uintptr_t teb;
    __asm__ volatile("movq %%gs:0x30, %0" : "=r"(teb));
    return teb;
}

static struct dr_data *dr_of(uintptr_t teb) { return (struct dr_data *)(teb + TEB_DR); }

static int known(uintptr_t *set, unsigned n, uintptr_t teb) {
    for (unsigned i = 0; i < n; i++)
        if (__atomic_load_n(&set[i], __ATOMIC_ACQUIRE) == teb) return 1;
    return 0;
}

static void remember(uintptr_t *set, unsigned n, uintptr_t teb, int in) {
    for (unsigned i = 0; i < n; i++) {
        uintptr_t was = __atomic_load_n(&set[i], __ATOMIC_ACQUIRE);
        if (was == teb) {
            if (!in) __atomic_compare_exchange_n(&set[i], &was, 0, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
            return;
        }
    }
    if (!in) return;
    for (unsigned i = 0; i < n; i++) {
        uintptr_t none = 0;
        if (__atomic_compare_exchange_n(&set[i], &none, teb, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) return;
    }
}

static void guard(struct sw_breakpoint *bp, int on) {
    uintptr_t page = bp->addr & ~(uintptr_t)0xfff;
    int was = !on;
    if (__atomic_compare_exchange_n(&bp->guarded, &was, on, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
        mprotect((void *)page, 0x1000, on ? (bp->prot & ~PROT_EXEC) : bp->prot);
}

// Whether execution breakpoint i of `d` is enabled (L or G bit, RW bits 00).
static int exec_breakpoint(const struct dr_data *d, unsigned i) {
    return (d->dr7 & (3u << (i * 2))) && !((d->dr7 >> (16 + i * 4)) & 0xf) && d->dr[i];
}

// Brings the current thread's guarded pages in line with its debug registers, as 0017's
// sync_sw_breakpoints; a breakpoint on the address the thread resumes at stays out (the resume
// flag). From a signal handler (`in_signal`) it gives up rather than wait for the lock.
static void sync(uintptr_t resume, int in_signal) {
    uintptr_t teb = current_teb(), want[4] = {0};
    struct dr_data *d;
    int any = 0, unlocked = 0;
    if (!teb) return;
    d = dr_of(teb);
    for (unsigned i = 0; i < 4; i++)
        if (exec_breakpoint(d, i)) {
            any = 1;
            if (d->dr[i] != resume) want[i] = d->dr[i];
        }
    if (any) d->dr7 |= 0x400;  // bit 10 reads as set, as on hardware
    remember(dr_threads, 64, teb, any);
    if (in_signal) {
        if (!__atomic_compare_exchange_n(&lock, &unlocked, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) return;
    } else {
        while (!__atomic_compare_exchange_n(&lock, &unlocked, 1, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) unlocked = 0;
    }
    for (unsigned j = 0; j < 16; j++) {
        struct sw_breakpoint *bp = &breakpoints[j];
        unsigned i;
        if (!bp->armed || bp->teb != teb) continue;
        for (i = 0; i < 4; i++)
            if (want[i] == bp->addr) break;
        if (i < 4) { want[i] = 0; continue; }  // still wanted, already in place
        guard(bp, 0);
        __atomic_store_n(&bp->armed, 0, __ATOMIC_RELEASE);
    }
    for (unsigned i = 0; i < 4; i++) {
        unsigned char info[48];  // MEMORY_BASIC_INFORMATION: State at 0x20, Protect at 0x24
        unsigned state, protect;
        if (!want[i] || !query_memory) continue;
        if (query_memory((void *)~(uintptr_t)0, (void *)want[i], 0, info, sizeof(info), NULL)) continue;
        memcpy(&state, info + 0x20, 4);
        memcpy(&protect, info + 0x24, 4);
        if (state != 0x1000) continue;  // MEM_COMMIT
        for (unsigned j = 0; j < 16; j++) {
            struct sw_breakpoint *bp = &breakpoints[j];
            if (bp->armed) continue;
            bp->addr = want[i];
            bp->teb = teb;
            bp->prot = PROT_READ | PROT_EXEC | ((protect & 0xcc) ? PROT_WRITE : 0);  // the RW and WC protections
            bp->guarded = 0;
            __atomic_store_n(&bp->armed, 1, __ATOMIC_RELEASE);
            guard(bp, 1);
            break;
        }
    }
    __atomic_store_n(&lock, 0, __ATOMIC_RELEASE);
}

// Raises the debug exception of breakpoint `addr` (number i of 4, or 4 when it is not one of
// the thread's own) through Wine's SIGTRAP handler, and gives its frame Dr6 and Dr7 as the
// hardware leaves them: Wine reads them back from the server, which never heard of the hit.
static void raise_breakpoint(siginfo_t *info, ucontext_t *uc, uintptr_t teb, uintptr_t addr, unsigned i) {
    struct dr_data *d = dr_of(teb);
    uint64_t dr6 = 0xffff0ff0u | (i < 4 ? 1u << i : 0), dr7 = d->dr7 | 0x400;
    unsigned char *frame;
    uint32_t code;
    uint64_t at, rip;
    d->dr6 = dr6;
    uc->uc_mcontext->__ss.__rflags &= ~EFLAGS_TF;
    uc->uc_mcontext->__es.__trapno = TRAP_TRCTRAP;
    wine_trap(SIGTRAP, info, uc);
    frame = (unsigned char *)uc->uc_mcontext->__ss.__rsp;
    memcpy(&code, frame + REC_AT, 4);
    memcpy(&at, frame + REC_AT + 0x10, 8);
    memcpy(&rip, frame + CTX_RIP, 8);
    if (code == SINGLE_STEP && at == addr && rip == addr) {
        memcpy(frame + CTX_DR6, &dr6, 8);
        memcpy(frame + CTX_DR7, &dr7, 8);
    }
    note("an execution breakpoint", &raised);
}

// A fault (SIGSEGV, SIGBUS, SIGILL) of a thread with a breakpoint enabled, or in a guarded page.
static int breakpoint_fault(siginfo_t *info, ucontext_t *uc) {
    uintptr_t rip = uc->uc_mcontext->__ss.__rip, teb;
    if (!breakpoints_on) return 0;
    if (!wine_trap && !(wine_trap = mgf_signal_wine(SIGTRAP))) return 0;
    teb = current_teb();
    // At an armed breakpoint: the debug exception comes before the instruction's own fault.
    if (known(dr_threads, 64, teb)) {
        struct dr_data *d = dr_of(teb);
        for (unsigned i = 0; i < 4; i++) {
            if (!exec_breakpoint(d, i) || d->dr[i] != rip) continue;
            if (uc->uc_mcontext->__ss.__rflags & EFLAGS_RF) {  // the resume flag: skip it once
                uc->uc_mcontext->__ss.__rflags &= ~EFLAGS_RF;
                return 0;
            }
            for (unsigned j = 0; j < 16; j++)
                if (breakpoints[j].armed && breakpoints[j].addr == rip && breakpoints[j].teb == teb) {
                    guard(&breakpoints[j], 0);
                    __atomic_store_n(&breakpoints[j].armed, 0, __ATOMIC_RELEASE);
                }
            raise_breakpoint(info, uc, teb, rip, i);
            return 1;
        }
    }
    // Entering a guarded page: report the breakpoint, or step the thread through the page.
    for (unsigned j = 0; j < 16; j++) {
        struct sw_breakpoint *bp = &breakpoints[j];
        if (!bp->armed || !bp->guarded || (bp->addr & ~(uintptr_t)0xfff) != (rip & ~(uintptr_t)0xfff)) continue;
        if (bp->addr == rip && bp->teb == teb) {
            guard(bp, 0);
            __atomic_store_n(&bp->armed, 0, __ATOMIC_RELEASE);
            raise_breakpoint(info, uc, teb, rip, 4);
            return 1;
        }
        guard(bp, 0);
        remember(stepping, 16, teb, 1);
        if (known(stepping, 16, teb)) uc->uc_mcontext->__ss.__rflags |= EFLAGS_TF;
        note("a step through a breakpoint page", &stepped);
        return 1;
    }
    return 0;
}

// The trap after each instruction of a thread stepping through a breakpoint page.
static int on_trap(int sig, siginfo_t *info, ucontext_t *uc) {
    uintptr_t rip = uc->uc_mcontext->__ss.__rip, teb = current_teb();
    int inside = 0;
    (void)sig;
    if (!known(stepping, 16, teb)) return 0;
    if (!wine_trap && !(wine_trap = mgf_signal_wine(SIGTRAP))) return 0;
    for (unsigned j = 0; j < 16; j++) {
        struct sw_breakpoint *bp = &breakpoints[j];
        if (!bp->armed) continue;
        if (bp->addr == rip && bp->teb == teb) {
            remember(stepping, 16, teb, 0);
            guard(bp, 0);
            __atomic_store_n(&bp->armed, 0, __ATOMIC_RELEASE);
            raise_breakpoint(info, uc, teb, rip, 4);
            return 1;
        }
        if ((bp->addr & ~(uintptr_t)0xfff) == (rip & ~(uintptr_t)0xfff)) inside = 1;
    }
    if (inside) uc->uc_mcontext->__ss.__rflags |= EFLAGS_TF;
    else {  // left the page: stop stepping, guard the pages again
        remember(stepping, 16, teb, 0);
        uc->uc_mcontext->__ss.__rflags &= ~EFLAGS_TF;
        for (unsigned j = 0; j < 16; j++)
            if (breakpoints[j].armed) guard(&breakpoints[j], 1);
    }
    return 1;
}

// After a suspend: a context another thread set is applied there, inside ntdll.so.
static void after_usr1(int sig, siginfo_t *info, ucontext_t *uc, uintptr_t pc) {
    (void)sig; (void)info; (void)pc;
    sync(uc->uc_mcontext->__ss.__rip, 1);
}

static int sets_debug_registers(const void *context) {
    uint32_t flags;
    memcpy(&flags, (const unsigned char *)context + CTX_FLAGS, 4);
    return (flags & CONTEXT_DEBUG_FLAGS) == CONTEXT_DEBUG_FLAGS;
}

static uintptr_t resume_of(const void *context) {
    uint32_t flags;
    uint64_t rip;
    memcpy(&flags, (const unsigned char *)context + CTX_FLAGS, 4);
    if ((flags & CONTEXT_CONTROL_FLAGS) != CONTEXT_CONTROL_FLAGS) return 0;
    memcpy(&rip, (const unsigned char *)context + CTX_RIP, 8);
    return rip;
}

static long continue_hook(void *context, uintptr_t alertable) {
    long rc = ((long (*)(void *, uintptr_t))old_continue)(context, alertable);
    if (!rc && context && sets_debug_registers(context)) sync(resume_of(context), 0);
    return rc;
}

static long continue_ex_hook(void *context, void *args) {
    long rc = ((long (*)(void *, void *))old_continue_ex)(context, args);
    if (!rc && context && sets_debug_registers(context)) sync(resume_of(context), 0);
    return rc;
}

static long set_context_hook(void *thread, void *context) {
    long rc = ((long (*)(void *, void *))old_set_context)(thread, context);
    if (!rc && thread == (void *)~(uintptr_t)1 && context && sets_debug_registers(context))  // GetCurrentThread()
        sync(resume_of(context), 0);
    return rc;
}

static int hook(const struct mach_header_64 *mh, intptr_t slide, const char *name, uintptr_t *old, void *with) {
    uintptr_t *slot = mgf_syscall_slot(api, mh, slide, name, old);
    return slot && api->swap_pointer(slot, *old, (uintptr_t)with);
}

static void arm_breakpoints(const struct mach_header_64 *mh, intptr_t slide) {
    query_memory = (long (*)(void *, const void *, unsigned, void *, size_t, size_t *))api->symbol(
        mh, slide, "_NtQueryVirtualMemory");
    if (!query_memory || !mgf_signal_first(api, mh, slide, SIGTRAP, on_trap) ||
        !mgf_signal_after(api, mh, slide, SIGUSR1, after_usr1)) {
        api->log(TAG, "execution breakpoints: no place in ntdll.so, not armed");
        return;
    }
    if (!hook(mh, slide, "_NtContinue", &old_continue, (void *)continue_hook) ||
        !hook(mh, slide, "_NtContinueEx", &old_continue_ex, (void *)continue_ex_hook) ||
        !hook(mh, slide, "_NtSetContextThread", &old_set_context, (void *)set_context_hook)) {
        api->log(TAG, "execution breakpoints: a context call not found in the syscall table, not armed");
        return;
    }
    breakpoints_on = 1;
    api->log(TAG, "execution breakpoints (Dr0-3) are emulated");
}

static int on_ill(int sig, siginfo_t *info, ucontext_t *uc) {
    unsigned char b[12];
    unsigned len;
    (void)sig;
    if (breakpoint_fault(info, uc)) return 1;
    if (uc->uc_mcontext->__es.__trapno != TRAP_PRIVINFLT) return 0;
    len = read_code(uc->uc_mcontext->__ss.__rip, b, sizeof(b));
    return rdpid(uc, b, len) || clwb(uc, b, len);
}

// The CPUID Rosetta skipped after self-modifying code (0019).
static int skipped_cpuid(siginfo_t *info, ucontext_t *uc) {
    _STRUCT_X86_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
    unsigned char code[10];
    uint64_t target;
    unsigned eax, ebx, ecx, edx;
    if (read_code(ss->__rip - 1, code, sizeof(code)) != sizeof(code)) return 0;
    if (code[0] != 0x0f || code[1] != 0xa2) return 0;
    memcpy(&target, code + 2, sizeof(target));
    if ((uintptr_t)info->si_addr != target) return 0;
    eax = (unsigned)ss->__rax;
    ecx = (unsigned)ss->__rcx;
    __asm__ volatile("cpuid" : "+a"(eax), "=b"(ebx), "+c"(ecx), "=d"(edx));
    ss->__rax = eax;
    ss->__rbx = ebx;
    ss->__rcx = ecx;
    ss->__rdx = edx;
    ss->__rip += 1;
    api->log(TAG, "ran the CPUID Rosetta skipped after self-modifying code");
    return 1;
}

static int on_fault(int sig, siginfo_t *info, ucontext_t *uc) {
    int64_t high = (int64_t)(uintptr_t)info->si_addr >> 47;
    (void)sig;
    if (breakpoint_fault(info, uc)) return 1;
    if (uc->uc_mcontext->__es.__trapno != TRAP_PAGEFLT) return 0;
    if (skipped_cpuid(info, uc)) return 1;
    // Non-canonical: Wine's handler then reports the general protection fault, an access
    // violation at -1 with no read or write flag, as Windows does.
    if (high != 0 && high != -1) {
        uc->uc_mcontext->__es.__trapno = TRAP_PROTFLT;
        uc->uc_mcontext->__es.__err = 0;
    }
    return 0;
}

// The leaf-7 row of every Rosetta CPUID table in the process (0017's rosetta_extend_cpuid).
static unsigned extend_cpuid(unsigned mask, unsigned mask_ecx) {
    static const unsigned vendor[3] = {0x756e6547, 0x6c65746e, 0x49656e69};  // "Genu" "ntel" "ineI"
    mach_vm_address_t addr = 0;
    mach_vm_size_t size = 0;
    unsigned patched = 0;
    for (;;) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object;
        if (mach_vm_region(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count,
                           &object))
            break;
        // The runtime image: readable and executable, never writable, a few hundred kB.
        if ((info.protection & (VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)) == (VM_PROT_READ | VM_PROT_EXECUTE) &&
            size <= 0x400000) {
            unsigned *p = (unsigned *)addr;
            size_t n = size / sizeof(*p);
            for (size_t i = 4; i + 32 < n; i++) {
                unsigned *row1 = p + i, *ebx7 = row1 + 6 * 4 + 1;
                mach_vm_address_t page;
                // Leaf 0 ends in the vendor string, leaf 1 follows, leaf 7 is six rows on.
                if (row1[-3] != vendor[0] || row1[-2] != vendor[1] || row1[-1] != vendor[2]) continue;
                if ((row1[0] & 0xfff00000) || !(row1[3] & (1 << 25))) continue;  // family/model, SSE
                if (ebx7[-1] || (*ebx7 & ~0x128u) || ebx7[1]) continue;           // eax 0, the known bits only
                page = (mach_vm_address_t)ebx7 & ~(mach_vm_address_t)0x3fff;
                if (mach_vm_protect(mach_task_self(), page, 0x4000, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY))
                    continue;
                *ebx7 |= mask;
                ebx7[1] |= mask_ecx;
                mach_vm_protect(mach_task_self(), page, 0x4000, 0, VM_PROT_READ | VM_PROT_EXECUTE);
                patched++;
            }
        }
        addr += size;
    }
    return patched;
}

static void arm(const struct mach_header_64 *mh, intptr_t slide) {
    int translated = 0;
    size_t size = sizeof(translated);
    unsigned tables;
    if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) || !translated) {
        api->log(TAG, "not under Rosetta, not armed");
        return;
    }
    processor_number = (unsigned (*)(void))api->symbol(mh, slide, "_NtGetCurrentProcessorNumber");
    if (!processor_number) {
        api->log(TAG, "ntdll.so has no NtGetCurrentProcessorNumber, not armed");
        return;
    }
    if (!mgf_signal_first(api, mh, slide, SIGILL, on_ill) || !mgf_signal_first(api, mh, slide, SIGSEGV, on_fault) ||
        !mgf_signal_first(api, mh, slide, SIGBUS, on_fault)) {
        api->log(TAG, "cannot put handlers before Wine's, not armed");
        return;
    }
    arm_breakpoints(mh, slide);
    if ((tables = extend_cpuid(CLFLUSHOPT_CLWB, RDPID))) {
        cpuid7_ebx = CLFLUSHOPT_CLWB;
        cpuid7_ecx = RDPID;
        api->log(TAG, "CPUID leaf 7 shows CLFLUSHOPT, CLWB and RDPID (%u Rosetta table%s); CLWB and RDPID are emulated",
                 tables, tables == 1 ? "" : "s");
    } else {
        api->log(TAG, "no Rosetta CPUID table as expected: leaf 7 stays as it is");
    }
}

#else

static const struct np_plugin_api *api;
static void arm(const struct mach_header_64 *mh, intptr_t slide) { (void)mh; (void)slide; }

#endif

// mgf-engine.dylib (../mgf-engine.c) arms this for the games that need it.
void mgf_rosetta_cpu_arm(const struct np_plugin_api *with, const struct mach_header_64 *mh, intptr_t slide) {
    api = with;
    arm(mh, slide);
}
