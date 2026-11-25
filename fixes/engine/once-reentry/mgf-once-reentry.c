// A pthread_once a thread enters again from inside itself returns instead of ending the process.
//
// CrossOver's ntdll.so (CW HACK 22434) sets up D3DMetal's non-native code regions once per
// process, under a pthread_once: the first time a native module loads (pe_module_loaded, which
// ntdll.dll calls right after it maps the game's exe) it dlopens libd3dshared.dylib, which takes
// a while. register_allocated_code_region, which NtProtectVirtualMemory calls when memory becomes
// executable, goes through the same pthread_once. When another process changes the game's memory
// in that window (VirtualProtectEx: Swofty Launcher's offline play patching F1 25 as it resumes
// it), Wine runs that change on the game's main thread, from the suspend signal it is handling,
// and the thread enters the pthread_once it is already inside. macOS ends the process on that
// (_os_once_gate_recursive_abort, an illegal instruction; Wine's log says "nested exception on
// signal stack"). Recorded on 2026-11-25, NotProton, CrossOver Preview 41303 on Rosetta, with an
// ntdll.so that kept the faulting thread's frames:
//     _sigtramp > usr1_handler > wait_suspend > server_select > invoke_system_apc >
//     NtProtectVirtualMemory > register_allocated_code_region > pthread_once > abort
// It is a race: F1 25 started now and then, and failed 5 times out of 7. With this armed it
// started 3 times out of 3 the same evening; on the first the re-entry came, right after the
// exe loaded, and the game went on to the menu.
//
// This points ntdll.so's import of pthread_once (a __got entry, as mgf-signals.c does for
// sigaction) at mgf_once. A thread that calls it for a once it is already running returns 0 at
// once, as if the work were done; anything else goes to pthread_once as before. The interrupted
// call finishes the work when the thread returns to it. For the call above that is right:
// register_allocated_code_region only registers a region when CX_DYNAMIC_NON_NATIVE_REGIONS=1,
// and it reads the pointers it would call, which are NULL until the work is done. ntdll.dll
// (NotProton's or another) and ntdll.so stay as they are on disk.
//
// It is Wine's fault, not a game's, so mgf-engine.dylib arms it in every game its row is on for.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "../mgf_hooks.h"

#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

#define TAG "once-reentry"
#define RUNNING 64

typedef int (*once_fn)(pthread_once_t *, void (*)(void));

static once_fn real_once;
// The pthread_once calls running now, by thread: a slot is claimed with its owner, then given
// the once. A thread reads only its own slots for itself, from a signal handler too.
static struct {
    pthread_t owner;
    pthread_once_t *once;
} running[RUNNING];
static int noted;

static void note(void) {
    static const char msg[] = TAG ": a thread entered a pthread_once it was running; it returned instead\n";
    if (!__atomic_exchange_n(&noted, 1, __ATOMIC_RELAXED)) (void)!write(2, msg, sizeof(msg) - 1);
}

static int mgf_once(pthread_once_t *once, void (*init)(void)) {
    pthread_t self = pthread_self();
    int slot = -1;
    for (int i = 0; i < RUNNING; i++)
        if (__atomic_load_n(&running[i].owner, __ATOMIC_ACQUIRE) == self &&
            __atomic_load_n(&running[i].once, __ATOMIC_ACQUIRE) == once) {
            note();
            return 0;
        }
    for (int i = 0; i < RUNNING && slot < 0; i++) {
        pthread_t none = NULL;
        if (__atomic_compare_exchange_n(&running[i].owner, &none, self, 0, __ATOMIC_ACQ_REL, __ATOMIC_RELAXED))
            slot = i;
    }
    if (slot >= 0) __atomic_store_n(&running[slot].once, once, __ATOMIC_RELEASE);
    int rc = real_once(once, init);
    if (slot >= 0) {
        __atomic_store_n(&running[slot].once, NULL, __ATOMIC_RELEASE);
        __atomic_store_n(&running[slot].owner, NULL, __ATOMIC_RELEASE);
    }
    return rc;
}

void mgf_once_reentry_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide) {
    uintptr_t real = (uintptr_t)pthread_once, *found = NULL;
    int n = api->count_pointers(mh, slide, real, &found);
    if (n != 1 || !found) {
        fprintf(stderr, TAG ": ntdll.so has %d pointer(s) to pthread_once, not 1: not armed\n", n);
        return;
    }
    real_once = (once_fn)real;
    if (!api->swap_pointer(found, real, (uintptr_t)mgf_once)) {
        fprintf(stderr, TAG ": ntdll.so's pthread_once import could not be changed: not armed\n");
        return;
    }
    fprintf(stderr, TAG ": armed\n");
}
