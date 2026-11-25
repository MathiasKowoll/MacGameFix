// MacGameFix's engine fixes, one library for NotProton and one row: "Engine fixes (MacGameFix)".
//
// Wine fixes that used to be engine patches in the runner's ntdll.so or kernel32.dll, for every
// game, made again from outside those files, for the games that need them. NotProton loads this
// library into a game when the game's row is on; it looks at which game it is in and arms that
// game's fixes alone. Another game with the row on gets nothing from it.
//
// One row for them all, rather than one for each game, because NotProton reads at most 32 rows
// from its plugins folder, for every game together. Each game's fix (its installer) adds its app
// to the row's apps, so the row shows on that game's page only, and switches the row on there.
//
//   low-allocations  engine patch 0038  F1 25 (3059520)       allocations kept below Wine's high area
//   package-family   engine patch 0041  EA SPORTS FC 27 (4080220)  FindPackagesByPackageFamily in kernel32
//   timer-overflow   engine patch 0021  Forza Horizon 6 (2483190)  the threadpool's timer thread kept still
//
// The game is the Steam app NotProton starts: STEAM_COMPAT_APP_ID, else SteamAppId, else
// SteamGameId. MGF_ENGINE_FIXES, a comma-separated list of the names above, arms those instead,
// whatever the game: build-engine.sh's checks use it.
//
// Every fix works through NotProton's plugin host (plugin-host.dylib); without it nothing is
// armed and the library says so.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mgf_hooks.h"

#include <stdlib.h>
#include <string.h>

#define TAG "mgf-engine"

typedef void (*arm_fn)(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);

void mgf_low_allocations_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_package_family_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);
void mgf_timer_overflow_arm(const struct np_plugin_api *, const struct mach_header_64 *, intptr_t);

static const struct fix {
    const char *name;
    arm_fn arm;
    unsigned app;
} FIXES[] = {
    {"low-allocations", mgf_low_allocations_arm, 3059520},
    {"package-family", mgf_package_family_arm, 4080220},
    {"timer-overflow", mgf_timer_overflow_arm, 2483190},
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
        if (wanted[i]) FIXES[i].arm(api, mh, slide);
}

__attribute__((constructor)) static void mgf_engine_init(void) {
    if (!(api = np_plugin_api())) {
        fprintf(stderr, TAG ": plugin-host.dylib isn't loaded, nothing armed\n");
        return;
    }
    const char *only = getenv("MGF_ENGINE_FIXES");
    unsigned app = this_app(), n = 0;
    for (unsigned i = 0; i < COUNT; i++) {
        wanted[i] = (only && *only) ? listed(only, FIXES[i].name) : FIXES[i].app == app;
        n += wanted[i];
    }
    if (!n) {
        api->log(TAG, "app %u: no engine fix is for this game", app);
        return;
    }
    api->on_first_image("ntdll.so", "-unix/", arm);
}
