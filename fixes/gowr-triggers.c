/*
 * gowr-triggers.c -- God of War Ragnarök's adaptive triggers on a DualSense under Wine.
 *
 * Under Wine, Steam answers that the game runs on a Steam Deck, so the game never
 * loads Sony's library (libScePad): every trigger effect it builds goes to its
 * scePadSetTriggerEffect wrapper (exe+0x695580), which answers 0x8a80010d and drops
 * it. Measured with gowr-trigger-probe on 2026-10-23: 979 effects in eight minutes,
 * all L2 VIBRATION, every one dropped.
 *
 * This proxy rides in on bink2w64.dll (build-proxy.sh forwards every export to
 * bink2w64_real.dll), finds the wrapper by the name it hands on (find_wrapper), and
 * puts a jump at it. The replacement turns Sony's ScePadTriggerEffectParam into the
 * DualSense's trigger effect bytes and writes them to the pad as an output report
 * 0x02 carrying only the trigger fields (valid_flag0 0x04 R2, 0x08 L2), so the
 * rumble Steam or XInput writes is left alone. It answers the game what the
 * original answers, so the game behaves as before. The Wine modules see a trigger
 * effect written by the game and leave that trigger to it.
 *
 * A pad is looked for once, on the first effect: a HID game pad with Sony's vendor
 * id and the DualSense's or the Edge's product id whose output report is the wired
 * one (48 bytes), which is what the Wine modules show with bluetooth=wired. Without
 * one, nothing is written. On ExitProcess both triggers it set are released.
 *
 * Log: gowr-triggers.log beside the executable. Made from gowr-trigger-probe's
 * findings; the probe is not shipped.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define RETURN_NOT_LOADED   0x8a80010du
#define LOG_NAME            "gowr-triggers.log"

/* The wrapper is found, not addressed: the one function whose code loads the
 * address of the string "scePadSetTriggerEffect" (it hands the name to an
 * optional hook) and starts as the wrapper of build 0x6859ad47 does, up to its
 * first call. Measured on that build: one such string, one such reference, at
 * exe+0x6955bb inside the wrapper at exe+0x695580. A build that changed this
 * code finds nothing and is left untouched. */
static const unsigned char wrapper_start[21] = {
    0x48, 0x89, 0x5c, 0x24, 0x08,       /* mov [rsp+8], rbx */
    0x48, 0x89, 0x74, 0x24, 0x10,       /* mov [rsp+0x10], rsi */
    0x57,                               /* push rdi */
    0x48, 0x83, 0xec, 0x20,             /* sub rsp, 0x20 */
    0x48, 0x8b, 0xfa,                   /* mov rdi, rdx */
    0x8b, 0xf1,                         /* mov esi, ecx */
    0xe8,                               /* call ... */
};

/* ScePadTriggerEffectParam: triggerMask (bit0 L2, bit1 R2) at 0, then command[2]
 * (L2, R2) at 0x08 and 0x40: mode u32, 4 bytes padding, the mode's parameters. */
#define CMD_FIRST 0x08
#define CMD_SIZE  0x38
#define CMD_PARAM 0x08
#define PARAM_SIZE (CMD_FIRST + 2 * CMD_SIZE)

enum { MODE_OFF, MODE_FEEDBACK, MODE_WEAPON, MODE_VIBRATION, MODE_MULTI_FEEDBACK, MODE_SLOPE, MODE_MULTI_VIBRATION };

static uint8_t *g_exe;
static HANDLE g_log = INVALID_HANDLE_VALUE;
static CRITICAL_SECTION g_lock;
static HANDLE g_pad = INVALID_HANDLE_VALUE;
static USHORT g_out_len;
static int g_pad_looked;
static uint8_t g_last[2][11];        /* what each trigger was last given: [0] R2, [1] L2 */
static int g_set[2];
static LONG g_effects, g_writes, g_failed;

