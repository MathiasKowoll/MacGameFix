// Forza Horizon 6's software exception chain (engine patches 0023, 0024 and 0025), from this proxy, in the
// game's own process, instead of a replaced ntdll.dll.
//
// FH6's protection runs about 14,500 deliberate invalid instructions a second, each one an exception its own
// vectored handler steps over. Under Rosetta and Wine each costs a trip through macOS's signal, Wine's
// dispatcher and NtContinue. The chain shortens the trip: when the handler has dealt with one and the thread's
// next instruction is another invalid one of the kinds the protection uses (exception_chain/guaranteed_ud.h),
// or one a few simple instructions away (the bridge: a byte load, register arithmetic, then a jump), the
// handler is called again at once with the next exception, without leaving the dispatcher. Played A/B on
// 2026-11-25, same route: with it 58.4 frames a second and 2.4% of seconds holding a frame over 100 ms;
// without it 48.1 and 68.6%, unplayable. Its logic is the patched file's, unchanged but for the call it
// makes (exception_chain/software_exception_chain.h says how).
//
// How it is reached. Wine's dispatch_exception has the loop over the vectored handlers inlined, and calls each
// handler through a small thunk that keeps the callee-saved registers. On CrossOver Preview 41303's
// ntdll.dll, CodeWeavers' and NotProton's alike (NotProton's patch changes 8 bytes at 0x34a99 and adds a
// section), that call is at RVA 0x23ba9 (e8, to the thunk at 0x2344c), and 17 bytes of int3 padding follow the
// thunk at 0x2346f. The hook writes a jump to chain_entry into the padding, then points the call's rel32 at
// it, in one 8-byte compare-and-exchange. Every byte is checked first: any other ntdll.dll (another build, or
// MacGameFix's own FH6 ntdll.dll, which carries the chain itself) is left alone and the chain stays where it
// is. Only in the guarded FH6 build (the patch's own header guard), and only while
// WINE_SOFTWARE_EXCEPTION_CHAIN is unset or 1, as with the patch.
//
// One difference from the patch: a link calls the handler that dealt with the previous exception, not
// Wine's whole list again from its start. A handler earlier in the list (one that passed on the previous
// exception) is not asked about the next. If the handler passes the next one on, Wine's loop goes on to the
// handlers after it with that exception, as it would for a real one at that address.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef MGF_EXCEPTION_CHAIN_H
#define MGF_EXCEPTION_CHAIN_H

#include <windows.h>
#include <winternl.h>
#include <string.h>

#ifndef STATUS_VARIABLE_NOT_FOUND
#define STATUS_VARIABLE_NOT_FOUND ((NTSTATUS)0xC0000100)
#endif
#ifndef RTL_CONSTANT_STRING
#define RTL_CONSTANT_STRING(s) {sizeof(s) - sizeof((s)[0]), sizeof(s), (PWSTR)(s)}
#endif
#ifndef C_ASSERT
#define C_ASSERT(e) _Static_assert(e, #e)
#endif

NTSYSAPI PIMAGE_NT_HEADERS NTAPI RtlImageNtHeader(PVOID);
NTSYSAPI NTSTATUS NTAPI RtlQueryEnvironmentVariable_U(PWSTR, PUNICODE_STRING, PUNICODE_STRING);
NTSYSAPI BOOLEAN NTAPI RtlEqualUnicodeString(const UNICODE_STRING *, const UNICODE_STRING *, BOOLEAN);
NTSYSAPI NTSTATUS NTAPI NtReadVirtualMemory(HANDLE, const void *, void *, SIZE_T, SIZE_T *);
NTSYSAPI NTSTATUS NTAPI NtQueryPerformanceCounter(LARGE_INTEGER *, LARGE_INTEGER *);

#define MemoryBasicInformation 0
NTSYSAPI NTSTATUS NTAPI NtQueryVirtualMemory(HANDLE, PVOID, int, PVOID, SIZE_T, SIZE_T *);

// The TEB, PEB and process parameters fields the chain reads, at their x86-64 offsets: mingw's winternl.h
// keeps these structures opaque.
struct chain_parameters { BYTE reserved[0x60]; UNICODE_STRING ImagePathName; };
struct chain_peb {
    BYTE reserved0[2]; BYTE BeingDebugged; BYTE reserved1[0xd];
    void *ImageBaseAddress; void *Ldr; struct chain_parameters *ProcessParameters;
};
struct chain_teb {
    BYTE reserved0[0x40]; struct { HANDLE UniqueProcess, UniqueThread; } ClientId;
    BYTE reserved1[0x60 - 0x50]; struct chain_peb *Peb;
};
_Static_assert(__builtin_offsetof(struct chain_teb, Peb) == 0x60, "TEB.Peb");
_Static_assert(__builtin_offsetof(struct chain_peb, ProcessParameters) == 0x20, "PEB.ProcessParameters");
static struct chain_teb *chain_teb(void) { return (struct chain_teb *)NtCurrentTeb(); }

