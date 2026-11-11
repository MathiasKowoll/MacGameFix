/* Keep gs:[0x20] right for Windows code (FiberData) and for native code (its semaphore cache); see below. */
#define FH_RD(v) __asm__ volatile("movq %%gs:0x20, %0" : "=r"(v))
#define FH_WR(v) __asm__ volatile("movq %0, %%gs:0x20" :: "r"((UINT64)(v)))
typedef NTSTATUS (WINAPI *fh_dispatch_t)(UINT64, unsigned int, void *);
static fh_dispatch_t fh_orig;
static volatile LONG fh_nrestore, fh_nentry;
/* per-thread state in TEB TlsSlots, read directly (TlsGetValue would reset the last error):
 * fh_ns = native code's own gs:0x20 value (its semaphore cache) while Windows code runs */
static DWORD fh_ns = 0;
/* FH6 has used all 64 direct TEB TLS slots before this DLL loads, so the per-thread value lives in an
 * open-addressing table keyed by the TEB address (gs:0x30); no API calls, so the last error is untouched. */
#define FH_TAB 16384
static volatile LONG64 fh_key[FH_TAB];
static UINT64 fh_val[FH_TAB];
static UINT64 fh_teb(void) { UINT64 t; __asm__ volatile("movq %%gs:0x30, %0" : "=r"(t)); return t; }
static UINT64 *fh_slot(void)
{
    UINT64 t = fh_teb(); unsigned i = (unsigned)((t >> 12) ^ (t >> 24)) & (FH_TAB - 1), n;
    for (n = 0; n < FH_TAB; n++, i = (i + 1) & (FH_TAB - 1)) {
        LONG64 k = fh_key[i];
        if ((UINT64)k == t) return &fh_val[i];
        if (!k && !InterlockedCompareExchange64(&fh_key[i], (LONG64)t, 0)) return &fh_val[i];
        if ((UINT64)fh_key[i] == t) return &fh_val[i];
    }
    return NULL;
}
static UINT64 fh_get(DWORD i) { UINT64 *s = fh_slot(); (void)i; return s ? *s : 0; }
static void fh_set(DWORD i, UINT64 v) { UINT64 *s = fh_slot(); (void)i; if (s) *s = v; }

static void fh_log(UINT64 before, UINT64 after, unsigned int code)
{
    char b[96]; int n = 0; int i; UINT64 v[3]; static const char *hx = "0123456789abcdef";
    HANDLE h;
    DWORD w;
    if (!hb_debug) return;   // play build
    v[0] = before; v[1] = after; v[2] = code;
    for (i = 0; i < 3; i++) {
        int s;
        for (s = 60; s >= 0; s -= 4) b[n++] = hx[(v[i] >> s) & 15];
        b[n++] = i < 2 ? ' ' : '\n';
    }
    h = CreateFileA("C:\\highball\\logs\\fh6-fiberfix.log", FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) { WriteFile(h, b, n, &w, NULL); CloseHandle(h); }
}

/* Once Metal is loaded, Windows code runs with gs on the macOS thread block: gs:0x30 (Self) still gives the TEB,
 * but gs:0x20 is libdispatch's cached semaphore port, not the TEB's FiberData. Wine's fiber functions use the TEB
 * and stay right; code that reads gs:0x20 directly (MSVC GetCurrentFiber, e.g. ScriptHookV) does not. So gs:0x20
 * mirrors the TEB's FiberData while Windows code runs, and holds native code's own value while native code runs:
 * swapped at every crossing (unix calls, user callbacks) and set when a thread becomes a fiber. */
#define FH_TEBFD() ({ BYTE *t_; __asm__ volatile("movq %%gs:0x30, %0" : "=r"(t_)); *(UINT64 *)(t_ + 0x20); })

__attribute__((used,noinline)) static NTSTATUS WINAPI fh_wrap(UINT64 handle, unsigned int code, void *args)
{
    UINT64 cur, fd = FH_TEBFD();
    NTSTATUS r;
    FH_RD(cur);
    /* the mirror is in place: give native code its value back; anything else is native's own (left elsewhere) */
    FH_WR(cur == fd ? fh_get(fh_ns) : cur);
    r = fh_orig(handle, code, args);
    FH_RD(cur);
    fh_set(fh_ns, cur);
    FH_WR(FH_TEBFD());
    if (fh_nentry < 4 && cur && cur != fd) { fh_nentry++; fh_log(cur, fd, code); }
    return r;
}

