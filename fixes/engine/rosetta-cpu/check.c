/* The check for the rosetta-cpu fix: a Windows program, run under a NotProton runner on Rosetta.
 *
 * It reads CPUID leaf 7, then runs what a game whose copy protection checks the leaf runs when
 * it says yes: CLWB on a variable, RDPID, and a read through a non-canonical address, which it
 * expects to raise an access violation at -1. On a runner without patch 0017 the leaf has none
 * of the three bits. With the fix, or 0017, it has them, CLWB and RDPID run, RDPID gives the
 * processor GetCurrentProcessorNumber gives, and the read faults as on Windows.
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
    return 0;
}
