/*
 * mf-reader-fallback.c -- hand a refused video to our own ASF reader.
 *
 * The whole job: when Media Foundation refuses a stream in
 * MFCreateSourceReaderFromByteStream, try mgvf-asf-reader.dll (asf-reader.c)
 * from the same folder, and return its reader instead of the refusal. Nothing
 * else is touched -- no device, no vtable, no other call. A stream Media
 * Foundation can open never reaches the fallback.
 *
 * Built as a proxy of a DLL the game imports, forwarding every export to the
 * original kept as <name>_real.dll. For Devil May Cry 5 that is amd_ags_x64.dll.
 *
 * WHY. RE Engine plays some of its videos -- Devil May Cry 5's skill previews
 * -- as VC-1 in ASF, and no CrossOver decodes VC-1. On stable 26.3 the staged
 * codec answers it; on an engine without it the game is handed a null reader
 * and dereferences it (see the wiki page RE-Engine-VC1). Persona 5 Strikers
 * measured the reader on CrossOver Preview 27 with nothing staged.
 *
 * The same for DirectShow (NINJA GAIDEN 3: ASF with WMV3 and WMA v2, played
 * through quartz and qasf). Wine's prefixes give a .wmv no source filter, so
 * the game's filter graph is watched and a .wmv gets the WM ASF Reader the way
 * Windows gives it one; that reader's IWMReader is wrapped, so a file wine's
 * cannot open is opened by ours; and a WMV decoder DMO wine cannot create is
 * replaced by ours. All of it lives in mgvf-asf-reader.dll (dshow-graph.c,
 * wm-reader.c, wmv-dmo.c) and is armed only when that file is beside the game.
 *
 * A file mf-no-asf-reader.txt beside the game turns the fallback off.
 *
 * Part of MacGameVideoFix -- https://github.com/MathiasKowoll/MacGameVideoFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <wchar.h>

#define LOGFILE "C:\\mgvf-mf-fallback.log"
#define LOG_MAX 200

static LONG log_lines;

static void logf_(const char *fmt, ...)
{
    char buf[1024];
    int n;
    va_list ap;
    HANDLE h;
    DWORD w;

    if (InterlockedIncrement(&log_lines) > LOG_MAX) return;
    n = snprintf(buf, sizeof(buf), "[mf-fallback] ");
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof(buf) - n - 2, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof(buf) - 2) n = sizeof(buf) - 2;
    buf[n++] = '\r'; buf[n++] = '\n';
    h = CreateFileA(LOGFILE, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    WriteFile(h, buf, n, &w, NULL);
    CloseHandle(h);
}

typedef HRESULT (WINAPI *create_fn)(void *, void *, void **);
static create_fn real_create;
static create_fn asf_reader_create;
static HRESULT (WINAPI *wm_reader_wrap)(void *, void **);
static void (WINAPI *patch_filter_graph)(void *);
static HRESULT (WINAPI *wmv_dmo_create)(void *, REFIID, void **);

static BOOL load_asf_reader_(void)
{
    static LONG tried;
    WCHAR path[MAX_PATH], *slash;
    HMODULE self = NULL, mod;

    if (InterlockedExchange(&tried, 1)) return asf_reader_create != NULL;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)(void *)load_asf_reader_, &self) ||
        !GetModuleFileNameW(self, path, MAX_PATH))
        return FALSE;
    slash = wcsrchr(path, L'\\');
    if (!slash || (slash - path) + 32 >= MAX_PATH) return FALSE;

    lstrcpyW(slash + 1, L"mf-no-asf-reader.txt");
    if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES)
    {
        logf_("off (mf-no-asf-reader.txt)");
        return FALSE;
    }
    lstrcpyW(slash + 1, L"mgvf-asf-reader.dll");
    mod = LoadLibraryW(path);
    if (!mod)
    {
        logf_("mgvf-asf-reader.dll not loaded (err %lu) -- install the fix again", GetLastError());
        return FALSE;
    }
    asf_reader_create = (create_fn)(void *)GetProcAddress(mod, "MGVF_CreateAsfReader");
    *(FARPROC *)&wm_reader_wrap = GetProcAddress(mod, "MGVF_WrapWMReader");
    *(FARPROC *)&patch_filter_graph = GetProcAddress(mod, "MGVF_PatchFilterGraph");
    *(FARPROC *)&wmv_dmo_create = GetProcAddress(mod, "MGVF_CreateWmvDmo");
    logf_("our ASF reader: %s", asf_reader_create ? "loaded" : "loaded, but it exports no MGVF_CreateAsfReader");
    return asf_reader_create != NULL;
}

static HRESULT WINAPI my_create(void *stream, void *attrs, void **reader)
{
    static LONG calls, ours;
    HRESULT hr = real_create(stream, attrs, reader);
    LONG n = InterlockedIncrement(&calls);
    if (n == 1) logf_("MFCreateSourceReaderFromByteStream -> 0x%08lx (first call)", hr);
    if (FAILED(hr) && stream && reader && load_asf_reader_())
    {
        HRESULT mine = asf_reader_create(stream, attrs, reader);
        LONG k = InterlockedIncrement(&ours);
        if (k <= 5 || FAILED(mine))
            logf_("Media Foundation refused a stream (0x%08lx); our ASF reader -> 0x%08lx (%ld so far)",
                  hr, mine, k);
        if (SUCCEEDED(mine)) hr = mine;
    }
    return hr;
}

/* An import of `base`, replaced in its import table. */
static void *hook_module_import(HMODULE base, const char *dll, const char *func, void *replacement);

