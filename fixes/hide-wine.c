/*
 * hide-wine.c -- hide Wine from a game's own checks, and say what it asked.
 *
 * Some titles switch a feature off when they find they run under Wine. God of
 * War Ragnarök logs "[PSN] not initialized the PSPC sdk since are running on
 * steamdeck or wine" and then never loads the PlayStation PC SDK, so its
 * libScePad (DualSense haptics and adaptive triggers) is never used, wired or
 * not. The Witcher 3 does the same with Streamline (see w3-streamout-fix.c).
 *
 * The usual check is GetProcAddress(ntdll, "wine_get_version"). This proxy
 * rides in on a DLL the executable imports (build-proxy.sh forwards every
 * export to <name>_real.dll), replaces the executable's own imports of
 * GetProcAddress and LoadLibrary*, and:
 *   - answers NULL to the executable for every export whose name starts with
 *     "wine_" (wine_get_version, wine_get_host_version, wine_get_build_id, ...),
 *     logging each caller once by its offset in the executable;
 *   - logs the libraries the executable loads by name, so a run shows whether
 *     the hidden check changed what it does next (for Ragnarök: PsPcSdk.dll,
 *     libScePad.dll).
 * Only the executable's own calls go through those imports. Ragnarök showed
 * that is not enough: it loads ntdll and kernelbase by name and finds its
 * functions itself (it never asked GetProcAddress for a wine_ name), so the
 * Wine identity exports are also renamed in place in ntdll, kernel32 and
 * kernelbase -- wine_get_version, wine_get_build_id, wine_get_host_version,
 * wine_get_unix_file_name, wine_get_dos_file_name. Each name keeps its place in
 * the sorted name table (only its last letter moves, and only between its
 * neighbours), so every other lookup still finds what it looks for. This one
 * is process-wide: anything in the game's process that asks for those names
 * afterwards is told they do not exist.
 *
 * The executable also reads environment variables (getenv, _wgetenv,
 * GetEnvironmentVariableA), and a Wine process carries WINEDEBUG, WINEPREFIX,
 * WINEDLLOVERRIDES...: every name it asks is logged once, and names starting
 * with WINE, and SteamDeck, are answered as unset.
 *
 * The executable reads the SMBIOS table too (GetSystemFirmwareTable), where a
 * Steam Deck names Valve and Jupiter/Galileo and Wine may name itself: the
 * table's strings are logged once, and "Wine" in it becomes "Dell" (same
 * length, so the structure is untouched).
 *
 * Steam: the executable gets its Steam interfaces through
 * SteamInternal_FindOrCreateUserInterface. Every version string it asks for
 * is logged, and the ISteamUtils, ISteamApps and ISteamUser objects get a copy
 * of their vtable whose entries log the method index once and jump to Steam's
 * own: nothing Steam answers is changed. ("[PSN] not initialized the PSPC sdk
 * since are running on steamdeck or wine" -- ISteamUtils can say Steam Deck.)
 *
 * mgvf-hide-wine-off.txt beside this DLL keeps the logging and stops the
 * hiding, for an A/B run. The log is C:\mgvf-hide-wine.log.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>

#define LOG_PATH "C:\\mgvf-hide-wine.log"

static FILE *logf_;
static CRITICAL_SECTION log_lock;
static BOOL hiding = TRUE;
static const unsigned char *exe_base;
static SIZE_T exe_size;

static void logline(const char *fmt, ...)
{
    va_list ap;
    if (!logf_) return;
    EnterCriticalSection(&log_lock);
    fprintf(logf_, "[%7lu ms] ", GetTickCount());
    va_start(ap, fmt);
    vfprintf(logf_, fmt, ap);
    va_end(ap);
    fputc('\n', logf_);
    fflush(logf_);
    LeaveCriticalSection(&log_lock);
}

static BOOL readable_range(const void *p, SIZE_T n);

static unsigned long offset_of(const void *p)
{
    const unsigned char *a = p;
    return (a >= exe_base && a < exe_base + exe_size) ? (unsigned long)(a - exe_base) : 0;
}

/* Each (name, caller) pair is logged once: a check in a loop would flood the log. */
#define SEEN_MAX 256
static struct { char name[48]; unsigned long at; } seen[SEEN_MAX];
static LONG seen_count;

