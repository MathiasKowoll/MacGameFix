/* The check for the rosetta-cpu fix: a Windows program, run under a NotProton runner on Rosetta.
 *
 * It reads CPUID leaf 7, then runs what a game whose copy protection checks the leaf runs when
 * it says yes: CLWB on a variable, RDPID, and a read through a non-canonical address, which it
 * expects to raise an access violation at -1. On a runner without patch 0017 the leaf has none
 * of the three bits. With the fix, or 0017, it has them, CLWB and RDPID run, RDPID gives the
 * processor GetCurrentProcessorNumber gives, and the read faults as on Windows.
 *
 * Then the execution breakpoints Rosetta lacks (Dr0-3, Dr7). As Denuvo's handler does, the
 * handler of a deliberate fault (ud2) arms a breakpoint on the faulting instruction and continues:
 * the debug exception has to come there before the fault does again, with Dr6 naming
 * breakpoint 0. And a breakpoint SetThreadContext arms on a function that does not fault has to
 * stop the thread when it calls it. Without them the ud2 faults again and the call runs through.
 *
 * Exits 0 when all of it held, 2 when the leaf lacks the bits (the bug), 1 otherwise.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <windows.h>
#include <cpuid.h>
#include <stdio.h>

static volatile LONG faults;
static ULONG_PTR fault_info[2];

void *ud2_at;  /* the deliberate fault below; global, so the asm can store its address */
static volatile LONG ud2s, steps;
static ULONG_PTR step_at, step_dr6;

/* The ud2 at ud2_at: arm a breakpoint on it the first time, give up the second. The debug
 * exception: note it, disarm, and go past the ud2 when it is the one stopped at. */
static LONG CALLBACK on_breakpoint(EXCEPTION_POINTERS *e)
{
    CONTEXT *c = e->ContextRecord;
    DWORD code = e->ExceptionRecord->ExceptionCode;
    if (code == EXCEPTION_ILLEGAL_INSTRUCTION && (void *)c->Rip == ud2_at) {
        if (InterlockedIncrement(&ud2s) == 1) {
            c->Dr0 = c->Rip;
            c->Dr7 = 1;
        } else {
            c->Dr7 = 0;
            c->Rip += 2;
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    if (code == EXCEPTION_SINGLE_STEP) {
        InterlockedIncrement(&steps);
        step_at = (ULONG_PTR)e->ExceptionRecord->ExceptionAddress;
        step_dr6 = c->Dr6;
        c->Dr7 = 0;
        if ((void *)c->Rip == ud2_at) c->Rip += 2;
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static __attribute__((noinline)) int target(int x) { return x * 3 + 1; }
static int (*volatile call_target)(int) = target;

/* The non-canonical read below is 48 8b 00 (mov rax, [rax]): note the fault, step over it. */
static LONG CALLBACK on_exception(EXCEPTION_POINTERS *e)
{
    if (e->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    fault_info[0] = e->ExceptionRecord->ExceptionInformation[0];
    fault_info[1] = e->ExceptionRecord->ExceptionInformation[1];
    InterlockedIncrement(&faults);
    e->ContextRecord->Rip += 3;
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main(void)
{
    unsigned eax, ebx, ecx, edx;
    volatile ULONG64 line[8] = {1};
    ULONG64 id = ~0ull, value = 0x8000000000000000ull;

    __cpuid_count(7, 0, eax, ebx, ecx, edx);
    printf("leaf 7: ebx %08x ecx %08x\n", ebx, ecx);
    if ((ebx & 0x01800000) != 0x01800000 || !(ecx & 0x00400000)) {
        printf("bug: leaf 7 lacks CLFLUSHOPT, CLWB or RDPID\n");
        return 2;
    }
    AddVectoredExceptionHandler(1, on_exception);

    __asm__ volatile(".byte 0x66, 0x0f, 0xae, 0x30" :: "a"(line) : "memory");  /* clwb [rax] */
    __asm__ volatile(".byte 0xf3, 0x48, 0x0f, 0xc7, 0xf8" : "=a"(id));          /* rdpid rax */
    if (id > 255) { printf("FAIL: RDPID gave %llu\n", (unsigned long long)id); return 1; }

    __asm__ volatile(".byte 0x48, 0x8b, 0x00" : "+a"(value) :: "memory");       /* mov rax, [rax] */
    if (faults != 1 || fault_info[0] != 0 || fault_info[1] != ~(ULONG_PTR)0) {
        printf("FAIL: the non-canonical read gave %ld faults, at %p (flag %lu), not one at -1\n", faults,
               (void *)fault_info[1], (unsigned long)fault_info[0]);
        return 1;
    }
    printf("ok: CLWB ran, RDPID gave processor %llu, the non-canonical read faulted at -1\n", (unsigned long long)id);

    RemoveVectoredExceptionHandler(on_exception);
    AddVectoredExceptionHandler(1, on_breakpoint);
    __asm__ volatile("leaq 1f(%%rip), %%rax\n\tmovq %%rax, ud2_at(%%rip)\n1:\tud2" ::: "rax", "memory");
    if (ud2s != 1 || steps != 1 || step_at != (ULONG_PTR)ud2_at || !(step_dr6 & 1)) {
        printf("FAIL: a breakpoint on the faulting ud2 at %p: %ld faults, %ld debug exceptions (at %p, Dr6 %#llx)\n",
               ud2_at, ud2s, steps, (void *)step_at, (unsigned long long)step_dr6);
        return 1;
    }
    {
        CONTEXT c = { .ContextFlags = CONTEXT_DEBUG_REGISTERS };
        int r;
        c.Dr0 = (DWORD64)target;
        c.Dr7 = 1;
        if (!SetThreadContext(GetCurrentThread(), &c)) { printf("FAIL: SetThreadContext\n"); return 1; }
        r = call_target(4);
        if (steps != 2 || step_at != (ULONG_PTR)target || r != 13) {
            printf("FAIL: a breakpoint on a call of %p: %ld debug exceptions in all (last at %p), result %d\n",
                   (void *)target, steps, (void *)step_at, r);
            return 1;
        }
    }
    printf("ok: execution breakpoints stop the thread on a faulting instruction and on a call\n");
    return 0;
}