/* The game's own import of the function, replaced in its import table. */
static void *hook_import(const char *dll, const char *func, void *replacement)
{
    return hook_module_import(GetModuleHandleA(NULL), dll, func, replacement);
}

static void *hook_module_import(HMODULE base, const char *dll, const char *func, void *replacement)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((BYTE *)base + dos->e_lfanew);
    IMAGE_DATA_DIRECTORY *dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    IMAGE_IMPORT_DESCRIPTOR *imp;

    if (!dir->VirtualAddress) return NULL;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)((BYTE *)base + dir->VirtualAddress); imp->Name; imp++)
    {
        IMAGE_THUNK_DATA *orig, *iat;
        if (lstrcmpiA((const char *)((BYTE *)base + imp->Name), dll) != 0) continue;
        orig = (IMAGE_THUNK_DATA *)((BYTE *)base + imp->OriginalFirstThunk);
        iat  = (IMAGE_THUNK_DATA *)((BYTE *)base + imp->FirstThunk);
        for (; orig->u1.AddressOfData; orig++, iat++)
        {
            IMAGE_IMPORT_BY_NAME *by;
            void *original;
            DWORD old;
            if (IMAGE_SNAP_BY_ORDINAL(orig->u1.Ordinal)) continue;
            by = (IMAGE_IMPORT_BY_NAME *)((BYTE *)base + orig->u1.AddressOfData);
            if (lstrcmpiA((const char *)by->Name, func) != 0) continue;
            original = (void *)iat->u1.Function;
            if (!VirtualProtect(&iat->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) return NULL;
            iat->u1.Function = (ULONG_PTR)replacement;
            VirtualProtect(&iat->u1.Function, sizeof(void *), old, &old);
            return original;
        }
    }
    return NULL;
}

/* --------------------------------------------------------- DirectShow --- */

static const GUID clsid_filter_graph =
    { 0xe436ebb3, 0x524f, 0x11ce, { 0x9f, 0x53, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 } };
static const GUID clsid_filter_graph_no_thread =
    { 0xe436ebb8, 0x524f, 0x11ce, { 0x9f, 0x53, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 } };
static const GUID clsid_wmv_decoder =
    { 0x82d353df, 0x90bd, 0x4382, { 0x8b, 0xc2, 0x3f, 0x61, 0x92, 0xb7, 0x6e, 0x34 } };

typedef HRESULT (WINAPI *cocreate_fn)(REFCLSID, void *, DWORD, REFIID, void **);
static cocreate_fn real_game_CoCreateInstance, real_qasf_CoCreateInstance;
static HRESULT (WINAPI *real_qasf_WMCreateReader)(void *, DWORD, void **);

static HRESULT WINAPI my_game_CoCreateInstance(REFCLSID clsid, void *outer, DWORD ctx, REFIID iid, void **out)
{
    HRESULT hr = real_game_CoCreateInstance(clsid, outer, ctx, iid, out);
    if (SUCCEEDED(hr) && out && *out && clsid
        && (IsEqualGUID(clsid, &clsid_filter_graph) || IsEqualGUID(clsid, &clsid_filter_graph_no_thread))
        && load_asf_reader_() && patch_filter_graph)
        patch_filter_graph(*out);
    return hr;
}

static HRESULT WINAPI my_qasf_CoCreateInstance(REFCLSID clsid, void *outer, DWORD ctx, REFIID iid, void **out)
{
    HRESULT hr = real_qasf_CoCreateInstance(clsid, outer, ctx, iid, out);
    if (FAILED(hr) && clsid && IsEqualGUID(clsid, &clsid_wmv_decoder) && out
        && load_asf_reader_() && wmv_dmo_create)
    {
        HRESULT mine = wmv_dmo_create(outer, iid, out);
        logf_("WMVideo Decoder DMO refused (0x%08lx); ours -> 0x%08lx", hr, mine);
        if (SUCCEEDED(mine)) hr = mine;
    }
    return hr;
}

static HRESULT WINAPI my_qasf_WMCreateReader(void *reserved, DWORD rights, void **reader)
{
    HRESULT hr = real_qasf_WMCreateReader(reserved, rights, reader);
    if (SUCCEEDED(hr) && reader && *reader && load_asf_reader_() && wm_reader_wrap)
    {
        static LONG said;
        void *wrapped = NULL;
        if (SUCCEEDED(wm_reader_wrap(*reader, &wrapped)) && wrapped) *reader = wrapped;
        if (InterlockedIncrement(&said) == 1) logf_("WM reader wrapped: ours opens what wine's cannot");
    }
    return hr;
}