static BOOL first_time(const char *name, unsigned long at)
{
    LONG i, n = seen_count;
    for (i = 0; i < n && i < SEEN_MAX; i++)
        if (seen[i].at == at && !strncmp(seen[i].name, name, sizeof(seen[i].name) - 1)) return FALSE;
    if (n < SEEN_MAX)
    {
        lstrcpynA(seen[n].name, name, sizeof(seen[n].name));
        seen[n].at = at;
        seen_count = n + 1;
    }
    return TRUE;
}

static void iat_hook(const char *dll, const char *name, void *repl, void **was)
{
    char *base = (char *)exe_base;
    IMAGE_NT_HEADERS *nt = (void *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_IMPORT_DESCRIPTOR *d = (void *)(base +
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    for (; d->Name; d++)
    {
        IMAGE_THUNK_DATA *names, *slots;
        if (lstrcmpiA(base + d->Name, dll)) continue;
        names = (void *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        slots = (void *)(base + d->FirstThunk);
        for (; names->u1.AddressOfData; names++, slots++)
        {
            DWORD old;
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            if (strcmp(((IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData))->Name, name)) continue;
            VirtualProtect(&slots->u1.Function, sizeof(void *), PAGE_READWRITE, &old);
            *was = (void *)slots->u1.Function;
            slots->u1.Function = (ULONG_PTR)repl;
            VirtualProtect(&slots->u1.Function, sizeof(void *), old, &old);
            logline("import %s!%s hooked", dll, name);
            return;
        }
    }
    logline("import %s!%s not found", dll, name);
}

/* Rename the export names starting with one of `prefixes` in `mod`, keeping the
 * name table sorted: the loader looks names up by binary search. */
static void hide_exports(const char *module, const char *const *prefixes)
{
    unsigned char *base = (unsigned char *)GetModuleHandleA(module);
    IMAGE_NT_HEADERS *nt;
    IMAGE_EXPORT_DIRECTORY *ed;
    DWORD *names, i, j;
    if (!base) { logline("%s not loaded, nothing to hide there", module); return; }
    nt = (void *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    if (!nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress) return;
    ed = (void *)(base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
    names = (DWORD *)(base + ed->AddressOfNames);
    for (i = 0; i < ed->NumberOfNames; i++)
    {
        char *name = (char *)(base + names[i]);
        const char *prev = i ? (const char *)(base + names[i - 1]) : NULL;
        const char *next = i + 1 < ed->NumberOfNames ? (const char *)(base + names[i + 1]) : NULL;
        size_t len;
        char was, c;
        DWORD old;
        BOOL match = FALSE;
        for (j = 0; prefixes[j]; j++)
            if (!strcmp(name, prefixes[j])) match = TRUE;
        if (!match) continue;
        len = strlen(name);
        was = name[len - 1];
        if (!VirtualProtect(name, len, PAGE_READWRITE, &old)) { logline("%s!%s: cannot write the name", module, name); continue; }
        for (c = 'A'; c <= 'z'; c++)
        {
            if (c == was) continue;
            name[len - 1] = c;
            if ((!prev || strcmp(prev, name) < 0) && (!next || strcmp(name, next) < 0)) break;
        }
        if (c > 'z') { name[len - 1] = was; logline("%s: no letter keeps the order, left alone", name); }
        else logline("%s!%.*s%c hidden (now %s)", module, (int)len - 1, name, was, name);
        VirtualProtect(name, len, old, &old);
    }
}

typedef FARPROC (WINAPI *gpa_fn)(HMODULE, LPCSTR);
static gpa_fn o_GetProcAddress;

/* scePsPcIsSupportedPlatform: its signature is not public, so the wrapper
 * passes the four argument registers through and logs what goes in and what
 * comes back (and the first bytes behind the first argument, if it points). */
typedef ULONG_PTR (*u4_fn)(ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR);
static u4_fn o_IsSupportedPlatform;
static BOOL pspc_unsupported;   /* mgvf-pspc-unsupported.txt: tell the game the SDK is unsupported */
static ULONG_PTR w_IsSupportedPlatform(ULONG_PTR a, ULONG_PTR b, ULONG_PTR c, ULONG_PTR d)
{
    ULONG_PTR r = o_IsSupportedPlatform(a, b, c, d);
    unsigned long long behind = 0;
    BOOL ptr = a > 0x10000 && readable_range((void *)a, 8);
    if (ptr) memcpy(&behind, (void *)a, 8);
    logline("scePsPcIsSupportedPlatform(0x%llx, 0x%llx) -> 0x%llx%s%llx%s", (unsigned long long)a,
            (unsigned long long)b, (unsigned long long)r, ptr ? ", first argument now points at 0x" : "",
            ptr ? behind : 0ULL, pspc_unsupported ? "; the game is told 0x8a800111 (not supported)" : "");
    /* Measured: 0, and the SDK goes on to initialise. An SCE error here makes
     * God of War Ragnarök stop with "E111000B ... Wine, Proton, and Steam Deck
     * are not supported by this application!" -- so it is off by default. */
    return pspc_unsupported ? (ULONG_PTR)0x8a800111u : r;
}

static FARPROC WINAPI p_GetProcAddress(HMODULE m, LPCSTR name)
{
    if ((ULONG_PTR)name > 0xffff && m && !strcmp(name, "scePsPcIsSupportedPlatform"))
    {
        FARPROC f = o_GetProcAddress(m, name);
        logline("GetProcAddress(PsPcSdk, scePsPcIsSupportedPlatform) at exe+0x%lx -> %p, wrapped",
                offset_of(__builtin_return_address(0)), (void *)f);
        if (!f) return f;
        o_IsSupportedPlatform = (u4_fn)f;
        return (FARPROC)w_IsSupportedPlatform;
    }
    if ((ULONG_PTR)name > 0xffff && m &&
        (m == GetModuleHandleA("PsPcSdk.dll") || m == GetModuleHandleA("libScePad.dll")))
    {
        FARPROC f = o_GetProcAddress(m, name);
        if (first_time(name, offset_of(__builtin_return_address(0))))
            logline("GetProcAddress(%s, %s) at exe+0x%lx -> %p", m == GetModuleHandleA("PsPcSdk.dll") ? "PsPcSdk" : "libScePad",
                    name, offset_of(__builtin_return_address(0)), (void *)f);
        return f;
    }
    if ((ULONG_PTR)name > 0xffff && !strncmp(name, "wine_", 5))
    {
        unsigned long at = offset_of(__builtin_return_address(0));
        if (first_time(name, at))
            logline("%s asked at exe+0x%lx: %s", name, at, hiding ? "hidden" : "answered (hiding off)");
        if (hiding) return NULL;
    }
    return o_GetProcAddress(m, name);
}

/* What the executable loads by name, to see whether hiding Wine changed its path. */
static void note_load(const char *what, const char *a, const WCHAR *w, HMODULE got)
{
    char name[MAX_PATH];
    if (w) WideCharToMultiByte(CP_UTF8, 0, w, -1, name, sizeof(name), NULL, NULL);
    else lstrcpynA(name, a ? a : "(null)", sizeof(name));
    if (first_time(name, 0)) logline("%s(%s) -> %p", what, name, (void *)got);
}

typedef HMODULE (WINAPI *lla_fn)(LPCSTR);
typedef HMODULE (WINAPI *llw_fn)(LPCWSTR);
typedef HMODULE (WINAPI *llea_fn)(LPCSTR, HANDLE, DWORD);
typedef HMODULE (WINAPI *llew_fn)(LPCWSTR, HANDLE, DWORD);
static lla_fn o_LoadLibraryA;
static llw_fn o_LoadLibraryW;
static llea_fn o_LoadLibraryExA;
static llew_fn o_LoadLibraryExW;

static HMODULE WINAPI p_LoadLibraryA(LPCSTR n) { HMODULE h = o_LoadLibraryA(n); note_load("LoadLibraryA", n, NULL, h); return h; }
static HMODULE WINAPI p_LoadLibraryW(LPCWSTR n) { HMODULE h = o_LoadLibraryW(n); note_load("LoadLibraryW", NULL, n, h); return h; }
static HMODULE WINAPI p_LoadLibraryExA(LPCSTR n, HANDLE f, DWORD fl) { HMODULE h = o_LoadLibraryExA(n, f, fl); note_load("LoadLibraryExA", n, NULL, h); return h; }
static HMODULE WINAPI p_LoadLibraryExW(LPCWSTR n, HANDLE f, DWORD fl) { HMODULE h = o_LoadLibraryExW(n, f, fl); note_load("LoadLibraryExW", NULL, n, h); return h; }

/* Environment: which variables the executable asks for, and Wine's answered as unset. */
static BOOL env_hidden(const char *name)
{
    return !_strnicmp(name, "WINE", 4) || !_stricmp(name, "SteamDeck");
}

static void note_env(const char *what, const char *name, BOOL hidden, BOOL set)
{
    char key[64];
    snprintf(key, sizeof(key), "env:%s", name);
    if (first_time(key, 0))
        logline("%s(%s): %s", what, name, hidden ? "hidden" : set ? "set" : "unset");
}

typedef char *(__cdecl *getenv_fn)(const char *);
typedef WCHAR *(__cdecl *wgetenv_fn)(const WCHAR *);
typedef DWORD (WINAPI *gev_fn)(LPCSTR, LPSTR, DWORD);
static getenv_fn o_getenv;
static wgetenv_fn o_wgetenv;
static gev_fn o_GetEnvironmentVariableA;

static char *__cdecl p_getenv(const char *name)
{
    BOOL hide = name && hiding && env_hidden(name);
    char *v = hide ? NULL : o_getenv(name);
    if (name) note_env("getenv", name, hide, v != NULL);
    return v;
}

static WCHAR *__cdecl p_wgetenv(const WCHAR *name)
{
    char n[64] = "";
    BOOL hide;
    WCHAR *v;
    if (name) WideCharToMultiByte(CP_UTF8, 0, name, -1, n, sizeof(n), NULL, NULL);
    hide = name && hiding && env_hidden(n);
    v = hide ? NULL : o_wgetenv(name);
    if (name) note_env("_wgetenv", n, hide, v != NULL);
    return v;
}

static DWORD WINAPI p_GetEnvironmentVariableA(LPCSTR name, LPSTR buf, DWORD size)
{
    BOOL hide = name && hiding && env_hidden(name);
    DWORD r;
    if (hide) { SetLastError(ERROR_ENVVAR_NOT_FOUND); r = 0; }
    else r = o_GetEnvironmentVariableA(name, buf, size);
    if (name) note_env("GetEnvironmentVariableA", name, hide, r != 0);
    return r;
}

/* SMBIOS: log the printable strings, and take "Wine" out of them. */
typedef UINT (WINAPI *gsft_fn)(DWORD, DWORD, PVOID, DWORD);
static gsft_fn o_GetSystemFirmwareTable;

static UINT WINAPI p_GetSystemFirmwareTable(DWORD provider, DWORD id, PVOID buf, DWORD size)
{
    UINT r = o_GetSystemFirmwareTable(provider, id, buf, size);
    char key[48];
    BOOL first;
    snprintf(key, sizeof(key), "fw:%08lx:%08lx:%u", (unsigned long)provider, (unsigned long)id, buf ? 1 : 0);
    first = first_time(key, 0);
    if (first)
        logline("GetSystemFirmwareTable('%c%c%c%c', 0x%lx, size %lu) -> %u", (char)(provider >> 24),
                (char)(provider >> 16), (char)(provider >> 8), (char)provider, (unsigned long)id,
                (unsigned long)size, r);
    if (buf && r && r <= size)
    {
        unsigned char *b = buf;
        UINT i, start = 0;
        int changed = 0;
        for (i = 0; i <= r; i++)
        {
            BOOL printable = i < r && b[i] >= 0x20 && b[i] < 0x7f;
            if (printable) continue;
            if (i - start >= 3 && first) logline("  string: %.*s", (int)(i - start), (char *)b + start);
            start = i + 1;
        }
        if (hiding)
            for (i = 0; i + 4 <= r; i++)
                if (!_strnicmp((char *)b + i, "wine", 4)) { memcpy(b + i, b[i] == 'W' ? "Dell" : b[i] == 'w' ? "dell" : "DELL", 4); changed++; }
        if (changed && first) logline("  %d occurrence(s) of Wine replaced", changed);
    }
    return r;
}

/* ---- Steam interfaces: which ones, and which methods ---- */

#define STEAM_SLOTS 4
#define STEAM_METHODS 64
static const char *const steam_wrapped[STEAM_SLOTS] = { "SteamUtils", "STEAMAPPS_INTERFACE", "SteamUser0", "SteamInput" };
/* Method names per slot, read from steam_api64's flat wrappers at wrap time. */
static const char *const steam_flat_prefix[STEAM_SLOTS] = { "SteamAPI_ISteamUtils_", "SteamAPI_ISteamApps_", "SteamAPI_ISteamUser_", "SteamAPI_ISteamInput_" };
static char steam_method_name[STEAM_SLOTS][64][48];
/* ISteamUtils010::IsSteamRunningOnSteamDeck, read from steam_api64's flat
 * wrapper (SteamAPI_ISteamUtils_IsSteamRunningOnSteamDeck: jmp [rax+0x110]). */
#define UTILS_IS_STEAM_DECK 34
static void **steam_orig[STEAM_SLOTS];
static void *steam_vtbl[STEAM_SLOTS][STEAM_METHODS];
static char steam_name[STEAM_SLOTS][48];
static volatile LONG steam_seen[STEAM_SLOTS][STEAM_METHODS];

/* Called by every thunk with its number (slot * 64 + method); returns Steam's own entry. */
__attribute__((used)) void *hw_note_call(int k)
{
    int slot = k / STEAM_METHODS, idx = k % STEAM_METHODS;
    if (!InterlockedExchange(&steam_seen[slot][idx], 1))
        logline("%s method %d (%s) called", steam_name[slot], idx,
                steam_method_name[slot][idx][0] ? steam_method_name[slot][idx] : "?");
    return steam_orig[slot][idx];
}

/* 256 thunks, 128 bytes apart: save the argument registers, ask hw_note_call
 * for Steam's own entry, restore, and jump to it. */
__asm__(
    ".text\n"
    ".balign 128\n"
    "hw_thunks:\n"
    ".set hwk, 0\n"
    ".rept 256\n"
    ".balign 128\n"
    "  push %rcx\n  push %rdx\n  push %r8\n  push %r9\n"
    "  sub $104, %rsp\n"
    "  movdqu %xmm0, 32(%rsp)\n  movdqu %xmm1, 48(%rsp)\n"
    "  movdqu %xmm2, 64(%rsp)\n  movdqu %xmm3, 80(%rsp)\n"
    "  mov $hwk, %ecx\n"
    "  call hw_note_call\n"
    "  movdqu 32(%rsp), %xmm0\n  movdqu 48(%rsp), %xmm1\n"
    "  movdqu 64(%rsp), %xmm2\n  movdqu 80(%rsp), %xmm3\n"
    "  add $104, %rsp\n"
    "  pop %r9\n  pop %r8\n  pop %rdx\n  pop %rcx\n"
    "  jmp *%rax\n"
    ".set hwk, hwk + 1\n"
    ".endr\n");
extern unsigned char hw_thunks[];

static BOOL readable_range(const void *p, SIZE_T n)
{
    MEMORY_BASIC_INFORMATION mbi;
    const char *a = p;
    while (n)
    {
        SIZE_T left;
        if (!VirtualQuery(a, &mbi, sizeof(mbi)) || mbi.State != MEM_COMMIT ||
            (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return FALSE;
        left = (const char *)mbi.BaseAddress + mbi.RegionSize - a;
        if (left >= n) return TRUE;
        n -= left; a += left;
    }
    return TRUE;
}

static unsigned char p_IsSteamRunningOnSteamDeck(void *self);

/* steam_api64's flat wrappers are `mov rax,[rcx]; jmp [rax+disp]`: the
 * displacement gives each method's vtable index, so the log can name it. */
/* ISteamInput006 in vtable order. The flat-wrapper reader below finds 41 of
 * these by their [rax+disp]; the rest (struct returns, six arguments) use other
 * registers, and this list, checked against the 41, fills them in. */
static const char *const steam_input006_names[] = {
    "Init",
    "Shutdown",
    "SetInputActionManifestFilePath",
    "RunFrame",
    "BWaitForData",
    "BNewDataAvailable",
    "GetConnectedControllers",
    "EnableDeviceCallbacks",
    "EnableActionEventCallbacks",
    "GetActionSetHandle",
    "ActivateActionSet",
    "GetCurrentActionSet",
    "ActivateActionSetLayer",
    "DeactivateActionSetLayer",
    "DeactivateAllActionSetLayers",
    "GetActiveActionSetLayers",
    "GetDigitalActionHandle",
    "GetDigitalActionData",
    "GetDigitalActionOrigins",
    "GetStringForDigitalActionName",
    "GetAnalogActionHandle",
    "GetAnalogActionData",
    "GetAnalogActionOrigins",
    "GetGlyphPNGForActionOrigin",
    "GetGlyphSVGForActionOrigin",
    "GetGlyphForActionOrigin_Legacy",
    "GetStringForActionOrigin",
    "GetStringForAnalogActionName",
    "StopAnalogActionMomentum",
    "GetMotionData",
    "TriggerVibration",
    "TriggerVibrationExtended",
    "TriggerSimpleHapticEvent",
    "SetLEDColor",
    "Legacy_TriggerHapticPulse",
    "Legacy_TriggerRepeatedHapticPulse",
    "ShowBindingPanel",
    "GetInputTypeForHandle",
    "GetControllerForGamepadIndex",
    "GetGamepadIndexForController",
    "GetStringForXboxOrigin",
    "GetGlyphForXboxOrigin",
    "GetActionOriginFromXboxOrigin",
    "TranslateActionOrigin",
    "GetDeviceBindingRevision",
    "GetRemotePlaySessionID",
    "GetSessionInputConfigurationSettings",
    "SetDualSenseTriggerEffect",
};

static void read_method_names(int slot)
{
    unsigned char *base = (unsigned char *)GetModuleHandleA("steam_api64.dll");
    IMAGE_NT_HEADERS *nt;
    IMAGE_EXPORT_DIRECTORY *ed;
    DWORD *names, *funcs, i;
    WORD *ords;
    size_t plen = strlen(steam_flat_prefix[slot]);
    if (slot == 3 && !strcmp(steam_name[3], "SteamInput006"))
    {
        for (i = 0; i < sizeof(steam_input006_names) / sizeof(steam_input006_names[0]); i++)
            lstrcpynA(steam_method_name[3][i], steam_input006_names[i], sizeof(steam_method_name[3][0]));
        return;
    }
    if (!base) return;
    nt = (void *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    ed = (void *)(base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
    names = (DWORD *)(base + ed->AddressOfNames);
    funcs = (DWORD *)(base + ed->AddressOfFunctions);
    ords = (WORD *)(base + ed->AddressOfNameOrdinals);
    for (i = 0; i < ed->NumberOfNames; i++)
    {
        const char *n = (const char *)(base + names[i]);
        const unsigned char *c;
        long disp = -1;
        if (strncmp(n, steam_flat_prefix[slot], plen)) continue;
        c = base + funcs[ords[i]];
        if (!readable_range(c, 48)) continue;
        {
            /* After `mov rax,[rcx]` (48 8b 01), the first [rax+disp] operand of
             * a call/jmp (ff /2, ff /4) or a mov (4x 8b) is the vtable slot. */
            int k, start = -1;
            for (k = 0; k + 3 <= 24; k++)
                if (c[k] == 0x48 && c[k + 1] == 0x8b && c[k + 2] == 0x01) { start = k + 3; break; }
            for (k = start; start >= 0 && k + 6 <= 48; k++)
            {
                unsigned char op = c[k], m = c[k + 1];
                BOOL rax_rm = (m & 7) == 0 && ((m >> 6) == 1 || (m >> 6) == 2);
                if (op == 0xff && m == 0x20) { disp = 0; break; }   /* jmp [rax]: slot 0 */
                BOOL hit = rax_rm && ((op == 0xff && (((m >> 3) & 7) == 2 || ((m >> 3) & 7) == 4)) ||
                                      (op == 0x8b && k > start && (c[k - 1] & 0xf0) == 0x40));
                if (!hit) continue;
                disp = (m >> 6) == 1 ? (long)c[k + 2] : (long)*(const int *)(c + k + 2);
                break;
            }
        }
        if (disp >= 0 && disp % 8 == 0 && disp / 8 < STEAM_METHODS)
            lstrcpynA(steam_method_name[slot][disp / 8], n + plen, sizeof(steam_method_name[slot][0]));
    }
}

static void wrap_interface(void *obj, const char *version)
{
    int slot, i;
    void ***self = obj;
    for (slot = 0; slot < STEAM_SLOTS; slot++)
        if (!strncmp(version, steam_wrapped[slot], strlen(steam_wrapped[slot]))) break;
    if (slot == STEAM_SLOTS || !obj) return;
    if (*self == steam_vtbl[slot]) return;          /* already ours */
    if (steam_orig[slot]) { logline("%s: a second object, left alone", version); return; }
    if (!readable_range(*self, STEAM_METHODS * sizeof(void *))) { logline("%s: vtable not readable", version); return; }
    steam_orig[slot] = *self;
    lstrcpynA(steam_name[slot], version, sizeof(steam_name[slot]));
    read_method_names(slot);
    for (i = 0; i < STEAM_METHODS; i++)
        steam_vtbl[slot][i] = hw_thunks + (slot * STEAM_METHODS + i) * 128;
    if (slot == 0 && !strcmp(version, "SteamUtils010"))
        steam_vtbl[0][UTILS_IS_STEAM_DECK] = (void *)p_IsSteamRunningOnSteamDeck;
    *self = steam_vtbl[slot];
    logline("%s: methods are logged", version);
}

/* With mgvf-deck-no.txt beside this DLL every caller is told "not a Steam
 * Deck", except the hex offsets listed in mgvf-deck-keep-at.txt; without it,
 * Steam's own answer passes through and is only logged. */
static unsigned long deck_keep_at[16];
static BOOL deck_no;   /* mgvf-deck-no.txt: tell the game it is not on a Steam Deck */
static int deck_keep_count;

typedef unsigned char (*deck_fn)(void *);
static unsigned char p_IsSteamRunningOnSteamDeck(void *self)
{
    unsigned char r = ((deck_fn)steam_orig[0][UTILS_IS_STEAM_DECK])(self);
    unsigned long at = offset_of(__builtin_return_address(0));
    BOOL keep = !deck_no;
    int i;
    for (i = 0; i < deck_keep_count; i++) if (deck_keep_at[i] == at) keep = TRUE;
    if (first_time("IsSteamRunningOnSteamDeck", at))
        logline("IsSteamRunningOnSteamDeck asked at exe+0x%lx: Steam says %s, the game is told %s",
                at, r ? "yes" : "no", keep ? (r ? "yes" : "no") : "no");
    return keep ? r : 0;
}

typedef void *(__cdecl *find_iface_fn)(int, const char *);
static find_iface_fn o_FindOrCreateUserInterface;

static void *__cdecl p_FindOrCreateUserInterface(int user, const char *version)
{
    void *obj = o_FindOrCreateUserInterface(user, version);
    if (version && first_time(version, 1)) logline("Steam interface %s -> %p", version, obj);
    if (version && obj) wrap_interface(obj, version);
    return obj;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    char path[MAX_PATH + 32];
    DWORD n;
    char *slash;
    IMAGE_NT_HEADERS *nt;
    (void)reserved;
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(inst);
    InitializeCriticalSection(&log_lock);
    logf_ = fopen(LOG_PATH, "w");

    n = GetModuleFileNameA(inst, path, MAX_PATH);
    slash = n ? strrchr(path, '\\') : NULL;
    if (slash)
    {
        FILE *f;
        strcpy(slash + 1, "mgvf-hide-wine-off.txt");
        hiding = GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES;
        strcpy(slash + 1, "mgvf-deck-no.txt");
        deck_no = GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
        strcpy(slash + 1, "mgvf-pspc-unsupported.txt");
        pspc_unsupported = GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
        strcpy(slash + 1, "mgvf-deck-keep-at.txt");
        if ((f = fopen(path, "r")))
        {
            char tok[32];
            while (deck_keep_count < 16 && fscanf(f, "%31s", tok) == 1)
            {
                char *end;
                unsigned long v = strtoul(tok, &end, 16);
                if (*end == 0) deck_keep_at[deck_keep_count++] = v;
            }
            fclose(f);
        }
    }
    exe_base = (const unsigned char *)GetModuleHandleA(NULL);
    nt = (void *)(exe_base + ((IMAGE_DOS_HEADER *)exe_base)->e_lfanew);
    exe_size = nt->OptionalHeader.SizeOfImage;
    GetModuleFileNameA(NULL, path, MAX_PATH);
    logline("hide-wine loaded into %s, hiding %s", path, hiding ? "on" : "off (mgvf-hide-wine-off.txt)");

    iat_hook("KERNEL32.dll", "GetProcAddress", (void *)p_GetProcAddress, (void **)&o_GetProcAddress);
    iat_hook("KERNEL32.dll", "LoadLibraryA", (void *)p_LoadLibraryA, (void **)&o_LoadLibraryA);
    iat_hook("KERNEL32.dll", "LoadLibraryW", (void *)p_LoadLibraryW, (void **)&o_LoadLibraryW);
    iat_hook("KERNEL32.dll", "LoadLibraryExA", (void *)p_LoadLibraryExA, (void **)&o_LoadLibraryExA);
    iat_hook("KERNEL32.dll", "LoadLibraryExW", (void *)p_LoadLibraryExW, (void **)&o_LoadLibraryExW);
    iat_hook("api-ms-win-crt-environment-l1-1-0.dll", "getenv", (void *)p_getenv, (void **)&o_getenv);
    iat_hook("api-ms-win-crt-environment-l1-1-0.dll", "_wgetenv", (void *)p_wgetenv, (void **)&o_wgetenv);
    iat_hook("KERNEL32.dll", "GetEnvironmentVariableA", (void *)p_GetEnvironmentVariableA, (void **)&o_GetEnvironmentVariableA);
    iat_hook("steam_api64.dll", "SteamInternal_FindOrCreateUserInterface", (void *)p_FindOrCreateUserInterface,
             (void **)&o_FindOrCreateUserInterface);
    iat_hook("KERNEL32.dll", "GetSystemFirmwareTable", (void *)p_GetSystemFirmwareTable, (void **)&o_GetSystemFirmwareTable);
    if (!o_GetSystemFirmwareTable) o_GetSystemFirmwareTable = GetSystemFirmwareTable;
    if (!o_getenv) o_getenv = getenv;
    if (!o_wgetenv) o_wgetenv = _wgetenv;
    if (!o_GetEnvironmentVariableA) o_GetEnvironmentVariableA = GetEnvironmentVariableA;
    if (hiding)
    {
        static const char *const identity[] = { "wine_get_version", "wine_get_build_id",
            "wine_get_host_version", "wine_get_unix_file_name", "wine_get_dos_file_name", NULL };
        hide_exports("ntdll.dll", identity);
        hide_exports("kernel32.dll", identity);
        hide_exports("kernelbase.dll", identity);
    }
    if (!o_GetProcAddress) o_GetProcAddress = (gpa_fn)GetProcAddress;
    if (!o_LoadLibraryA) o_LoadLibraryA = LoadLibraryA;
    if (!o_LoadLibraryW) o_LoadLibraryW = LoadLibraryW;
    if (!o_LoadLibraryExA) o_LoadLibraryExA = LoadLibraryExA;
    if (!o_LoadLibraryExW) o_LoadLibraryExW = LoadLibraryExW;
    return TRUE;
}