/* user callbacks (PEB KernelCallbackTable, e.g. window procedures): native -> Windows on entry, back on return */
typedef NTSTATUS (WINAPI *fh_cb_t)(void *, ULONG);
#define FH_NCB 128
static fh_cb_t fh_cb_orig[FH_NCB];
static void *fh_cb_table[2 * FH_NCB];
static NTSTATUS fh_cb(int i, void *args, ULONG size)
{
    UINT64 v; NTSTATUS r;
    FH_RD(v);
    fh_set(fh_ns, v);
    FH_WR(FH_TEBFD());
    r = fh_cb_orig[i](args, size);
    FH_WR(fh_get(fh_ns));
    return r;
}
#define FH_CB(i) static NTSTATUS WINAPI fh_cb_##i(void *a, ULONG s) { return fh_cb(i, a, s); }
FH_CB(0) FH_CB(1) FH_CB(2) FH_CB(3) FH_CB(4) FH_CB(5) FH_CB(6) FH_CB(7)
FH_CB(8) FH_CB(9) FH_CB(10) FH_CB(11) FH_CB(12) FH_CB(13) FH_CB(14) FH_CB(15)
FH_CB(16) FH_CB(17) FH_CB(18) FH_CB(19) FH_CB(20) FH_CB(21) FH_CB(22) FH_CB(23)
FH_CB(24) FH_CB(25) FH_CB(26) FH_CB(27) FH_CB(28) FH_CB(29) FH_CB(30) FH_CB(31)
FH_CB(32) FH_CB(33) FH_CB(34) FH_CB(35) FH_CB(36) FH_CB(37) FH_CB(38) FH_CB(39)
FH_CB(40) FH_CB(41) FH_CB(42) FH_CB(43) FH_CB(44) FH_CB(45) FH_CB(46) FH_CB(47)
FH_CB(48) FH_CB(49) FH_CB(50) FH_CB(51) FH_CB(52) FH_CB(53) FH_CB(54) FH_CB(55)
FH_CB(56) FH_CB(57) FH_CB(58) FH_CB(59) FH_CB(60) FH_CB(61) FH_CB(62) FH_CB(63)
FH_CB(64) FH_CB(65) FH_CB(66) FH_CB(67) FH_CB(68) FH_CB(69) FH_CB(70) FH_CB(71)
FH_CB(72) FH_CB(73) FH_CB(74) FH_CB(75) FH_CB(76) FH_CB(77) FH_CB(78) FH_CB(79)
FH_CB(80) FH_CB(81) FH_CB(82) FH_CB(83) FH_CB(84) FH_CB(85) FH_CB(86) FH_CB(87)
FH_CB(88) FH_CB(89) FH_CB(90) FH_CB(91) FH_CB(92) FH_CB(93) FH_CB(94) FH_CB(95)
FH_CB(96) FH_CB(97) FH_CB(98) FH_CB(99) FH_CB(100) FH_CB(101) FH_CB(102) FH_CB(103)
FH_CB(104) FH_CB(105) FH_CB(106) FH_CB(107) FH_CB(108) FH_CB(109) FH_CB(110) FH_CB(111)
FH_CB(112) FH_CB(113) FH_CB(114) FH_CB(115) FH_CB(116) FH_CB(117) FH_CB(118) FH_CB(119)
FH_CB(120) FH_CB(121) FH_CB(122) FH_CB(123) FH_CB(124) FH_CB(125) FH_CB(126) FH_CB(127)
static const fh_cb_t fh_cb_thunk[FH_NCB] = {
    fh_cb_0, fh_cb_1, fh_cb_2, fh_cb_3, fh_cb_4, fh_cb_5, fh_cb_6, fh_cb_7,
    fh_cb_8, fh_cb_9, fh_cb_10, fh_cb_11, fh_cb_12, fh_cb_13, fh_cb_14, fh_cb_15,
    fh_cb_16, fh_cb_17, fh_cb_18, fh_cb_19, fh_cb_20, fh_cb_21, fh_cb_22, fh_cb_23,
    fh_cb_24, fh_cb_25, fh_cb_26, fh_cb_27, fh_cb_28, fh_cb_29, fh_cb_30, fh_cb_31,
    fh_cb_32, fh_cb_33, fh_cb_34, fh_cb_35, fh_cb_36, fh_cb_37, fh_cb_38, fh_cb_39,
    fh_cb_40, fh_cb_41, fh_cb_42, fh_cb_43, fh_cb_44, fh_cb_45, fh_cb_46, fh_cb_47,
    fh_cb_48, fh_cb_49, fh_cb_50, fh_cb_51, fh_cb_52, fh_cb_53, fh_cb_54, fh_cb_55,
    fh_cb_56, fh_cb_57, fh_cb_58, fh_cb_59, fh_cb_60, fh_cb_61, fh_cb_62, fh_cb_63,
    fh_cb_64, fh_cb_65, fh_cb_66, fh_cb_67, fh_cb_68, fh_cb_69, fh_cb_70, fh_cb_71,
    fh_cb_72, fh_cb_73, fh_cb_74, fh_cb_75, fh_cb_76, fh_cb_77, fh_cb_78, fh_cb_79,
    fh_cb_80, fh_cb_81, fh_cb_82, fh_cb_83, fh_cb_84, fh_cb_85, fh_cb_86, fh_cb_87,
    fh_cb_88, fh_cb_89, fh_cb_90, fh_cb_91, fh_cb_92, fh_cb_93, fh_cb_94, fh_cb_95,
    fh_cb_96, fh_cb_97, fh_cb_98, fh_cb_99, fh_cb_100, fh_cb_101, fh_cb_102, fh_cb_103,
    fh_cb_104, fh_cb_105, fh_cb_106, fh_cb_107, fh_cb_108, fh_cb_109, fh_cb_110, fh_cb_111,
    fh_cb_112, fh_cb_113, fh_cb_114, fh_cb_115, fh_cb_116, fh_cb_117, fh_cb_118, fh_cb_119,
    fh_cb_120, fh_cb_121, fh_cb_122, fh_cb_123, fh_cb_124, fh_cb_125, fh_cb_126, fh_cb_127 };