/* Only where the reader sits beside the game. qasf is loaded here, once, so
 * the module the graph later uses is the one whose imports were replaced. */
static DWORD WINAPI arm_dshow(void *unused)
{
    WCHAR path[MAX_PATH], *slash;
    HMODULE self = NULL, qasf;
    void *was;
    (void)unused;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)(void *)arm_dshow, &self) ||
        !GetModuleFileNameW(self, path, MAX_PATH))
        return 0;
    slash = wcsrchr(path, L'\\');
    if (!slash || (slash - path) + 32 >= MAX_PATH) return 0;
    lstrcpyW(slash + 1, L"mgvf-asf-reader.dll");
    if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) return 0;
    if (!(qasf = LoadLibraryA("qasf.dll"))) { logf_("qasf.dll not loaded; no DirectShow fallback"); return 0; }
    was = hook_module_import(qasf, "ole32.dll", "CoCreateInstance", (void *)my_qasf_CoCreateInstance);
    if (was) real_qasf_CoCreateInstance = (cocreate_fn)was;
    was = hook_module_import(qasf, "wmvcore.dll", "WMCreateReader", (void *)my_qasf_WMCreateReader);
    if (was) *(void **)&real_qasf_WMCreateReader = was;
    logf_("DirectShow: qasf %s", was ? "watched (WMCreateReader, CoCreateInstance)" : "imports no WMCreateReader");
    return 0;
}

/* ------------------------------------------------------------ evidence --- */

/* Which file a module was loaded from, by name, once. A DLL beside the game and
 * the engine's own build of it answer to the same name; only the path tells
 * which one the process is running -- NINJA GAIDEN 3 crashed with d9vk beside
 * it and no d9vk log, which says nothing until this does. */
static void log_module(const char *name)
{
    char path[MAX_PATH];
    HMODULE m = GetModuleHandleA(name);
    if (!m) { logf_("%s: not loaded", name); return; }
    if (GetModuleFileNameA(m, path, sizeof(path))) logf_("%s: %s", name, path);
}

/* Where a crash happens: the first few access violations and illegal
 * instructions, by module and offset. First-chance, so a game that handles its
 * own is only noted, never changed. */
static LONG WINAPI note_fault(EXCEPTION_POINTERS *ep)
{
    static LONG said;
    DWORD code = ep->ExceptionRecord->ExceptionCode;
    if ((code == EXCEPTION_ACCESS_VIOLATION || code == EXCEPTION_ILLEGAL_INSTRUCTION ||
         code == 0xc0000409 /* stack buffer overrun / fail fast */) && InterlockedIncrement(&said) <= 5)
    {
        HMODULE m = NULL;
        char path[MAX_PATH] = "?";
        void *at = ep->ExceptionRecord->ExceptionAddress;
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)at, &m) && m)
            GetModuleFileNameA(m, path, sizeof(path));
        logf_("exception 0x%08lx at %p = %s+0x%llx", code, at, path,
              m ? (unsigned long long)((BYTE *)at - (BYTE *)m) : 0ULL);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

/* For a game that resolves the function by name instead. */
static FARPROC (WINAPI *real_GetProcAddress)(HMODULE, LPCSTR);

static FARPROC WINAPI my_GetProcAddress(HMODULE module, LPCSTR name)
{
    FARPROC proc = real_GetProcAddress(module, name);
    if (proc && name && ((ULONG_PTR)name >> 16) &&
        lstrcmpA(name, "MFCreateSourceReaderFromByteStream") == 0)
    {
        if (!real_create) real_create = (create_fn)(void *)proc;
        return (FARPROC)(void *)my_create;
    }
    return proc;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        void *was;
        DisableThreadLibraryCalls(inst);
        was = hook_import("MFReadWrite.dll", "MFCreateSourceReaderFromByteStream", (void *)my_create);
        if (was) real_create = (create_fn)was;
        *(void **)&real_GetProcAddress =
            hook_import("KERNEL32.dll", "GetProcAddress", (void *)my_GetProcAddress);
        if (!real_GetProcAddress)
            *(FARPROC *)&real_GetProcAddress =
                GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetProcAddress");
        logf_("armed: MFCreateSourceReaderFromByteStream %s", was ? "hooked in the import table"
              : "not imported; watched through GetProcAddress");
        AddVectoredExceptionHandler(1, note_fault);
        log_module("d3d9.dll");
        /* The game's filter graph, through its own CoCreateInstance import. */
        was = hook_import("ole32.dll", "CoCreateInstance", (void *)my_game_CoCreateInstance);
        if (was)
        {
            HANDLE t;
            real_game_CoCreateInstance = (cocreate_fn)was;
            if ((t = CreateThread(NULL, 0, arm_dshow, NULL, 0, NULL))) CloseHandle(t);
        }
    }
    return TRUE;
}
