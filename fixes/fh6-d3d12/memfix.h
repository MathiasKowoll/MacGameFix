/* memfix: replace K32GetProcessMemoryInfo (kernelbase, and kernel32 if separate) so PagefileUsage /
   PrivateUsage (Wine fills them from the task virtual size, ~65 GB) are clamped to WorkingSetSize,
   and never exceed GlobalMemoryStatusEx ullTotalPhys. Does not call the original. */
typedef struct { SIZE_T PeakVirtualSize, VirtualSize; ULONG PageFaultCount; SIZE_T PeakWorkingSetSize, WorkingSetSize,
    QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage, QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage,
    PagefileUsage, PeakPagefileUsage, PrivateUsage; } mf_vmc_ex;
typedef LONG (WINAPI *mf_ntqip_t)(HANDLE, ULONG, PVOID, ULONG, PULONG);
typedef struct { DWORD cb, PageFaultCount; SIZE_T PeakWorkingSetSize, WorkingSetSize, QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage,
    QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage, PagefileUsage, PeakPagefileUsage, PrivateUsage; } mf_pmc_ex;
typedef struct { DWORD cb, PageFaultCount; SIZE_T a[8]; } mf_pmc;
static mf_ntqip_t mf_ntqip;

static BOOL WINAPI mf_GetProcessMemoryInfo(HANDLE h, void *out, DWORD cb)
{
    mf_vmc_ex v; ULONG rl = 0; LONG st; mf_pmc_ex r; MEMORYSTATUSEX g; SIZE_T cap;
    if (cb < sizeof(mf_pmc)) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
    memset(&v, 0, sizeof v);
    st = mf_ntqip ? mf_ntqip(h, 3 /* ProcessVmCounters */, &v, sizeof v, &rl) : (LONG)0xC0000001;
    if (st < 0) { SetLastError(ERROR_ACCESS_DENIED); return FALSE; }
    cap = v.WorkingSetSize;
    if (v.PeakWorkingSetSize > cap) cap = v.PeakWorkingSetSize;
    if (v.PagefileUsage > v.WorkingSetSize) v.PagefileUsage = v.WorkingSetSize;
    if (v.PrivateUsage > v.WorkingSetSize) v.PrivateUsage = v.WorkingSetSize;
    if (v.PeakPagefileUsage < v.PagefileUsage || v.PeakPagefileUsage > cap) v.PeakPagefileUsage = v.PagefileUsage;
    memset(&g, 0, sizeof g); g.dwLength = sizeof g;
    if (GlobalMemoryStatusEx(&g) && g.ullTotalPhys) {
        if (v.WorkingSetSize > g.ullTotalPhys) v.WorkingSetSize = (SIZE_T)g.ullTotalPhys;
        if (v.PeakWorkingSetSize > g.ullTotalPhys) v.PeakWorkingSetSize = (SIZE_T)g.ullTotalPhys;
        if (v.PagefileUsage > g.ullTotalPhys) v.PagefileUsage = (SIZE_T)g.ullTotalPhys;
        if (v.PeakPagefileUsage > g.ullTotalPhys) v.PeakPagefileUsage = (SIZE_T)g.ullTotalPhys;
        if (v.PrivateUsage > g.ullTotalPhys) v.PrivateUsage = (SIZE_T)g.ullTotalPhys;
    }
    memset(&r, 0, sizeof r);
    r.cb = cb;
    r.PageFaultCount = v.PageFaultCount;
    r.PeakWorkingSetSize = v.PeakWorkingSetSize; r.WorkingSetSize = v.WorkingSetSize;
    r.QuotaPeakPagedPoolUsage = v.QuotaPeakPagedPoolUsage; r.QuotaPagedPoolUsage = v.QuotaPagedPoolUsage;
    r.QuotaPeakNonPagedPoolUsage = v.QuotaPeakNonPagedPoolUsage; r.QuotaNonPagedPoolUsage = v.QuotaNonPagedPoolUsage;
    r.PagefileUsage = v.PagefileUsage; r.PeakPagefileUsage = v.PeakPagefileUsage;
    r.PrivateUsage = v.PrivateUsage;
    memcpy(out, &r, cb < sizeof r ? cb : sizeof r);
    return TRUE;
}

static int mf_patch(void *fn, void *dst)
{
    BYTE *p = (BYTE *)fn; DWORD old, tmp;
    if (!fn) return 0;
    if (!VirtualProtect(p, 12, PAGE_EXECUTE_READWRITE, &old)) return 0;
    p[0] = 0x48; p[1] = 0xB8; memcpy(p + 2, &dst, 8); p[10] = 0xFF; p[11] = 0xE0; /* movabs rax,imm64; jmp rax */
    VirtualProtect(p, 12, old, &tmp);
    FlushInstructionCache(GetCurrentProcess(), p, 12);
    return 1;
}

static void memfix_install(void)
{
    const char *mods[2] = { "kernelbase.dll", "kernel32.dll" };
    void *done[2] = { NULL, NULL }; int nd = 0, ok = 0, i, j; char msg[256]; int len;
    HANDLE f; DWORD wr;
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    mf_ntqip = nt ? (mf_ntqip_t)GetProcAddress(nt, "NtQueryInformationProcess") : NULL;
    len = wsprintfA(msg, "memfix: ");
    for (i = 0; i < 2; i++) {
        HMODULE m = GetModuleHandleA(mods[i]);
        void *fn = m ? (void *)GetProcAddress(m, "K32GetProcessMemoryInfo") : NULL; int dup = 0, r;
        for (j = 0; j < nd; j++) if (done[j] == fn) dup = 1;
        if (!fn) { len += wsprintfA(msg + len, "%s:missing ", mods[i]); continue; }
        if (dup) { len += wsprintfA(msg + len, "%s:same-as-previous(%p) ", mods[i], fn); continue; }
        done[nd++] = fn;
        r = mf_ntqip ? mf_patch(fn, (void *)mf_GetProcessMemoryInfo) : 0; ok += r;
        len += wsprintfA(msg + len, "%s:%p:%s ", mods[i], fn, r ? "patched" : "FAILED");
    }
    len += wsprintfA(msg + len, "result=%s\r\n", ok ? "OK" : "FAIL");
    if (!hb_debug) return;   // play build: the patch is applied above, only the log is skipped
    CreateDirectoryA("C:\\highball", NULL); CreateDirectoryA("C:\\highball\\logs", NULL);
    f = CreateFileA("C:\\highball\\logs\\fh6-memfix.log", FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f != INVALID_HANDLE_VALUE) { WriteFile(f, msg, len, &wr, NULL); CloseHandle(f); }
}
