// What mmdevapi.c, in the game's Windows code, asks of audio.c, on the macOS side: the container
// of an audio endpoint.
//
// The question goes the way mmdevapi's own go: through Wine's unix call dispatcher, to
// winecoreaudio.so's get_prop_value, which audio.c has taken. It is told from one of Wine's by
// its first field: Wine's starts with the device's name, this with the address of a tag.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_MMDEVAPI_H
#define MGF_CONTROLS_MMDEVAPI_H

#include <stdint.h>

typedef struct { uint32_t Data1; uint16_t Data2, Data3; uint8_t Data4[8]; } wine_guid;
struct property_key { wine_guid fmtid; uint32_t pid; };
// The start of a PROPVARIANT: its type, and the pointer the types used here keep.
struct prop_variant { uint16_t vt, reserved[3]; void *pointer; };

#define VT_EMPTY 0
#define VT_LPWSTR 31
#define VT_CLSID 72

#define UNIX_GET_PROP_VALUE 29  // its index in winecoreaudio.so's __wine_unix_call_funcs

struct mgf_container_request {
    const void *tag;     // &mgf_container_request_tag
    uint16_t *endpoint;  // the endpoint's GUID as text, "{...}"; when found, its container instead: 16 bytes
    int found;
};

extern const char mgf_container_request_tag;
// winecoreaudio.so's __wine_unix_call_funcs once audio.c has taken its get_prop_value: the handle
// Wine's dispatcher is called with. 0 until then, and for good where that file is MacGameFix's own.
extern uintptr_t mgf_audio_unix_handle;

#endif
