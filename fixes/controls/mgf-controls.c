// MacGameFix's DualSense controls, one library for NotProton and one row: "DualSense controllers
// (MacGameFix)", on for every game through the tool's defaults.
//
// The runner keeps CodeWeavers' own winebus.so and winecoreaudio.so. NotProton loads this library
// into every process of a game whose row is on, winedevice.exe included (it gets the game's
// environment): when winebus.so is loaded this takes its IOKit calls (bus.c), and when
// winecoreaudio.so is, its CoreAudio calls (audio.c). What engine
// patches 0004-0016 and 0030 did inside those files is done from here; their Windows halves
// (winebus.sys, hidclass, xinput, mmdevapi, setupapi, xaudio2) come as a NotProton variant.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include "pad.h"
#include "../../app/notproton-plugins/notproton_plugin.h"

void mgf_controls_bus_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide);
void mgf_controls_audio_arm(const struct np_plugin_api *api, const struct mach_header_64 *mh, intptr_t slide);

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

__attribute__((constructor)) static void mgf_controls_init(void) {
    if (!(api = np_plugin_api())) {
        pad_log("controls: plugin-host.dylib isn't loaded, the controls are not armed\n");
        return;
    }
    api->on_first_image("winebus.so", "-unix/", bus_loaded);
    api->on_first_image("winecoreaudio.so", "-unix/", audio_loaded);
}
