// unwindguard: containment for Wine's ntdll RtlVirtualUnwind2 / RtlVirtualUnwind faulting on foreign thread contexts.
// FH5's stack-walking thread (hang watchdog) unwinds other threads' contexts; in Wine's UWOP_PUSH_MACHFRAME path
// the unwinder reads/writes through garbage pointers (e.g. READ at ntdll+0x3BDEC, mov (%r15),%rax). Instead of
// letting that kill the process, a first-chance VEH unwinds ONE frame out of the faulting unwinder and makes the
// call return a failure (STATUS_ACCESS_VIOLATION from RtlVirtualUnwind2, NULL handler from RtlVirtualUnwind).
//
// Code ranges (computed at runtime, ntdll is relocated): the RUNTIME_FUNCTION entry covering each export
// (RtlLookupFunctionEntry), plus every .pdata entry whose UNW_FLAG_CHAININFO chain leads back to it (hot/cold
// splits). On the Highball ntdll RtlVirtualUnwind2 is ONE entry [0x3B1A0,0x3C3F4), so no window is needed.
// HB_UNWINDGUARD=0 disables registration.
#ifndef UNWINDGUARD_H
#define UNWINDGUARD_H
#include <windows.h>
#include <stdio.h>

typedef struct { ULONG_PTR lo, hi; } ug_rng;
static ULONG_PTR ug_nt_lo, ug_nt_hi;
static ug_rng ug_r1[8], ug_r2[8];
static int ug_n1, ug_n2;
static DWORD ug_tls = TLS_OUT_OF_INDEXES;
static volatile LONG ug_count;
static HANDLE ug_logh = INVALID_HANDLE_VALUE;

static int ug_in(const ug_rng *r, int n, ULONG_PTR a)
{
    for (int i = 0; i < n; i++) if (a >= r[i].lo && a < r[i].hi) return 1;
    return 0;
}

extern int hb_debug;   // d3d12.c: HB_DEBUG=1
static void ug_log(const char *fn, EXCEPTION_POINTERS *ep, ULONG_PTR caller)
{
    LONG n;
    char b[256]; DWORD w; int len;
    if (!hb_debug) return;   // play build: the guard still swallows the fault, it just does not log it
    n = InterlockedIncrement(&ug_count);
    if (!(n <= 20 || n % 100 == 0)) return;
    if (ug_logh == INVALID_HANDLE_VALUE) {
        char path[64];
        CreateDirectoryA("C:\\highball", NULL); CreateDirectoryA("C:\\highball\\logs", NULL);
        snprintf(path, sizeof path, "C:\\highball\\logs\\unwindguard-%lu.log", GetCurrentProcessId());
        HANDLE h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, 0, NULL);
        if (InterlockedCompareExchangePointer(&ug_logh, h, INVALID_HANDLE_VALUE) != INVALID_HANDLE_VALUE && h != INVALID_HANDLE_VALUE) CloseHandle(h);
    }
    if (ug_logh == INVALID_HANDLE_VALUE) return;
    len = snprintf(b, sizeof b, "#%ld tick=%llu tid=%lu fn=%s rip=ntdll+0x%llX addr=0x%llX %s caller=%p\r\n", (long)n,
        (unsigned long long)GetTickCount64(), GetCurrentThreadId(), fn,
        (unsigned long long)(ep->ContextRecord->Rip - ug_nt_lo), (unsigned long long)ep->ExceptionRecord->ExceptionInformation[1],
        ep->ExceptionRecord->ExceptionInformation[0] == 0 ? "READ" : ep->ExceptionRecord->ExceptionInformation[0] == 1 ? "WRITE" : "DEP",
        (void *)caller);
    if (len > 0) WriteFile(ug_logh, b, (DWORD)len, &w, NULL);
}

// unwind one frame of c in place; returns 0 on failure
static int ug_unwind1(CONTEXT *c)
{
    DWORD64 base, frame = 0; PVOID hd = NULL;
    PRUNTIME_FUNCTION rf = RtlLookupFunctionEntry(c->Rip, &base, NULL);
    if (!rf) return 0;
    RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, c->Rip, rf, c, &hd, &frame, NULL);
    return 1;
}

