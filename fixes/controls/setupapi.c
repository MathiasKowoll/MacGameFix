// setupapi.dll: a device's base container id comes back as WCHAR from the ANSI function too.
// What engine patch 0010 does in the Wine modules' setupapi.dll, done here on CodeWeavers' own.
//
// Windows returns SPDRP_BASE_CONTAINERID as a WCHAR string from
// SetupDiGetDeviceRegistryPropertyA as well as from the W one (Wine's ntoskrnl tests read it
// with the W one for that reason); Wine converts it to ANSI like any other string. A game that
// reads a pad's container with one function and an audio endpoint's with the other compares two
// WCHAR strings: Nioh 3 does, and never finds the pad's output when this one is ANSI.
//
// When setupapi.dll is mapped, its export SetupDiGetDeviceRegistryPropertyA is pointed at a few
// instructions that send that one property to the W function and everything else to the
// function as it was. Both take the same arguments in the same places, so they are jumped to
// with the caller's untouched. A setupapi.dll that already answers so (the Wine modules') gives
// the same answer through this.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pe.h"
#include "pad.h"

#define SPDRP_BASE_CONTAINERID 0x24

#if defined(__x86_64__)
static void mapped(const struct pe_image *image) {
    // BOOL SetupDiGetDeviceRegistryPropertyA(HDEVINFO, SP_DEVINFO_DATA *, DWORD property, ...): the
    // Windows x64 convention has the property in r8d.
    unsigned char code[] = {
        0x41, 0x83, 0xf8, SPDRP_BASE_CONTAINERID,    //  0: cmp  r8d, SPDRP_BASE_CONTAINERID
        0x75, 0x0c,                                  //  4: jne  ansi (18)
        0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0,          //  6: mov  rax, the W function
        0xff, 0xe0,                                  // 16: jmp  rax
        0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0,          // 18: ansi: mov rax, the A function as it was
        0xff, 0xe0,                                  // 28: jmp  rax
    };
    static int told;
    uint8_t *ansi = pe_export(image, "SetupDiGetDeviceRegistryPropertyA");
    uint8_t *wide = pe_export(image, "SetupDiGetDeviceRegistryPropertyW");
    uint8_t *room;

    if (!ansi || !wide) {
        pad_log("controls: setupapi.dll has no SetupDiGetDeviceRegistryProperty to point elsewhere, left as it is\n");
        return;
    }
    if (!(room = pe_room(image, sizeof(code)))) {
        pad_log("controls: no memory free within 4 GB above setupapi.dll, left as it is\n");
        return;
    }
    memcpy(code + 8, &wide, 8);
    memcpy(code + 20, &ansi, 8);
    memcpy(room, code, sizeof(code));
    if (!pe_runs(room, sizeof(code)) || !pe_point_export(image, "SetupDiGetDeviceRegistryPropertyA", room)) {
        pad_log("controls: setupapi.dll could not be written, left as it is\n");
        return;
    }
    if (!__atomic_exchange_n(&told, 1, __ATOMIC_RELAXED))
        pad_log("controls: setupapi.dll answers a device's base container id in WCHAR from the ANSI function too\n");
}
#endif

void mgf_controls_setupapi(void) {
#if defined(__x86_64__)
    pe_on_map("setupapi.dll", mapped);
#endif
}
