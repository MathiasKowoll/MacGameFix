// The Windows side of the controls, from the library: a Windows module as Wine has just mapped
// it, its exports, and an export pointed at code of ours.
//
// The Wine modules change six Windows files for the pad (winebus.sys, mmdevapi.dll, hidclass.sys,
// xinput*.dll, setupapi.dll, xaudio2_9.dll). In a runner that keeps CodeWeavers' own, each of
// those changes is made here in memory instead, in the processes of a game whose row is on.
//
// Wine's loader maps every DLL with NtMapViewOfSection. This takes that entry of ntdll.so's
// syscall table (as mgf-engine's package-family does for kernel32) and, when a module asked for
// by name has been mapped, calls the part that changes it, before the loader binds any import to
// it. An export is pointed elsewhere by its entry in the export directory's function array: the
// new target has to be within 4 GB above the image, as that entry is an RVA, so a part writes
// its code into memory taken there (pe_room).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_PE_H
#define MGF_CONTROLS_PE_H

#include <mach-o/loader.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct np_plugin_api;

// A 64-bit Windows image where Wine mapped it.
struct pe_image {
    uint8_t *base;
    uint32_t size;  // SizeOfImage
};

typedef void (*pe_mapped_fn)(const struct pe_image *image);

// `fn` is called each time a module whose export directory names `dll` is mapped. Before pe_arm.
void pe_on_map(const char *dll, pe_mapped_fn fn);
// Called with ntdll.so, when it has loaded.
void pe_arm(const struct np_plugin_api *api, const struct mach_header_64 *ntdll, intptr_t slide);

// Where an export's code is; NULL when the module has none by that name or forwards it.
uint8_t *pe_export(const struct pe_image *image, const char *name);
// Writable memory within 4 GB above the image; NULL when there is none.
uint8_t *pe_room(const struct pe_image *image, size_t size);
// That memory made to run (and no longer written).
bool pe_runs(uint8_t *room, size_t size);
// The export's entry pointed at `target`, which pe_room gave.
bool pe_point_export(const struct pe_image *image, const char *name, const uint8_t *target);

// For a change that no export reaches (a COM method, found by what its table holds):
// The image's sections, one at a time; false past the last. `code`: the section holds code.
bool pe_section(const struct pe_image *image, unsigned index, uint8_t **start, uint32_t *size, bool *code);
// How many bytes of code there are from `at` to the end of its section; 0 when `at` is not code.
uint32_t pe_code(const struct pe_image *image, const uint8_t *at);
// Where the loader puts the address of `name`, imported from `dll`, when it binds the image's
// imports (after the module's part is called); NULL when the image does not import it by name.
uintptr_t *pe_import_slot(const struct pe_image *image, const char *dll, const char *name);
// The same for the first thing the image imports from `dll`, whatever it is: an address inside
// that module, to find the module by.
uintptr_t *pe_import_first(const struct pe_image *image, const char *dll);
// A pointer inside the image changed, whatever its page's protection.
bool pe_write_pointer(uintptr_t *slot, uintptr_t value);

#endif