typedef LONG (*chain_thunk_t)(EXCEPTION_POINTERS *, void *);
static chain_thunk_t chain_thunk;
static LONG chain_call(EXCEPTION_POINTERS *ptrs, void *handler) { return chain_thunk(ptrs, handler); }

#define NtCurrentTeb() chain_teb()
#include "exception_chain/software_exception_chain.h"
#undef NtCurrentTeb

// Where the hook goes in CrossOver Preview 41303's ntdll.dll, and the bytes that must be there.
#define CHAIN_SITE 0x23ba1    // lea rcx,[rsp+0x50]; mov rdx,r13; call thunk; mov ebp,eax
#define CHAIN_CALL 0x23ba9
#define CHAIN_THUNK 0x2344c
#define CHAIN_PAD 0x2346f
static const BYTE chain_site_bytes[] = {0x48, 0x8d, 0x4c, 0x24, 0x50, 0x4c, 0x89, 0xea, 0xe8,
                                        0x9e, 0xf8, 0xff, 0xff, 0x89, 0xc5};
static const BYTE chain_thunk_bytes[] = {0x53, 0x56, 0x57, 0x55, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57,
                                         0x48, 0x83, 0xec, 0x28, 0xff, 0xd2, 0x48, 0x83, 0xc4, 0x28, 0x41, 0x5f,
                                         0x41, 0x5e, 0x41, 0x5d, 0x41, 0x5c, 0x5d, 0x5f, 0x5e, 0x5b, 0xc3};
#define CHAIN_PAD_SIZE 17
static volatile LONG chain_installed;

// Called by dispatch_exception, through the jump in the padding, in place of the thunk, for each handler.
static LONG chain_entry(EXCEPTION_POINTERS *ptrs, void *handler)
{
    EXCEPTION_RECORD *rec = ptrs->ExceptionRecord;
    if (rec->ExceptionCode == EXCEPTION_ILLEGAL_INSTRUCTION && software_chain_enabled())
        return call_vectored_handlers_with_chain(rec, ptrs->ContextRecord, ptrs, handler);
    return chain_thunk(ptrs, handler);
}

// 1 when the chain is in place, 0 when the game, the switch or ntdll.dll is not the one it is for. *why
// says which.
static int chain_install(const char **why)
{
    BYTE *base = (BYTE *)GetModuleHandleW(L"ntdll.dll"), pad[CHAIN_PAD_SIZE];
    IMAGE_NT_HEADERS *nt;
    DWORD old;
    LONG64 *word, before, after;
    INT32 rel;
    UINT64 target = (UINT64)(ULONG_PTR)chain_entry;
    *why = "in place";
    if (chain_installed) return 1;
    chain_thunk = (chain_thunk_t)(base + CHAIN_THUNK);
    if (!software_chain_enabled()) { *why = "not this game's build, or WINE_SOFTWARE_EXCEPTION_CHAIN is off"; return 0; }
    if (!base || !(nt = RtlImageNtHeader(base)) || nt->OptionalHeader.SizeOfImage <= CHAIN_SITE + sizeof(chain_site_bytes)) {
        *why = "no ntdll.dll to look at"; return 0;
    }
    if (memcmp(base + CHAIN_SITE, chain_site_bytes, sizeof(chain_site_bytes)) ||
        memcmp(base + CHAIN_THUNK, chain_thunk_bytes, sizeof(chain_thunk_bytes))) {
        *why = "ntdll.dll is not CrossOver Preview 41303's (or it carries the chain itself)"; return 0;
    }
    memset(pad, 0xcc, sizeof(pad));
    if (memcmp(base + CHAIN_PAD, pad, sizeof(pad))) { *why = "ntdll.dll's padding is in use"; return 0; }
    // movabs rax, chain_entry; jmp rax; the rest stays int3.
    pad[0] = 0x48; pad[1] = 0xb8; memcpy(pad + 2, &target, 8); pad[10] = 0xff; pad[11] = 0xe0;
    rel = (INT32)(CHAIN_PAD - (CHAIN_CALL + 5));
    word = (LONG64 *)(base + (CHAIN_CALL & ~7));
    if (!VirtualProtect(base + CHAIN_PAD, CHAIN_SITE + sizeof(chain_site_bytes) - CHAIN_PAD, PAGE_EXECUTE_READWRITE, &old)) {
        *why = "ntdll.dll's code could not be made writable"; return 0;
    }
    memcpy(base + CHAIN_PAD, pad, sizeof(pad));
    FlushInstructionCache(GetCurrentProcess(), base + CHAIN_PAD, sizeof(pad));
    before = *word;
    after = before;
    memcpy((BYTE *)&after + (CHAIN_CALL + 1 - (CHAIN_CALL & ~7)), &rel, 4);
    if (InterlockedCompareExchange64(word, after, before) != before) *why = "ntdll.dll's call changed under the hook";
    else chain_installed = 1;
    FlushInstructionCache(GetCurrentProcess(), word, 8);
    VirtualProtect(base + CHAIN_PAD, CHAIN_SITE + sizeof(chain_site_bytes) - CHAIN_PAD, old, &old);
    return chain_installed;
}

#endif
