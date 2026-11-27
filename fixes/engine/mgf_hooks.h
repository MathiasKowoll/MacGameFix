// What MacGameFix's NotProton plugins share on top of NotProton's plugin host
// (app/notproton-plugins/notproton_plugin.h).
//
// mgf_syscall_slot finds a function's entry in ntdll.so's syscall table even when the entry is
// not the function itself. The host's count_pointers looks for pointers to the exported
// function, which is what the table holds for most syscalls; for some, the compiler put a
// thunk in the table instead, a few instructions that extend a narrow argument and jump to the
// function. NtSetTimer on CrossOver Preview 41303's x86_64 ntdll.so, slot 0x62:
//     45 0f b6 c0        movzx r8d, r8b        (its BOOLEAN resume)
//     e9 <rel32>         jmp   NtSetTimer
// With the host alone such a syscall can't be hooked: no table entry points at the function.
//
// This reads KeServiceDescriptorTable, which ntdll.so exports, and takes the one entry that is
// the function or a thunk whose first jmp, within its first 24 bytes, lands on the function. A
// hook put in that entry chains to what the entry held, the thunk included, so the narrow
// argument is still extended as the dispatcher's callers expect.
//
// mgf_signal_first (mgf-signals.c) puts a fix's handler for a signal before Wine's: Wine
// installs its own late, from ntdll.so, and mgf-signals.c says how they are kept in front.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef MGF_HOOKS_H
#define MGF_HOOKS_H

#include "../../app/notproton-plugins/notproton_plugin.h"

#include <stdint.h>
#include <string.h>

struct mgf_service_table {
    void **table;
    uintptr_t *counters;
    uint32_t limit;
    unsigned char *arguments;
};

// Where a thunk at `at` jumps, or 0: the first jmp in its first 24 bytes. On x86-64 an E9 jmp.
// On arm64 an unconditional b; the FEX side's ntdll.so (41303) has thunks of its own, packed
// one after the other with nops between them, so only the first b counts:
//     12001c84  and  w4, w4, #0xff       NtSetTimer, slot 0x62: its BOOLEAN resume
//     17ffefc1  b    NtSetTimer
//     b9400be8  ldr  w8, [sp, #8]        NtMapViewOfSection, slot 0x28: a narrow stack argument
//     b90007e8  str  w8, [sp, #4]
//     14005c8c  b    NtMapViewOfSection
static inline uintptr_t mgf_thunk_target(uintptr_t at) {
#if defined(__x86_64__)
    const unsigned char *b = (const unsigned char *)at;
    for (int i = 0; i + 5 <= 24; i++) {
        if (b[i] == 0xe9) {
            int32_t rel;
            memcpy(&rel, b + i + 1, 4);
            return at + i + 5 + (intptr_t)rel;
        }
        if (b[i] == 0xc3) return 0;  // a ret first: not a thunk
    }
#elif defined(__aarch64__)
    for (int i = 0; i < 6; i++) {
        uint32_t ins;
        memcpy(&ins, (const void *)(at + 4 * i), 4);
        if ((ins & 0xfc000000) == 0x14000000) {  // b <imm26>
            int32_t imm = (int32_t)(ins << 6) >> 6;
            return at + 4 * i + (intptr_t)imm * 4;
        }
        if ((ins & 0xfffffc1f) == 0xd65f0000) return 0;  // a ret first: not a thunk
    }
#else
    (void)at;
#endif
    return 0;
}

// A 32-bit argument of a syscall that is passed on the stack, after the eighth. Wine's syscall
// dispatcher passes stack arguments in 8-byte slots, as Windows does. On arm64, Apple's ABI packs
// them to their own size, so the FEX side's ntdll.so has a thunk that repacks them
// (NtMapViewOfSection's at slot 0x28, above). A hook in that entry sees the slots as the
// dispatcher left them, so it takes such an argument as a whole slot, and it passes the slot on
// to the thunk the same way.
#if defined(__aarch64__)
typedef uint64_t mgf_stack_u32;
#else
typedef uint32_t mgf_stack_u32;
#endif

// The syscall table's one entry for `name` (as nm spells it, with its underscore), the entry
// itself or a thunk to it; NULL when there is none or more than one. *old gets what it holds.
static inline uintptr_t *mgf_syscall_slot(const struct np_plugin_api *api, const struct mach_header_64 *mh,
                                          intptr_t slide, const char *name, uintptr_t *old) {
    struct mgf_service_table *t = (struct mgf_service_table *)api->symbol(mh, slide, "_KeServiceDescriptorTable");
    uintptr_t fn = api->symbol(mh, slide, name);
    uintptr_t *found = NULL;
    int count = 0;
    if (!t || !fn || !t->table || t->limit > 4096) return NULL;
    for (uint32_t i = 0; i < t->limit; i++) {
        uintptr_t entry = (uintptr_t)t->table[i];
        if (entry == fn || (entry && mgf_thunk_target(entry) == fn)) {
            found = (uintptr_t *)&t->table[i];
            count++;
        }
    }
    if (count != 1) return NULL;
    *old = *found;
    return found;
}

#include <signal.h>
#include <sys/ucontext.h>

// A fix's handler: 1 when it dealt with the signal (the thread resumes from the context as the
// handler left it), 0 to pass it on, to the next fix's and then to Wine's.
typedef int (*mgf_signal_fn)(int sig, siginfo_t *info, ucontext_t *context);

// Puts `fn` before the handler ntdll.so will install for `sig`; called from a fix's arm, when
// ntdll.so has loaded and before its process setup. 0 when it cannot.
int mgf_signal_first(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide, int sig,
                     mgf_signal_fn fn);

// Called once Wine's handler for `sig` has returned to it, with the context as it is then and
// the instruction pointer the thread had when the signal came. Same conditions as above.
typedef void (*mgf_signal_after_fn)(int sig, siginfo_t *info, ucontext_t *context, uintptr_t pc);
int mgf_signal_after(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide, int sig,
                     mgf_signal_after_fn fn);

// Wine's own handler for `sig`, once ntdll.so has installed it behind ours (NULL before): a fix
// that turns one signal into another hands the context to it. Read it from a handler, not at arm.
void (*mgf_signal_wine(int sig))(int, siginfo_t *, void *);

#endif