/* swap PEB->KernelCallbackTable for a copy: user32 entries go through fh_cb, the rest is copied as is */
static int fh_cb_install(void)
{
    BYTE *peb; void **tab; HMODULE u32 = GetModuleHandleA("user32.dll"), m; int n, i;
    __asm__ volatile("movq %%gs:0x60, %0" : "=r"(peb));
    tab = *(void ***)(peb + 0x58);
    if (!tab || !u32) return 0;
    for (n = 0; n < FH_NCB; n++) {
        m = NULL;
        if (!tab[n] || !GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                          (LPCWSTR)tab[n], &m) || m != u32) break;
        fh_cb_orig[n] = (fh_cb_t)tab[n];
        fh_cb_table[n] = (void *)fh_cb_thunk[n];
    }
    for (i = n; i < 2 * FH_NCB; i++) fh_cb_table[i] = tab[i];
    if (!n) return 0;
    *(void ***)(peb + 0x58) = fh_cb_table;
    fh_log(n, (UINT64)tab, 0xCB000000u);
    return n;
}

/* ConvertThreadToFiberEx: set the mirror at once (ScriptHookV reads gs:0x20 right after the call).
 * Wine builds it hot-patchable: a 2-byte nop with 5 bytes of padding before it. */
typedef LPVOID (WINAPI *fh_ctf_t)(LPVOID, DWORD);
static fh_ctf_t fh_ctf_orig;
static LPVOID WINAPI fh_ctf(LPVOID param, DWORD flags)
{
    UINT64 cur, fd = FH_TEBFD();
    LPVOID f;
    FH_RD(cur);
    if (cur != fd) fh_set(fh_ns, cur);   /* native's value: keep it for its next turn */
    f = fh_ctf_orig(param, flags);
    FH_WR(FH_TEBFD());
    return f;
}
static int fh_ctf_install(void)
{
    BYTE *p = (BYTE *)GetProcAddress(GetModuleHandleA("kernelbase.dll"), "ConvertThreadToFiberEx"), *t = NULL;
    DWORD old; INT64 rel; int i; UINT64 a;
    if (!p || p[0] != 0x66 || p[1] != 0x90) return 0;
    for (i = 1; i <= 5; i++) if (p[-i] != 0xCC && p[-i] != 0x90) return 0;
    for (a = ((UINT64)p & ~0xFFFFULL) - 0x10000; !t && a > (UINT64)p - 0x7FF00000ULL; a -= 0x10000)
        t = VirtualAlloc((void *)a, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if (!t) return 0;
    t[0] = 0xFF; t[1] = 0x25; *(DWORD *)(t + 2) = 0; *(UINT64 *)(t + 6) = (UINT64)fh_ctf;   /* jmp [rip]; dq fh_ctf */
    rel = (INT64)t - (INT64)p;
    fh_ctf_orig = (fh_ctf_t)(p + 2);
    if (!VirtualProtect(p - 5, 7, PAGE_EXECUTE_READWRITE, &old)) return 0;
    p[-5] = 0xE9; *(INT32 *)(p - 4) = (INT32)rel;
    *(volatile WORD *)p = 0xF9EB;   /* jmp -7 */
    VirtualProtect(p - 5, 7, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p - 5, 7);
    fh_log((UINT64)p, (UINT64)t, 0xCF000000u);
    return 1;
}

/* ABI guard: preserves rsi/rdi across the unix call (no counters). */
void fh_guard(void);
__asm__(
".text\n.globl fh_guard\nfh_guard:\n"
"  pushq %rsi\n  pushq %rdi\n  pushq %rbx\n"
"  subq $0x20, %rsp\n"
"  call fh_wrap\n"
"  addq $0x20, %rsp\n"
"  movq 16(%rsp), %rsi\n  movq 8(%rsp), %rdi\n"
"  popq %rbx\n  addq $16, %rsp\n  ret\n");

/* returns 1 if hooked, 0 if export missing */
static int fiberhook_install(void)
{
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    fh_dispatch_t *pp = nt ? (fh_dispatch_t *)GetProcAddress(nt, "__wine_unix_call_dispatcher") : NULL;
    DWORD old;
    if (!pp) return 2;
    if (!*pp) return 3;
    fh_orig = *pp;
    { UINT64 cur, fd = FH_TEBFD(); FH_RD(cur); if (cur != fd) fh_set(fh_ns, cur); FH_WR(fd); }
    /* fh_cb_install() and fh_ctf_install(): disabled, the callback-table swap hung a message loop in testing */
    if (!VirtualProtect(pp, sizeof *pp, PAGE_READWRITE, &old)) return 4;
    *pp = (fh_dispatch_t)fh_guard;
    VirtualProtect(pp, sizeof *pp, old, &old);
    return 1;
}
