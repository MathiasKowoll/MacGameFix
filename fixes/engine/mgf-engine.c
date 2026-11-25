// MacGameFix's engine fixes, one library for NotProton and one row: "Engine fixes (MacGameFix)".
//
// Wine fixes that used to be engine patches in the runner's ntdll.so or kernel32.dll, for every
// game, made again from outside those files, for the games that need them. NotProton loads this
// library into a game when the game's row is on; it looks at which game it is in and arms that
// game's fixes, and the ones for every game (once-reentry), alone.
//
// One row for them all, rather than one for each game, because NotProton reads at most 32 rows
// from its plugins folder, for every game together. Each game's fix (its installer) adds its app
// to the row's apps, so the row shows on that game's page only, and switches the row on there.
//
//   low-allocations  engine patch 0038  F1 25 (3059520)       allocations kept below Wine's high area
//   package-family   engine patch 0041  EA SPORTS FC 27 (4080220)  FindPackagesByPackageFamily in kernel32
//   timer-overflow   engine patch 0021  Forza Horizon 6 (2483190)  the threadpool's timer thread kept still
//   dualstack-ipv4   engine patch 0026  Forza Horizon 6 (2483190)  IPv4 options on its dual-stack game
//                                       socket, for the online sessions
//   direct-syscall   engine patches     Forza Horizon 6 (2483190)  a direct system call or an
//                    0028, 0029                        exception Rosetta delivers on top of a
//                                                      suspend, replayed after it
//   rosetta-cpu      engine patches     every game the row is on for  Rosetta's CPUID leaf 7, CLWB,
//                    0017, 0019, 0020                     RDPID and faults as copy protection
//                                                         expects them (no execution breakpoints)
//   once-reentry     -                  every game the row is on for  a pthread_once a thread
//                                       enters again from a suspend returns instead of ending the
//                                       process (F1 25 under Swofty's offline play; once-reentry/)
//   d3dmetal-hookable  -                EA SPORTS FC 27 (4080220)  D3DMetal's method stubs made
//                                       hookable for FC 27 Live Editor's window
//                                       (../d3dmetal-hookable/mgf-d3dmetal-hookable.c)
//
// The game is the Steam app NotProton starts: STEAM_COMPAT_APP_ID, else SteamAppId, else
// SteamGameId. MGF_ENGINE_FIXES, a comma-separated list of the names above, arms those instead,
// whatever the game: build-engine.sh's checks use it.
//
// The Wine fixes work through NotProton's plugin host (plugin-host.dylib); without it they are
// not armed and the library says so. d3dmetal-hookable needs no host: it starts a thread of its
// own.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mgf_hooks.h"

#include <stdlib.h>
#include <string.h>

#define TAG "mgf-engine"

typedef void (*arm_fn)(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
typedef void (*start_fn)(void);

void mgf_low_allocations_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_package_family_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_timer_overflow_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_dualstack_ipv4_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_rosetta_cpu_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_direct_syscall_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_once_reentry_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_d3dmetal_hookable_start(void);

// A fix either arms through ntdll.so (arm, when the host sees it) or starts by itself (start).
static const struct fix {
    const char *name;
    arm_fn arm;
    start_fn start;
    unsigned app;
} FIXES[] = {
    {"low-allocations", mgf_low_allocations_arm, NULL, 3059520},
    {"package-family", mgf_package_family_arm, NULL, 4080220},
    {"timer-overflow", mgf_timer_overflow_arm, NULL, 2483190},
    {"dualstack-ipv4", mgf_dualstack_ipv4_arm, NULL, 2483190},
    {"rosetta-cpu", mgf_rosetta_cpu_arm, NULL, 0},  // every game: what engine patch 0020 did
    {"direct-syscall", mgf_direct_syscall_arm, NULL, 2483190},
    {"once-reentry", mgf_once_reentry_arm, NULL, 0},  // every game
    {"d3dmetal-hookable", NULL, mgf_d3dmetal_hookable_start, 4080220},
};
#define COUNT (sizeof(FIXES) / sizeof(FIXES[0]))

static const struct np_plugin_api *api;
static int wanted[COUNT];

static unsigned this_app(void) {
    const char *names[] = {"STEAM_COMPAT_APP_ID", "SteamAppId", "SteamGameId"};
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        const char *v = getenv(names[i]);
        if (v && *v) return (unsigned)strtoul(v, NULL, 10);
    }
    return 0;
}

// Whether `name` is one of the comma-separated words in `list`.
static int listed(const char *list, const char *name) {
    size_t n = strlen(name);
    for (const char *p = list; *p;) {
        const char *end = strchr(p, ',');
        size_t len = end ? (size_t)(end - p) : strlen(p);
        if (len == n && !strncmp(p, name, n)) return 1;
        if (!end) break;
        p = end + 1;
    }
    return 0;
}

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    (void)image;
    for (unsigned i = 0; i < COUNT; i++)
        if (wanted[i] && FIXES[i].arm) FIXES[i].arm(api, mh, slide);
}

__attribute__((constructor)) static void mgf_engine_init(void) {
    const char *only = getenv("MGF_ENGINE_FIXES");
    unsigned app = this_app(), arms = 0, starts = 0;
    for (unsigned i = 0; i < COUNT; i++) {
        wanted[i] = (only && *only) ? listed(only, FIXES[i].name) : (FIXES[i].app == 0 || FIXES[i].app == app);
        if (!wanted[i]) continue;
        if (FIXES[i].start) {
            FIXES[i].start();
            starts++;
        }
        if (FIXES[i].arm) arms++;
    }
    if (!arms) {
        if (!starts) fprintf(stderr, TAG ": app %u: no engine fix is for this game\n", app);
        return;
    }
    if (!(api = np_plugin_api())) {
        fprintf(stderr, TAG ": plugin-host.dylib isn't loaded, the Wine fixes are not armed\n");
        return;
    }
    api->on_first_image("ntdll.so", "-unix/", arm);
}
