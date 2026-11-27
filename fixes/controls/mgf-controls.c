// MacGameFix's DualSense controls, one library for NotProton and one row: "DualSense controllers",
// the same on every game's page and switched on game by game (app/NotProtonPlugins.swift).
//
// For a runner that keeps CodeWeavers' own winebus.so and winecoreaudio.so. NotProton loads this
// library into every process of a game whose row is on, winedevice.exe included (it gets the
// game's environment): when winebus.so is loaded this takes its IOKit calls (bus.c), and when
// winecoreaudio.so is, its CoreAudio calls (audio.c). What engine patches 0004-0016 and 0030 do
// inside those two files is done from here, by the game's settings in Game Feel (pad.d).
//
// The Windows side moves here too, module by module: setupapi.dll's is done (pe.h, setupapi.c),
// winebus.sys's, the container of a USB device (container.c), and mmdevapi.dll's two: an audio
// endpoint's container (mmdevapi.c) and the endpoints listed in SetupAPI (endpoints.c).
// hidclass.sys, xinput and xaudio2 are still the Wine modules' own files in the runner.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include "pad.h"
#include "pe.h"
#include "../../app/notproton-plugins/notproton_plugin.h"

void mgf_controls_bus_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide);
void mgf_controls_audio_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide);
void mgf_controls_setupapi(void);
void mgf_controls_mmdevapi(void);
void mgf_controls_endpoints_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide);
void mgf_controls_container(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide);

static const struct np_plugin_api *api;

// A runner the Wine modules were put into has MacGameFix's own winebus.so and winecoreaudio.so,
// which do all of this themselves: taking their calls as well would do it twice. Those files
// name the folder the pad's log is in ("/tmp/macgamefix-%u"); CodeWeavers' do not.
static bool ours(const struct mach_header_64 *mh, const char *name) {
    unsigned long size = 0;
    const uint8_t *strings = getsectiondata(mh, "__TEXT", "__cstring", &size);
    if (!strings || !memmem(strings, size, "/tmp/macgamefix-", 16)) return false;
    pad_log("controls: %s is MacGameFix's own here, which does this itself: left alone\n", name);
    return true;
}

static void audio_loaded(const struct mach_header_64 *mh, intptr_t slide, const char *path) {
    (void)path;
    if (!ours(mh, "winecoreaudio.so")) mgf_controls_audio_arm(api, mh, slide);
}

static void bus_loaded(const struct mach_header_64 *mh, intptr_t slide, const char *path) {
    (void)path;
    if (!ours(mh, "winebus.so")) mgf_controls_bus_arm(api, mh, slide);
}

// The Windows side. pe.h: each part says which module it changes, then NtMapViewOfSection is
// taken. container.c takes NtSetValueKey.
static void ntdll_loaded(const struct mach_header_64 *mh, intptr_t slide, const char *path) {
    (void)path;
    mgf_controls_setupapi();
    mgf_controls_mmdevapi();
    pe_arm(api, mh, slide);
    mgf_controls_container(api, mh, slide);
    mgf_controls_endpoints_arm(api, mh, slide);
}

__attribute__((constructor)) static void mgf_controls_init(void) {
    if (!(api = np_plugin_api())) {
        pad_log("controls: plugin-host.dylib isn't loaded, the controls are not armed\n");
        return;
    }
    api->on_first_image("ntdll.so", "-unix/", ntdll_loaded);
    api->on_first_image("winebus.so", "-unix/", bus_loaded);
    api->on_first_image("winecoreaudio.so", "-unix/", audio_loaded);
}
