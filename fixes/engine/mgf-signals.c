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
// does, Wine's handler gets the signal, with the context as the fixes left it. A fix can also ask
// to see the context once Wine's handler has returned (mgf_signal_after), with the instruction
// pointer the thread had when the signal came.
//
// Only ntdll.so's own calls go through this: a handler another library installs replaces ours
// as it would replace Wine's. Signals no fix asked for, and the handlers ntdll.so installs
// without SA_SIGINFO, pass through untouched.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mgf_hooks.h"

#include <signal.h>

#define MGF_SIGNAL_HANDLERS 16

typedef void (*action_fn)(int, siginfo_t *, void *);
typedef int (*sigaction_fn)(int, const struct sigaction *, struct sigaction *);

static struct {
    int sig;
    mgf_signal_fn fn;
    mgf_signal_after_fn after;
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

static uintptr_t pc_of(ucontext_t *uc) {
#if defined(__x86_64__)
    return uc->uc_mcontext->__ss.__rip;
#else
    return uc->uc_mcontext->__ss.__pc;
#endif
}

static void first_handler(int sig, siginfo_t *info, void *context) {
    ucontext_t *uc = (ucontext_t *)context;
    int n = __atomic_load_n(&nhandlers, __ATOMIC_ACQUIRE);
    uintptr_t pc = pc_of(uc);
    for (int i = 0; i < n; i++)
        if (handlers[i].sig == sig && handlers[i].fn && handlers[i].fn(sig, info, uc)) return;
    action_fn then = __atomic_load_n(&next[sig], __ATOMIC_ACQUIRE);
    if (then) then(sig, info, context);
    for (int i = 0; i < n; i++)
        if (handlers[i].sig == sig && handlers[i].after) handlers[i].after(sig, info, uc, pc);
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

static int add(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide, int sig,
               mgf_signal_fn fn, mgf_signal_after_fn after) {
    if (sig <= 0 || sig >= NSIG || (!fn && !after) || nhandlers >= MGF_SIGNAL_HANDLERS) return 0;
    if (!slot) {
        uintptr_t real = (uintptr_t)sigaction, *found = NULL;
        if (api->count_pointers(mh, slide, real, &found) != 1 || !found) return 0;
        real_sigaction = (sigaction_fn)real;
        if (!api->swap_pointer(found, real, (uintptr_t)mgf_sigaction)) return 0;
        slot = found;
    }
    handlers[nhandlers].sig = sig;
    handlers[nhandlers].fn = fn;
    handlers[nhandlers].after = after;
    __atomic_store_n(&nhandlers, nhandlers + 1, __ATOMIC_RELEASE);
    return 1;
}

int mgf_signal_first(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide, int sig,
                     mgf_signal_fn fn) {
    return fn && add(api, mh, slide, sig, fn, NULL);
}

int mgf_signal_after(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide, int sig,
                     mgf_signal_after_fn fn) {
    return fn && add(api, mh, slide, sig, NULL, fn);
}
