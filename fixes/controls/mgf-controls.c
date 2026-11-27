// MacGameFix's DualSense controls, one library for NotProton and one row: "DualSense controllers",
// the same on every game's page and switched on game by game (app/NotProtonPlugins.swift).
//
// For a runner that keeps CodeWeavers' own winebus.so and winecoreaudio.so. NotProton loads this
// library into every process of a game whose row is on, winedevice.exe included (it gets the
// game's environment): when winebus.so is loaded this takes its IOKit calls (bus.c), and when
// winecoreaudio.so is, its CoreAudio calls (audio.c). What engine patches 0004-0016 and 0030 do
// inside those two files is done from here, by the game's settings in Game Feel (pad.d).
//
// The Windows side is done from here too, on CodeWeavers' own files, each module by a part of
// its own (pe.h for what the macOS side does to a module as it is mapped, windows.h for what the
// game then runs as Windows code):
//   setupapi.c   setupapi.dll   a device's base container id in WCHAR from the ANSI function (0010)
//   container.c  winebus.sys    a USB device's container made from its location (0001)
//   mmdevapi.c   mmdevapi.dll   an audio endpoint's container asked of the driver (0003)
//   endpoints.c  mmdevapi.dll   the audio endpoints listed in SetupAPI (0009)
//   xaudio2.c    xaudio2_9.dll  the device a mastering voice is created on (0011)
//   hidclass.c   hidclass.sys   a pad's collection with motors offered to xinput (0007)
//   xinput.c     xinput*.dll    a Sony pad's own descriptor read in Sony's order (0008)
// A module that is the Wine modules' own does its part itself, and each part steps aside for it.
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
void mgf_controls_xaudio2(void);
void mgf_controls_xinput(void);
void mgf_controls_hidclass(void);
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
    mgf_controls_xaudio2();
    mgf_controls_xinput();
    mgf_controls_hidclass();
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