__attribute__((format(printf, 1, 2))) static void logline(const char *fmt, ...)
{
    char line[512];
    SYSTEMTIME st;
    va_list ap;
    int n;
    DWORD w;
    if (g_log == INVALID_HANDLE_VALUE) return;
    GetLocalTime(&st);
    n = snprintf(line, sizeof(line), "[%02u:%02u:%02u.%03u] ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_start(ap, fmt);
    n += vsnprintf(line + n, sizeof(line) - 2 - n, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof(line) - 2) n = sizeof(line) - 2;
    line[n++] = '\n';
    WriteFile(g_log, line, (DWORD)n, &w, NULL);
}

/* The DualSense's 11 bytes from strengths 1-8 per zone (0 = none), the way the
 * Wine modules build them: 0x21 zones of resistance, or 0x26 vibration. */
static void zones(const uint8_t strengths[10], uint8_t mode, uint8_t frequency, uint8_t out[11])
{
    uint16_t z = 0;
    uint32_t forces = 0;
    int i;
    memset(out, 0, 11);
    for (i = 0; i < 10; i++)
        if (strengths[i] >= 1 && strengths[i] <= 8)
        {
            z |= 1u << i;
            forces |= (uint32_t)(strengths[i] - 1) << (3 * i);
        }
    if (!z || (mode == 0x26 && !frequency)) { out[0] = 0x05; return; }
    out[0] = mode;
    out[1] = z & 0xff;
    out[2] = z >> 8;
    for (i = 0; i < 4; i++) out[3 + i] = (uint8_t)(forces >> (8 * i));
    if (mode == 0x26) out[9] = frequency;
}

static void convert(uint32_t mode, const uint8_t *p, uint8_t out[11])
{
    uint8_t s[10] = {0};
    int i;
    switch (mode)
    {
    case MODE_FEEDBACK:      /* position 0-9, strength 1-8 */
        for (i = p[0]; i < 10; i++) s[i] = p[1];
        zones(s, 0x21, 0, out);
        return;
    case MODE_WEAPON:        /* start 2-7, end start+1-8, strength 1-8 */
        memset(out, 0, 11);
        if (p[0] > 9 || p[1] > 9 || p[1] <= p[0] || !p[2] || p[2] > 8) { out[0] = 0x05; return; }
        out[0] = 0x25;
        out[1] = ((1u << p[0]) | (1u << p[1])) & 0xff;
        out[2] = ((1u << p[0]) | (1u << p[1])) >> 8;
        out[3] = p[2] - 1;
        return;
    case MODE_VIBRATION:     /* position 0-9, amplitude 1-8, frequency in Hz */
        for (i = p[0]; i < 10; i++) s[i] = p[1];
        zones(s, 0x26, p[2], out);
        return;
    case MODE_MULTI_FEEDBACK:  /* strength[10] */
        zones(p, 0x21, 0, out);
        return;
    case MODE_SLOPE:         /* start, end, start strength, end strength */
        if (p[1] > p[0] && p[1] <= 9)
            for (i = p[0]; i < 10; i++)
                s[i] = i >= p[1] ? p[3] : (uint8_t)(p[2] + (int)(p[3] - p[2]) * (i - p[0]) / (p[1] - p[0]));
        zones(s, 0x21, 0, out);
        return;
    case MODE_MULTI_VIBRATION: /* frequency, amplitude[10] */
        zones(p + 1, 0x26, p[0], out);
        return;
    default:
        memset(out, 0, 11);
        out[0] = 0x05;
    }
}

typedef BOOLEAN (WINAPI *hidd_attr_fn)(HANDLE, void *);
typedef void (WINAPI *hidd_guid_fn)(GUID *);
typedef BOOLEAN (WINAPI *hidd_pp_fn)(HANDLE, void **);
typedef BOOLEAN (WINAPI *hidd_free_fn)(void *);
typedef LONG (WINAPI *hidp_caps_fn)(void *, void *);
typedef void *(WINAPI *sdi_classdevs_fn)(const GUID *, const WCHAR *, HWND, DWORD);
typedef BOOL (WINAPI *sdi_enum_fn)(void *, void *, const GUID *, DWORD, void *);
typedef BOOL (WINAPI *sdi_detail_fn)(void *, void *, void *, DWORD, DWORD *, void *);
typedef BOOL (WINAPI *sdi_destroy_fn)(void *);

struct hid_attributes { ULONG Size; USHORT VendorID, ProductID, VersionNumber; };
struct hidp_caps { USHORT Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength, Reserved[17], rest[10]; };
struct sp_interface { DWORD cbSize; GUID InterfaceClassGuid; DWORD Flags; ULONG_PTR Reserved; };

/* The pad, found once. Not under the loader lock: the first effect comes long after. */
static void find_pad(void)
{
    HMODULE hid = LoadLibraryW(L"hid.dll"), sdi = LoadLibraryW(L"setupapi.dll");
    hidd_guid_fn guid_fn; hidd_attr_fn attr_fn; hidd_pp_fn pp_fn; hidd_free_fn free_fn; hidp_caps_fn caps_fn;
    sdi_classdevs_fn classdevs; sdi_enum_fn enum_if; sdi_detail_fn detail; sdi_destroy_fn destroy;
    GUID g;
    void *set;
    DWORD i;
    int seen = 0;

    g_pad_looked = 1;
    if (!hid || !sdi) { logline("pad: hid.dll or setupapi.dll did not load"); return; }
    guid_fn = (hidd_guid_fn)GetProcAddress(hid, "HidD_GetHidGuid");
    attr_fn = (hidd_attr_fn)GetProcAddress(hid, "HidD_GetAttributes");
    pp_fn = (hidd_pp_fn)GetProcAddress(hid, "HidD_GetPreparsedData");
    free_fn = (hidd_free_fn)GetProcAddress(hid, "HidD_FreePreparsedData");
    caps_fn = (hidp_caps_fn)GetProcAddress(hid, "HidP_GetCaps");
    classdevs = (sdi_classdevs_fn)GetProcAddress(sdi, "SetupDiGetClassDevsW");
    enum_if = (sdi_enum_fn)GetProcAddress(sdi, "SetupDiEnumDeviceInterfaces");
    detail = (sdi_detail_fn)GetProcAddress(sdi, "SetupDiGetDeviceInterfaceDetailW");
    destroy = (sdi_destroy_fn)GetProcAddress(sdi, "SetupDiDestroyDeviceInfoList");
    if (!guid_fn || !attr_fn || !pp_fn || !free_fn || !caps_fn || !classdevs || !enum_if || !detail || !destroy)
    {
        logline("pad: a HID or SetupAPI function is missing");
        return;
    }
    guid_fn(&g);
    set = classdevs(&g, NULL, NULL, 0x12 /* DIGCF_PRESENT | DIGCF_DEVICEINTERFACE */);
    if (set == INVALID_HANDLE_VALUE) { logline("pad: SetupDiGetClassDevs failed (%lu)", GetLastError()); return; }
    for (i = 0; ; i++)
    {
        struct sp_interface itf = { sizeof(itf), {0}, 0, 0 };
        union { DWORD cbSize; BYTE raw[sizeof(DWORD) + 2048]; } d;
        struct hid_attributes a = { sizeof(a), 0, 0, 0 };
        struct hidp_caps caps;
        void *pp;
        HANDLE h;

        if (!enum_if(set, NULL, &g, i, &itf)) break;
        d.cbSize = 8;   /* sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W) on x64 */
        if (!detail(set, &itf, &d, sizeof(d), NULL, NULL)) continue;
        h = CreateFileW((WCHAR *)(d.raw + 4), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                        NULL, OPEN_EXISTING, 0, NULL);
        if (h == INVALID_HANDLE_VALUE) continue;
        if (attr_fn(h, &a) && a.VendorID == 0x054c && (a.ProductID == 0x0ce6 || a.ProductID == 0x0df2) && pp_fn(h, &pp))
        {
            memset(&caps, 0, sizeof(caps));
            caps_fn(pp, &caps);
            free_fn(pp);
            seen++;
            logline("pad: %04x:%04x usage %02x:%02x, output report %u bytes", a.VendorID, a.ProductID,
                    caps.UsagePage, caps.Usage, caps.OutputReportByteLength);
            if (caps.UsagePage == 1 && caps.Usage == 5 && caps.OutputReportByteLength == 48 && g_pad == INVALID_HANDLE_VALUE)
            {
                g_pad = h;
                g_out_len = caps.OutputReportByteLength;
                continue;
            }
        }
        CloseHandle(h);
    }
    destroy(set);
    if (g_pad != INVALID_HANDLE_VALUE) logline("pad: using the wired DualSense report (48 bytes)");
    else logline("pad: no DualSense with the wired output report among %d Sony pad collection(s): nothing will be written%s",
                 seen, seen ? " (over Bluetooth, keep Bluetooth as a cable on)" : "");
}

static void write_sides(const uint8_t want[2][11], int sides)
{
    uint8_t report[64] = {0x02};
    DWORD w;
    int i;
    for (i = 0; i < 2; i++)
        if (sides & (1 << i))
        {
            report[1] |= 4 << i;
            memcpy(report + 11 + 11 * i, want[i], 11);
        }
    if (!WriteFile(g_pad, report, g_out_len, &w, NULL))
    {
        if (!InterlockedExchangeAdd(&g_failed, 1)) logline("write: failed (%lu); later failures are only counted", GetLastError());
        return;
    }
    InterlockedIncrement(&g_writes);
}

__attribute__((noinline)) int32_t triggers_SetTriggerEffect(int32_t handle, const uint8_t *param);
__attribute__((noinline)) int32_t triggers_SetTriggerEffect(int32_t handle, const uint8_t *param)
{
    uint8_t want[2][11];
    int sides = 0, i;
    (void)handle;

    if (!param) return (int32_t)RETURN_NOT_LOADED;
    InterlockedIncrement(&g_effects);
    EnterCriticalSection(&g_lock);
    if (!g_pad_looked) find_pad();
    if (g_pad != INVALID_HANDLE_VALUE)
    {
        /* Sony's command[0] is L2 and command[1] R2; the DualSense's report has R2 first. */
        for (i = 0; i < 2; i++)
        {
            int ds = i ? 0 : 1;
            const uint8_t *cmd = param + CMD_FIRST + CMD_SIZE * i;
            if (!(param[0] & (1 << i))) continue;
            convert(*(const uint32_t *)cmd, cmd + CMD_PARAM, want[ds]);
            if (memcmp(want[ds], g_last[ds], 11) || !g_set[ds])
            {
                if (!g_set[ds] || want[ds][0] != g_last[ds][0])
                    logline("%s: mode %u -> DualSense %02x %02x%02x %02x%02x%02x%02x .. %02x", ds ? "L2" : "R2",
                            *(const uint32_t *)cmd, want[ds][0], want[ds][1], want[ds][2], want[ds][3], want[ds][4],
                            want[ds][5], want[ds][6], want[ds][9]);
                memcpy(g_last[ds], want[ds], 11);
                g_set[ds] = 1;
                sides |= 1 << ds;
            }
        }
        if (sides) write_sides(want, sides);
    }
    LeaveCriticalSection(&g_lock);
    return (int32_t)RETURN_NOT_LOADED;   /* what the original answers: the game behaves as before */
}

/* The wrapper, by the string it names: NULL unless exactly one function fits. */
static uint8_t *find_wrapper(char *why, size_t cap)
{
    static const char name[] = "scePadSetTriggerEffect";
    IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)(g_exe + ((IMAGE_DOS_HEADER *)g_exe)->e_lfanew);
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    IMAGE_DATA_DIRECTORY *exc = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION];
    const IMAGE_RUNTIME_FUNCTION_ENTRY *fn = (const IMAGE_RUNTIME_FUNCTION_ENTRY *)(g_exe + exc->VirtualAddress);
    size_t nfn = exc->Size / sizeof(*fn), lo, hi;
    uint8_t *text = NULL, *found = NULL, *s;
    uint32_t text_size = 0, str_rva = 0, i, k;
    int strings = 0, hits = 0;

    for (k = 0; k < nt->FileHeader.NumberOfSections; k++)
    {
        uint8_t *b = g_exe + sec[k].VirtualAddress;
        uint32_t n = sec[k].Misc.VirtualSize;
        if (!memcmp(sec[k].Name, ".text", 6)) { text = b; text_size = n; continue; }
        if (sec[k].Characteristics & IMAGE_SCN_MEM_EXECUTE || !(sec[k].Characteristics & IMAGE_SCN_MEM_READ)) continue;
        for (s = b + 1; s + sizeof(name) <= b + n; s++)
            if (*s == name[0] && !s[-1] && !memcmp(s, name, sizeof(name)))
            {
                strings++;
                str_rva = (uint32_t)(s - g_exe);
            }
    }
    if (strings != 1 || !text || !nfn)
    {
        snprintf(why, cap, "%d copies of the name, %s, %u functions", strings, text ? ".text" : "no .text", (unsigned)nfn);
        return NULL;
    }
    for (i = 0; i + 7 <= text_size; i++)
    {
        uint8_t *at = text + i, *start;
        uint32_t rva;
        int32_t disp;
        if ((at[0] != 0x48 && at[0] != 0x4c) || at[1] != 0x8d || (at[2] & 0xc7) != 0x05) continue;
        memcpy(&disp, at + 3, 4);
        rva = (uint32_t)(at + 7 - g_exe) + (uint32_t)disp;
        if (rva != str_rva) continue;
        rva = (uint32_t)(at - g_exe);
        for (lo = 0, hi = nfn; lo < hi; )
        {
            size_t mid = (lo + hi) / 2;
            if (fn[mid].BeginAddress <= rva) lo = mid + 1; else hi = mid;
        }
        if (!lo || rva >= fn[lo - 1].EndAddress) continue;
        start = g_exe + fn[lo - 1].BeginAddress;
        if (memcmp(start, wrapper_start, sizeof(wrapper_start))) continue;
        hits++;
        found = start;
    }
    if (hits != 1)
    {
        snprintf(why, cap, "%d functions name it and start as the wrapper does", hits);
        return NULL;
    }
    return found;
}