static LONG CALLBACK ug_guard(EXCEPTION_POINTERS *ep)
{
    ULONG_PTR rip;
    int which;
    CONTEXT c;
    ULONG_PTR caller;
    // fast path: a couple of compares (the game's anti-tamper raises ~14k exceptions/s)
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    rip = (ULONG_PTR)ep->ContextRecord->Rip;
    if (rip < ug_nt_lo || rip >= ug_nt_hi) return EXCEPTION_CONTINUE_SEARCH;
    if (ug_in(ug_r2, ug_n2, rip)) which = 2;
    else if (ug_in(ug_r1, ug_n1, rip)) which = 1;
    else return EXCEPTION_CONTINUE_SEARCH;
    if (TlsGetValue(ug_tls)) return EXCEPTION_CONTINUE_SEARCH;       // re-entered
    TlsSetValue(ug_tls, (LPVOID)1);
    c = *ep->ContextRecord;
    if (!ug_unwind1(&c)) goto pass;
    caller = (ULONG_PTR)c.Rip;
    if (caller >= ug_nt_lo && caller < ug_nt_hi) {
        // called from inside ntdll: only the exported RtlVirtualUnwind wrapper is ours to skip
        if (which != 2 || !ug_in(ug_r1, ug_n1, caller)) goto pass;
        which = 1;
        if (!ug_unwind1(&c)) goto pass;
        caller = (ULONG_PTR)c.Rip;
        if (caller >= ug_nt_lo && caller < ug_nt_hi) goto pass;
        c.Rax = 0;
    } else {
        c.Rax = (which == 2) ? 0xC0000005ull : 0;
    }
    ug_log(which == 2 ? "RtlVirtualUnwind2" : "RtlVirtualUnwind", ep, caller);
    *ep->ContextRecord = c;
    TlsSetValue(ug_tls, NULL);
    return EXCEPTION_CONTINUE_EXECUTION;
pass:
    TlsSetValue(ug_tls, NULL);
    return EXCEPTION_CONTINUE_SEARCH;
}

static void ug_add_ranges(BYTE *base, ULONG_PTR p, ug_rng *out, int *n)
{
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY *d = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION];
    RUNTIME_FUNCTION *t = (RUNTIME_FUNCTION *)(base + d->VirtualAddress);
    DWORD cnt = d->Size / sizeof(RUNTIME_FUNCTION), rva = (DWORD)(p - (ULONG_PTR)base), i;
    DWORD seed_lo = 0, seed_hi = 0;
    for (i = 0; i < cnt; i++) if (rva >= t[i].BeginAddress && rva < t[i].EndAddress) { seed_lo = t[i].BeginAddress; seed_hi = t[i].EndAddress; break; }
    if (!seed_hi) return;
    out[(*n)].lo = (ULONG_PTR)base + seed_lo; out[(*n)++].hi = (ULONG_PTR)base + seed_hi;
    for (i = 0; i < cnt && *n < 8; i++) {                         // chained (hot/cold split) entries leading back to the seed
        RUNTIME_FUNCTION *rf = &t[i]; int lvl;
        if (rf->BeginAddress == seed_lo) continue;
        for (lvl = 0; lvl < 8; lvl++) {
            BYTE *ui = base + (rf->UnwindData & ~3u);
            if (!(ui[0] & (4 << 3))) break;                       // UNW_FLAG_CHAININFO
            rf = (RUNTIME_FUNCTION *)(ui + 4 + ((ui[2] + 1) & ~1) * 2);
            if (rf->BeginAddress == seed_lo) { out[*n].lo = (ULONG_PTR)base + t[i].BeginAddress; out[(*n)++].hi = (ULONG_PTR)base + t[i].EndAddress; break; }
        }
    }
}

static void ug_init(void)
{
    char v[8]; HMODULE h; ULONG_PTR p1, p2; IMAGE_NT_HEADERS *nt;
    if (GetEnvironmentVariableA("HB_UNWINDGUARD", v, sizeof v) == 1 && v[0] == '0') return;
    h = GetModuleHandleA("ntdll.dll"); if (!h) return;
    p2 = (ULONG_PTR)GetProcAddress(h, "RtlVirtualUnwind2");
    p1 = (ULONG_PTR)GetProcAddress(h, "RtlVirtualUnwind");
    if (!p2 && !p1) return;
    nt = (IMAGE_NT_HEADERS *)((BYTE *)h + ((IMAGE_DOS_HEADER *)h)->e_lfanew);
    ug_nt_lo = (ULONG_PTR)h; ug_nt_hi = ug_nt_lo + nt->OptionalHeader.SizeOfImage;
    if (p2) ug_add_ranges((BYTE *)h, p2, ug_r2, &ug_n2);
    if (p1) ug_add_ranges((BYTE *)h, p1, ug_r1, &ug_n1);
    if (!ug_n2 && !ug_n1) return;
    ug_tls = TlsAlloc(); if (ug_tls == TLS_OUT_OF_INDEXES) return;
    AddVectoredExceptionHandler(1, ug_guard);
}
#endif
