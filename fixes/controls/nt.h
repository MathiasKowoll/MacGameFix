// Windows' own types, as much of them as the controls use: for ntdll.so's calls, made from the
// macOS side, and for the functions the game runs as Windows code (windows.h).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef MGF_CONTROLS_NT_H
#define MGF_CONTROLS_NT_H

#include <stdint.h>

typedef int32_t NTSTATUS;
typedef void *HANDLE;
#define STATUS_SUCCESS ((NTSTATUS)0)

typedef struct { uint32_t Data1; uint16_t Data2, Data3; uint8_t Data4[8]; } wine_guid;

struct unicode_string {
    uint16_t length, maximum_length;  // in bytes
    uint16_t *buffer;
};

struct object_attributes {
    uint32_t length;
    HANDLE root;
    struct unicode_string *name;
    uint32_t attributes;
    void *security_descriptor, *security_quality_of_service;
};

struct property_key { wine_guid fmtid; uint32_t pid; };
// The start of a PROPVARIANT: its type, and the pointer the types used here keep.
struct prop_variant { uint16_t vt, reserved[3]; void *pointer; };
#define VT_EMPTY 0
#define VT_LPWSTR 31
#define VT_CLSID 72

#define REG_SZ 1
#define REG_DWORD 4

#endif