static void build_jump(uint8_t code[12], uint64_t target)
{
    code[0] = 0x48; code[1] = 0xb8;
    memcpy(code + 2, &target, 8);
    code[10] = 0xff; code[11] = 0xe0;
}

static void attach(void)
{
    WCHAR path[1024], *slash = NULL, *s;
    uint8_t code[12], *at;
    char why[96];
    DWORD old, was;
    HMODULE self;
    int i;

    InitializeCriticalSection(&g_lock);
    g_exe = (uint8_t *)GetModuleHandleW(NULL);
    if (!GetModuleFileNameW(NULL, path, 1000)) return;
    for (s = path; *s; s++) if (*s == L'\\' || *s == L'/') slash = s;
    if (!slash || lstrcmpiW(slash + 1, L"GoWR.exe")) return;
    for (i = 0; LOG_NAME[i] && slash + 2 + i < path + 1023; i++) slash[1 + i] = (WCHAR)LOG_NAME[i];
    slash[1 + i] = 0;
    g_log = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    logline("==== gowr-triggers (built " __DATE__ " " __TIME__ "), pid %lu", GetCurrentProcessId());
    if (!(at = find_wrapper(why, sizeof(why))))
    {
        logline("the game's scePadSetTriggerEffect wrapper was not found (%s): nothing changed", why);
        return;
    }
    build_jump(code, (uint64_t)(uintptr_t)triggers_SetTriggerEffect);
    if (!VirtualProtect(at, sizeof(code), PAGE_EXECUTE_READWRITE, &old)) { logline("patch failed (%lu)", GetLastError()); return; }
    memcpy(at, code, sizeof(code));
    VirtualProtect(at, sizeof(code), old, &was);
    FlushInstructionCache(GetCurrentProcess(), at, sizeof(code));
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                       (LPCWSTR)(void *)triggers_SetTriggerEffect, &self);
    logline("ready: the wrapper at exe+0x%x sends the game's trigger effects to the pad", (unsigned)(at - g_exe));
}

static void detach(void)
{
    uint8_t off[2][11] = {{0x05}, {0x05}};
    int sides = (g_set[0] ? 1 : 0) | (g_set[1] ? 2 : 0);
    if (!TryEnterCriticalSection(&g_lock)) return;
    if (g_pad != INVALID_HANDLE_VALUE && sides) write_sides(off, sides);
    logline("exit: %ld effects from the game, %ld writes to the pad, %ld failed; triggers released", (long)g_effects,
            (long)g_writes, (long)g_failed);
    LeaveCriticalSection(&g_lock);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) { DisableThreadLibraryCalls(inst); attach(); }
    else if (reason == DLL_PROCESS_DETACH) detach();
    return TRUE;
}
