// The threadpool's timer thread, kept from spinning: engine patch 0021 as a NotProton plugin,
// for the games that need it.
//
// wineserver makes a relative timer expiry a deadline by subtracting its monotonic clock
// (timeout_to_abstime), which overflows when the expiry is within that clock of -MAXLONGLONG,
// and the timer is then signalled at once. Wine's threadpool arms its relative timer with such
// a value, rel_now - MAXLONGLONG, whenever no relative timer is pending (threadpool.c,
// update_timers): with only absolute timers, or a timer object not yet set, its timer thread
// wakes and re-arms in a loop. Forza Horizon 6: 88,000 set_timer requests a second, wineserver
// at 57% of a core.
//
// Patch 0021 sends such an expiry as -2^62, about 14,600 years, which cannot overflow and is as
// good as never, inside ntdll.so for every game. This does the same from outside it, in the
// game's process only: it replaces the syscall table's entry for NtSetTimer, so NotProton's
// ntdll stays as it is. Every other expiry goes through unchanged. On 41303's x86_64 ntdll.so
// that entry is a thunk that extends the BOOLEAN resume and jumps to NtSetTimer, so the entry is
// found through the table (../mgf_hooks.h) and the hook chains to the thunk.
//
// It is part of mgf-engine.dylib (../mgf-engine.c), which arms it in Forza Horizon 6.
// build-engine.sh builds it and runs its check (check.c): a Windows program that makes a
// threadpool timer, sets none, and measures its own CPU time while it sleeps, under a runner
// without 0021, with and without this fix armed.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../mgf_hooks.h"

#include <stdint.h>

#define TAG "timer-overflow"

typedef int32_t NTSTATUS;
typedef void *HANDLE;

// The earliest relative expiry sent as it is: -2^62, the value 0021 sends instead.
#define NEVER (-((int64_t)1 << 62))

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*set_timer_fn)(HANDLE handle, const int64_t *when, void *callback, void *arg, uint8_t resume,
                                 uint32_t period, uint8_t *state);

static const struct np_plugin_api *api;
static set_timer_fn real_set_timer;
static int said;

static NTSTATUS set_timer_hook(HANDLE handle, const int64_t *when, void *callback, void *arg, uint8_t resume,
                               uint32_t period, uint8_t *state) {
    if (when && *when < NEVER) {
        int64_t never = NEVER;
        if (!__atomic_exchange_n(&said, 1, __ATOMIC_RELAXED))
            api->log(TAG, "first relative expiry wineserver would overflow on (%lld) sent as -2^62",
                     (long long)*when);
        return real_set_timer(handle, &never, callback, arg, resume, period, state);
    }
    return real_set_timer(handle, when, callback, arg, resume, period, state);
}

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    (void)image;
    uintptr_t old, *slot = mgf_syscall_slot(api, mh, slide, "_NtSetTimer", &old);
    if (!slot) {
        api->log(TAG, "no one syscall table entry for NtSetTimer, not armed");
        return;
    }
    real_set_timer = (set_timer_fn)old;
    if (!api->swap_pointer(slot, old, (uintptr_t)set_timer_hook)) {
        api->log(TAG, "the syscall table could not be written, not armed");
        return;
    }
    api->log(TAG, "relative timer expiries wineserver would overflow on are sent as -2^62");
}

// mgf-engine.dylib (../mgf-engine.c) arms this for the games that need it.
void mgf_timer_overflow_arm(const struct np_plugin_api *with, const struct mach_header_64 *mh, intptr_t slide) {
    api = with;
    arm(mh, slide, NULL);
}
