// Signal handlers of MacGameFix's engine fixes, run before Wine's (mgf_hooks.h, mgf_signal_first).
//
// Wine installs its SIGSEGV, SIGILL, SIGBUS and SIGTRAP handlers late, in signal_init_process,
// which server_init_process_done calls once the process is set up: after every image a plugin
// sees load. A handler a plugin installs before that is replaced; one installed after it would
// need a moment the plugin is never given. So this changes how ntdll.so installs them: its
// import of sigaction (a __got entry, bound when the image loads) is pointed at mgf_sigaction.
// When ntdll.so installs a handler for a signal a fix asked for, ours goes in its place, and
// Wine's is kept as the next one. On the signal each fix's handler is asked in turn; the first
// that answers 1 has dealt with it, and the thread resumes from the context it left. When none
// does, Wine's handler gets the signal, with the context as the fixes left it.
//
// Only ntdll.so's own calls go through this: a handler another library installs replaces ours
// as it would replace Wine's. Signals no fix asked for, and the handlers ntdll.so installs
// without SA_SIGINFO, pass through untouched.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mgf_hooks.h"

#include <signal.h>

#define MGF_SIGNAL_HANDLERS 8

typedef void (*action_fn)(int, siginfo_t *, void *);
typedef int (*sigaction_fn)(int, const struct sigaction *, struct sigaction *);

static struct {
    int sig;
    mgf_signal_fn fn;
} handlers[MGF_SIGNAL_HANDLERS];
static int nhandlers;
static action_fn next[NSIG];
static sigaction_fn real_sigaction;
static uintptr_t *slot;

static int watched(int sig) {
    for (int i = 0; i < nhandlers; i++)
        if (handlers[i].sig == sig) return 1;
    return 0;
}

static void first_handler(int sig, siginfo_t *info, void *context) {
    int n = __atomic_load_n(&nhandlers, __ATOMIC_ACQUIRE);
    for (int i = 0; i < n; i++)
        if (handlers[i].sig == sig && handlers[i].fn(sig, info, (ucontext_t *)context)) return;
    action_fn then = __atomic_load_n(&next[sig], __ATOMIC_ACQUIRE);
    if (then) then(sig, info, context);
}

static int mgf_sigaction(int sig, const struct sigaction *act, struct sigaction *old) {
    if (act && sig > 0 && sig < NSIG && watched(sig) && (act->sa_flags & SA_SIGINFO) &&
        act->sa_sigaction != first_handler) {
        struct sigaction mine = *act;
        action_fn before = next[sig];
        mine.sa_sigaction = first_handler;
        __atomic_store_n(&next[sig], act->sa_sigaction, __ATOMIC_RELEASE);
        int rc = real_sigaction(sig, &mine, old);
        if (rc) __atomic_store_n(&next[sig], before, __ATOMIC_RELEASE);
        else if (old && (old->sa_flags & SA_SIGINFO) && old->sa_sigaction == first_handler) old->sa_sigaction = before;
        return rc;
    }
    return real_sigaction(sig, act, old);
}

int mgf_signal_first(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide, int sig,
                     mgf_signal_fn fn) {
    if (sig <= 0 || sig >= NSIG || !fn || nhandlers >= MGF_SIGNAL_HANDLERS) return 0;
    if (!slot) {
        uintptr_t real = (uintptr_t)sigaction, *found = NULL;
        if (api->count_pointers(mh, slide, real, &found) != 1 || !found) return 0;
        real_sigaction = (sigaction_fn)real;
        if (!api->swap_pointer(found, real, (uintptr_t)mgf_sigaction)) return 0;
        slot = found;
    }
    handlers[nhandlers].sig = sig;
    handlers[nhandlers].fn = fn;
    __atomic_store_n(&nhandlers, nhandlers + 1, __ATOMIC_RELEASE);
    return 1;
}
