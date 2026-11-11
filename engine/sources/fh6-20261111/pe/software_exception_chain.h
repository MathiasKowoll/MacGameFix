/* Experimental opt-in PE dispatcher optimization, not enabled in normal runners.
 * Re-dispatch only a known unconditional one-byte #UD after a handled #UD.
 * Original instructions and handler effects remain intact. No result is cached.
 * A separate explicit-context prototype does not establish this path's correctness:
 * nested dispatch, extended state and real-game behavior still require testing. */
#if defined(__x86_64__) && !defined(__arm64ec__)
/* Public only in this experimental DLL, for the authored validation probe.
 * [0] eligible deliveries, [1] synthesized links, [2] bounded-chain exits. */
LONG64 __wine_software_exception_chain_stats[6];
/* Readable activation state, even when all hot-path aggregate counters are off. */
LONG __wine_software_exception_chain_configuration[4] = {-1, -1, -1, -1};
#define software_chain_mode __wine_software_exception_chain_configuration[0]
#define software_chain_statistics __wine_software_exception_chain_configuration[1]
#define software_bridge_resume __wine_software_exception_chain_configuration[2]
#define software_alu_enabled __wine_software_exception_chain_configuration[3]
#include "guaranteed_ud.h"
static LONG software_legacy_d5;

/* The fast path reads every group below; equality of two incomplete contexts
 * does not make absent fields valid. An unsupported context uses normal dispatch. */
BOOL WINAPI __wine_software_exception_chain_context_valid( DWORD flags )
{
    const DWORD required = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_SEGMENTS |
                           CONTEXT_FLOATING_POINT | CONTEXT_DEBUG_REGISTERS;
    return (flags & required) == required;
}

static void software_chain_count( unsigned int index )
{
    if (software_chain_statistics) InterlockedIncrement64(&__wine_software_exception_chain_stats[index]);
}

static void burst_configure(void);

static BOOL software_chain_enabled(void)
{
    LONG mode = software_chain_mode;
    if (mode == -1)
    {
        WCHAR buffer[16];
        UNICODE_STRING name = RTL_CONSTANT_STRING(L"WINE_SOFTWARE_EXCEPTION_CHAIN");
        UNICODE_STRING value = {0, sizeof(buffer), buffer};
        IMAGE_NT_HEADERS *nt = RtlImageNtHeader(NtCurrentTeb()->Peb->ImageBaseAddress);
        UNICODE_STRING *path = &NtCurrentTeb()->Peb->ProcessParameters->ImagePathName;
        UNICODE_STRING base = *path;
        UNICODE_STRING probe = RTL_CONSTANT_STRING(L"exception_chain_probe.exe");
        UNICODE_STRING game = RTL_CONSTANT_STRING(L"forzahorizon6.exe");
        unsigned int i;
        LONG statistics = 1, resume_bridge = 0;
        mode = 0;
        for (i = 0; i < path->Length / sizeof(WCHAR); ++i)
            if (path->Buffer[i] == '\\' || path->Buffer[i] == '/')
            {
                base.Buffer = path->Buffer + i + 1;
                base.Length = path->Length - (i + 1) * sizeof(WCHAR);
            }
        base.MaximumLength = base.Length;
        if (nt && !RtlQueryEnvironmentVariable_U(NULL, &name, &value))
        {
            if (value.Length == 5 * sizeof(WCHAR) && !memcmp(buffer, L"probe", value.Length)
                && RtlEqualUnicodeString(&base, &probe, TRUE)) mode = 1;
            if (value.Length == 11 * sizeof(WCHAR) && !memcmp(buffer, L"probe-clean", value.Length)
                && RtlEqualUnicodeString(&base, &probe, TRUE)) mode = 3;
            /* Header guard is additional to deployment's full executable SHA256.
             * No fixed instruction RVA is used by this optimization. */
            if (value.Length == 1 * sizeof(WCHAR) && buffer[0] == '1'
                && RtlEqualUnicodeString(&base, &game, TRUE)
                && nt->FileHeader.Machine == IMAGE_FILE_MACHINE_AMD64
                && nt->FileHeader.TimeDateStamp == 0x6aea6132
                && nt->OptionalHeader.SizeOfImage == 0x0b3fd000
                && nt->OptionalHeader.CheckSum == 0x0afc4fc1) mode = 2;
        }
        {
            UNICODE_STRING stats_name = RTL_CONSTANT_STRING(L"WINE_SOFTWARE_EXCEPTION_STATS");
            value.Length = 0;
            if (!RtlQueryEnvironmentVariable_U(NULL, &stats_name, &value)
                && value.Length == sizeof(WCHAR) && buffer[0] == '0') statistics = 0;
        }
        {
            UNICODE_STRING resume_name = RTL_CONSTANT_STRING(L"WINE_SOFTWARE_BRIDGE_RESUME");
            value.Length = 0;
            if (!RtlQueryEnvironmentVariable_U(NULL, &resume_name, &value)
                && value.Length == sizeof(WCHAR) && buffer[0] == '1') resume_bridge = 1;
        }
        {
            LONG enabled=(mode==1 || mode==3);
            UNICODE_STRING alu_name = RTL_CONSTANT_STRING(L"WINE_SOFTWARE_ALU_BRIDGE");
            value.Length=0;
            if(!RtlQueryEnvironmentVariable_U(NULL,&alu_name,&value) && value.Length==sizeof(WCHAR))
            {
                if(buffer[0]=='0')enabled=0;
                else if(buffer[0]=='1')enabled=1;
            }
            InterlockedCompareExchange(&software_alu_enabled,enabled,-1);
        }
        InterlockedExchange(&software_legacy_d5,software_legacy_d5_available());
        InterlockedCompareExchange(&software_bridge_resume, resume_bridge, -1);
        /* Publish policy before the mode. Every initializer reads the same
         * immutable startup environment; no per-exception environment lookup. */
        InterlockedCompareExchange(&software_chain_statistics, statistics, -1);
        InterlockedCompareExchange(&software_chain_mode, mode, -1);
        mode = software_chain_mode;
    }
    if (mode) burst_configure();
    return mode != 0 && !NtCurrentTeb()->Peb->BeingDebugged;
}


/* Bounded in-memory diagnostic. No synchronous per-exception log output.
 * Per row: thread ID, then twenty {count, before RIP, after RIP, a, b} groups.
 * Reasons are mutually exclusive first-exit reasons, not independent predicates.
 * These captures are for classification, not unbiased performance measurement. */
LONG64 __wine_software_exception_chain_diagnostics[64][101];
static LONG64 *software_chain_diag_row(void)
{
    LONG64 tid;
    unsigned int i;
    /* Detailed diagnostics are private-probe-only in this build. FH6 keeps
     * aggregate counters but performs no per-thread scan or opcode census. */
    if (software_chain_mode != 1) return NULL;
    tid = HandleToULong(NtCurrentTeb()->ClientId.UniqueThread);
    for (i=0;i<64;i++)
    {
        LONG64 seen=InterlockedCompareExchange64(&__wine_software_exception_chain_diagnostics[i][0],tid,0);
        if (!seen || seen==tid) return __wine_software_exception_chain_diagnostics[i];
    }
    return NULL;
}
static void software_chain_diag(LONG64 *row,unsigned int reason,const CONTEXT *before,
                                const CONTEXT *after,ULONG64 a,ULONG64 b)
{
    LONG64 *p;
    if (!row) return;
    p=row+1+reason*5;
    if (InterlockedIncrement64(p)==1)
    {
        p[1]=before->Rip; p[2]=after->Rip; p[3]=a; p[4]=b;
    }
}
static unsigned int software_chain_state_reason(const CONTEXT *before,const CONTEXT *after,
                                                ULONG64 *a,ULONG64 *b)
{
    const DWORD arithmetic_and_direction=0xcd5;
    USHORT current_cs;
    __asm__("movw %%cs,%0":"=r"(current_cs));
#define REJECT_IF(test,reason,x,y) if(test){*a=(x);*b=(y);return reason;}
    REJECT_IF(!__wine_software_exception_chain_context_valid(before->ContextFlags)
        || !__wine_software_exception_chain_context_valid(after->ContextFlags),7,before->ContextFlags,after->ContextFlags);
    REJECT_IF(after->SegCs!=current_cs,5,current_cs,after->SegCs);
    REJECT_IF(before->Rsp!=after->Rsp,6,before->Rsp,after->Rsp);
    REJECT_IF(before->ContextFlags!=after->ContextFlags,7,before->ContextFlags,after->ContextFlags);
    REJECT_IF((after->ContextFlags & CONTEXT_XSTATE)==CONTEXT_XSTATE,8,before->ContextFlags,after->ContextFlags);
    REJECT_IF(after->EFlags & 0x100,9,before->EFlags,after->EFlags);
    REJECT_IF((before->EFlags ^ after->EFlags) & ~arithmetic_and_direction,10,before->EFlags,after->EFlags);
    REJECT_IF(after->Dr7 & 0x20ff,11,before->Dr7,after->Dr7);
    REJECT_IF(before->Dr0!=after->Dr0 || before->Dr1!=after->Dr1 || before->Dr2!=after->Dr2
        || before->Dr3!=after->Dr3 || before->Dr6!=after->Dr6 || before->Dr7!=after->Dr7,12,before->Dr7,after->Dr7);
    REJECT_IF(before->SegCs!=after->SegCs || before->SegSs!=after->SegSs || before->SegDs!=after->SegDs
        || before->SegEs!=after->SegEs || before->SegFs!=after->SegFs || before->SegGs!=after->SegGs,13,before->SegSs,after->SegSs);
    REJECT_IF(before->MxCsr!=after->MxCsr || memcmp(&before->FltSave,&after->FltSave,sizeof(after->FltSave)),14,before->MxCsr,after->MxCsr);
#undef REJECT_IF
    return 0;
}


/* Diagnostic-only bounded trace. Existing validator bytes/results are copied;
 * no extra guest reads, handler calls, memory queries or context changes.
 * Publication follows the PE timing recorder: reserve, populate, ready, drain.
 * control: opt-in, reserved count, dropped, active, capacity, record size,
 * version, reserved. All storage is prefaulted before the capture window. */
#define REFUSAL_CAPACITY 262144
LONG64 __wine_bridge_refusal_control[8]={0,0,0,0,REFUSAL_CAPACITY,80,1,0};
struct bridge_refusal_record
{
    LONG64 begin,end;
    ULONG64 rip,target;
    BYTE code[16];
    ULONG64 detail;
    ULONG tid,outcome,valid,length,next;
    LONG ready;
};
C_ASSERT(sizeof(struct bridge_refusal_record)==80);
struct bridge_refusal_record __wine_bridge_refusal_records[REFUSAL_CAPACITY];
extern LONG64 __wine_exception_burst_control[8];
static LONG64 burst_clock(void);
static struct bridge_refusal_record *bridge_refusal_begin(CONTEXT *context)
{
    LONG64 index;struct bridge_refusal_record *r;
    if(!__wine_bridge_refusal_control[0] || !__wine_exception_burst_control[0])return NULL;
    InterlockedIncrement64(&__wine_bridge_refusal_control[3]);
    if(!__wine_bridge_refusal_control[0] || !__wine_exception_burst_control[0])goto unreserved;
    index=InterlockedIncrement64(&__wine_bridge_refusal_control[1])-1;
    if(index>=REFUSAL_CAPACITY){InterlockedIncrement64(&__wine_bridge_refusal_control[2]);goto unreserved;}
    r=&__wine_bridge_refusal_records[index];r->begin=burst_clock();r->rip=context->Rip;
    r->tid=HandleToULong(NtCurrentTeb()->ClientId.UniqueThread);return r;
unreserved:
    InterlockedDecrement64(&__wine_bridge_refusal_control[3]);return NULL;
}
static void bridge_refusal_end(struct bridge_refusal_record *r,ULONG outcome,ULONG64 detail)
{
    if(!r)return;
    r->outcome=outcome;r->detail=detail;r->end=burst_clock();
    InterlockedExchange(&r->ready,1);InterlockedDecrement64(&__wine_bridge_refusal_control[3]);
}

/* Diagnostic census reads bytes at handler-return time. Opcode family buckets
 * ignore operand-size/REX prefixes for grouping only, not for execution.
 * [attempts, accepted, template refusal, target refusal, data refusal, RIP, bytes0, bytes1]. */
LONG64 __wine_software_exception_bridge_census[64][512][8];
static LONG64 *software_bridge_census(CONTEXT *context,LONG64 *row)
{
    BYTE code[16];SIZE_T bytes;unsigned int n=0,key;LONG64 *entry;
    if(!row || NtReadVirtualMemory(GetCurrentProcess(),(void*)context->Rip,code,sizeof code,&bytes) || bytes!=sizeof code)return NULL;
    while(n<8 && ((code[n]>=0x40 && code[n]<=0x4f) || code[n]==0x66 || code[n]==0xf2 || code[n]==0xf3))n++;
    key=code[n]==0x0f?256+code[n+1]:code[n];
    entry=__wine_software_exception_bridge_census[(row-&__wine_software_exception_chain_diagnostics[0][0])/101][key];
    if(InterlockedIncrement64(entry)==1){entry[5]=context->Rip;memcpy(entry+6,code,16);}
    return entry;
}

/* No-flag-change register bridge evaluator. Supports only complete canonical
 * legacy encodings with register operands; never executes a memory store.
 * Effects remain staged until the current relative-jump target is validated. */
struct software_bridge_effect {unsigned int length,dst,vector,no_write,flags_valid;DWORD flags;ULONG64 value[2];};
static ULONG64 *software_bridge_gpr(CONTEXT *c,unsigned int n)
{
    switch(n){case 0:return &c->Rax;case 1:return &c->Rcx;case 2:return &c->Rdx;case 3:return &c->Rbx;
    case 4:return &c->Rsp;case 5:return &c->Rbp;case 6:return &c->Rsi;case 7:return &c->Rdi;
    case 8:return &c->R8;case 9:return &c->R9;case 10:return &c->R10;case 11:return &c->R11;
    case 12:return &c->R12;case 13:return &c->R13;case 14:return &c->R14;case 15:return &c->R15;default:return NULL;}
}
/* Execute register-only arithmetic on temporary values. Seed only arithmetic
 * flags: never load guest TF/DF/IF or other control bits into the host handler.
 * The operation and PUSHFQ materialization run in one asm block so undefined
 * arithmetic bits follow this x86 runtime too, rather than invented C values.
 * No guest context effects are committed until the existing jump/target checks
 * succeed. Unsupported widths, memory operands, stack writes and prefixes fall
 * back unchanged. */
static void software_bridge_alu(unsigned int operation,unsigned int width,
                                ULONG64 left,ULONG64 right,DWORD initial_flags,
                                ULONG64 *result,DWORD *flags)
{
    ULONG64 seed, observed;
    __asm__ volatile("pushfq; popq %0" : "=r"(seed) :: "memory");
    seed=(seed & ~(ULONG64)0x8d5) | (initial_flags & 0x8d5);
#define ALU_ASM(insn,suffix,operand) \
    __asm__ volatile("pushq %[seed]; popfq; " insn suffix " " operand "; pushfq; popq %[flags]" \
                     : [left] "+&r"(left), [flags] "=&r"(observed) \
                     : [right] "r"(right), [seed] "r"(seed) : "cc","memory")
#define ALU_CASE(op,insn) case op: if(width==64){ALU_ASM(insn,"q","%[right],%[left]");} \
                                  else{ALU_ASM(insn,"l","%k[right],%k[left]");} break
    switch(operation)
    {
        ALU_CASE(0,"add"); ALU_CASE(1,"or"); ALU_CASE(4,"and");
        ALU_CASE(5,"sub"); ALU_CASE(6,"xor"); ALU_CASE(7,"cmp");
        ALU_CASE(8,"test");
        case 9:
            if(width==64)
                __asm__ volatile("pushq %[seed]; popfq; shrq %%cl,%[left]; pushfq; popq %[flags]"
                    : [left] "+&r"(left),[flags] "=&r"(observed)
                    : "c"(right),[seed] "r"(seed) : "cc","memory");
            else
                __asm__ volatile("pushq %[seed]; popfq; shrl %%cl,%k[left]; pushfq; popq %[flags]"
                    : [left] "+&r"(left),[flags] "=&r"(observed)
                    : "c"(right),[seed] "r"(seed) : "cc","memory");
            break;
        /* Rosetta can materialize undefined OF differently for immediate
         * versus CL shifts. Execute the original immediate form, including
         * its complete imm8 value; do not substitute a CL instruction. */
        case 10:
#define SHIFT_IMM(n) case n: \
            if(width==64) \
                __asm__ volatile("pushq %[seed]; popfq; shrq $" #n ",%[left]; pushfq; popq %[flags]" \
                    : [left] "+&r"(left),[flags] "=&r"(observed) : [seed] "r"(seed) : "cc","memory"); \
            else \
                __asm__ volatile("pushq %[seed]; popfq; shrl $" #n ",%k[left]; pushfq; popq %[flags]" \
                    : [left] "+&r"(left),[flags] "=&r"(observed) : [seed] "r"(seed) : "cc","memory"); \
            break
            switch((unsigned int)right & 255)
            {
                SHIFT_IMM(0); SHIFT_IMM(1); SHIFT_IMM(2); SHIFT_IMM(3); SHIFT_IMM(4); SHIFT_IMM(5); SHIFT_IMM(6); SHIFT_IMM(7);
                SHIFT_IMM(8); SHIFT_IMM(9); SHIFT_IMM(10); SHIFT_IMM(11); SHIFT_IMM(12); SHIFT_IMM(13); SHIFT_IMM(14); SHIFT_IMM(15);
                SHIFT_IMM(16); SHIFT_IMM(17); SHIFT_IMM(18); SHIFT_IMM(19); SHIFT_IMM(20); SHIFT_IMM(21); SHIFT_IMM(22); SHIFT_IMM(23);
                SHIFT_IMM(24); SHIFT_IMM(25); SHIFT_IMM(26); SHIFT_IMM(27); SHIFT_IMM(28); SHIFT_IMM(29); SHIFT_IMM(30); SHIFT_IMM(31);
                SHIFT_IMM(32); SHIFT_IMM(33); SHIFT_IMM(34); SHIFT_IMM(35); SHIFT_IMM(36); SHIFT_IMM(37); SHIFT_IMM(38); SHIFT_IMM(39);
                SHIFT_IMM(40); SHIFT_IMM(41); SHIFT_IMM(42); SHIFT_IMM(43); SHIFT_IMM(44); SHIFT_IMM(45); SHIFT_IMM(46); SHIFT_IMM(47);
                SHIFT_IMM(48); SHIFT_IMM(49); SHIFT_IMM(50); SHIFT_IMM(51); SHIFT_IMM(52); SHIFT_IMM(53); SHIFT_IMM(54); SHIFT_IMM(55);
                SHIFT_IMM(56); SHIFT_IMM(57); SHIFT_IMM(58); SHIFT_IMM(59); SHIFT_IMM(60); SHIFT_IMM(61); SHIFT_IMM(62); SHIFT_IMM(63);
                SHIFT_IMM(64); SHIFT_IMM(65); SHIFT_IMM(66); SHIFT_IMM(67); SHIFT_IMM(68); SHIFT_IMM(69); SHIFT_IMM(70); SHIFT_IMM(71);
                SHIFT_IMM(72); SHIFT_IMM(73); SHIFT_IMM(74); SHIFT_IMM(75); SHIFT_IMM(76); SHIFT_IMM(77); SHIFT_IMM(78); SHIFT_IMM(79);
                SHIFT_IMM(80); SHIFT_IMM(81); SHIFT_IMM(82); SHIFT_IMM(83); SHIFT_IMM(84); SHIFT_IMM(85); SHIFT_IMM(86); SHIFT_IMM(87);
                SHIFT_IMM(88); SHIFT_IMM(89); SHIFT_IMM(90); SHIFT_IMM(91); SHIFT_IMM(92); SHIFT_IMM(93); SHIFT_IMM(94); SHIFT_IMM(95);
                SHIFT_IMM(96); SHIFT_IMM(97); SHIFT_IMM(98); SHIFT_IMM(99); SHIFT_IMM(100); SHIFT_IMM(101); SHIFT_IMM(102); SHIFT_IMM(103);
                SHIFT_IMM(104); SHIFT_IMM(105); SHIFT_IMM(106); SHIFT_IMM(107); SHIFT_IMM(108); SHIFT_IMM(109); SHIFT_IMM(110); SHIFT_IMM(111);
                SHIFT_IMM(112); SHIFT_IMM(113); SHIFT_IMM(114); SHIFT_IMM(115); SHIFT_IMM(116); SHIFT_IMM(117); SHIFT_IMM(118); SHIFT_IMM(119);
                SHIFT_IMM(120); SHIFT_IMM(121); SHIFT_IMM(122); SHIFT_IMM(123); SHIFT_IMM(124); SHIFT_IMM(125); SHIFT_IMM(126); SHIFT_IMM(127);
                SHIFT_IMM(128); SHIFT_IMM(129); SHIFT_IMM(130); SHIFT_IMM(131); SHIFT_IMM(132); SHIFT_IMM(133); SHIFT_IMM(134); SHIFT_IMM(135);
                SHIFT_IMM(136); SHIFT_IMM(137); SHIFT_IMM(138); SHIFT_IMM(139); SHIFT_IMM(140); SHIFT_IMM(141); SHIFT_IMM(142); SHIFT_IMM(143);
                SHIFT_IMM(144); SHIFT_IMM(145); SHIFT_IMM(146); SHIFT_IMM(147); SHIFT_IMM(148); SHIFT_IMM(149); SHIFT_IMM(150); SHIFT_IMM(151);
                SHIFT_IMM(152); SHIFT_IMM(153); SHIFT_IMM(154); SHIFT_IMM(155); SHIFT_IMM(156); SHIFT_IMM(157); SHIFT_IMM(158); SHIFT_IMM(159);
                SHIFT_IMM(160); SHIFT_IMM(161); SHIFT_IMM(162); SHIFT_IMM(163); SHIFT_IMM(164); SHIFT_IMM(165); SHIFT_IMM(166); SHIFT_IMM(167);
                SHIFT_IMM(168); SHIFT_IMM(169); SHIFT_IMM(170); SHIFT_IMM(171); SHIFT_IMM(172); SHIFT_IMM(173); SHIFT_IMM(174); SHIFT_IMM(175);
                SHIFT_IMM(176); SHIFT_IMM(177); SHIFT_IMM(178); SHIFT_IMM(179); SHIFT_IMM(180); SHIFT_IMM(181); SHIFT_IMM(182); SHIFT_IMM(183);
                SHIFT_IMM(184); SHIFT_IMM(185); SHIFT_IMM(186); SHIFT_IMM(187); SHIFT_IMM(188); SHIFT_IMM(189); SHIFT_IMM(190); SHIFT_IMM(191);
                SHIFT_IMM(192); SHIFT_IMM(193); SHIFT_IMM(194); SHIFT_IMM(195); SHIFT_IMM(196); SHIFT_IMM(197); SHIFT_IMM(198); SHIFT_IMM(199);
                SHIFT_IMM(200); SHIFT_IMM(201); SHIFT_IMM(202); SHIFT_IMM(203); SHIFT_IMM(204); SHIFT_IMM(205); SHIFT_IMM(206); SHIFT_IMM(207);
                SHIFT_IMM(208); SHIFT_IMM(209); SHIFT_IMM(210); SHIFT_IMM(211); SHIFT_IMM(212); SHIFT_IMM(213); SHIFT_IMM(214); SHIFT_IMM(215);
                SHIFT_IMM(216); SHIFT_IMM(217); SHIFT_IMM(218); SHIFT_IMM(219); SHIFT_IMM(220); SHIFT_IMM(221); SHIFT_IMM(222); SHIFT_IMM(223);
                SHIFT_IMM(224); SHIFT_IMM(225); SHIFT_IMM(226); SHIFT_IMM(227); SHIFT_IMM(228); SHIFT_IMM(229); SHIFT_IMM(230); SHIFT_IMM(231);
                SHIFT_IMM(232); SHIFT_IMM(233); SHIFT_IMM(234); SHIFT_IMM(235); SHIFT_IMM(236); SHIFT_IMM(237); SHIFT_IMM(238); SHIFT_IMM(239);
                SHIFT_IMM(240); SHIFT_IMM(241); SHIFT_IMM(242); SHIFT_IMM(243); SHIFT_IMM(244); SHIFT_IMM(245); SHIFT_IMM(246); SHIFT_IMM(247);
                SHIFT_IMM(248); SHIFT_IMM(249); SHIFT_IMM(250); SHIFT_IMM(251); SHIFT_IMM(252); SHIFT_IMM(253); SHIFT_IMM(254); SHIFT_IMM(255);
            }
#undef SHIFT_IMM
            break;
        case 11:
            if(width==64)
                __asm__ volatile("pushq %[seed]; popfq; shlq %%cl,%[left]; pushfq; popq %[flags]"
                    : [left] "+&r"(left),[flags] "=&r"(observed)
                    : "c"(right),[seed] "r"(seed) : "cc","memory");
            else
                __asm__ volatile("pushq %[seed]; popfq; shll %%cl,%k[left]; pushfq; popq %[flags]"
                    : [left] "+&r"(left),[flags] "=&r"(observed)
                    : "c"(right),[seed] "r"(seed) : "cc","memory");
            break;
        /* Rosetta can materialize undefined OF differently for immediate
         * versus CL shifts. Execute the original immediate form, including
         * its complete imm8 value; do not substitute a CL instruction. */
        case 12:
#define SHIFT_IMM(n) case n: \
            if(width==64) \
                __asm__ volatile("pushq %[seed]; popfq; shlq $" #n ",%[left]; pushfq; popq %[flags]" \
                    : [left] "+&r"(left),[flags] "=&r"(observed) : [seed] "r"(seed) : "cc","memory"); \
            else \
                __asm__ volatile("pushq %[seed]; popfq; shll $" #n ",%k[left]; pushfq; popq %[flags]" \
                    : [left] "+&r"(left),[flags] "=&r"(observed) : [seed] "r"(seed) : "cc","memory"); \
            break
            switch((unsigned int)right & 255)
            {
                SHIFT_IMM(0); SHIFT_IMM(1); SHIFT_IMM(2); SHIFT_IMM(3); SHIFT_IMM(4); SHIFT_IMM(5); SHIFT_IMM(6); SHIFT_IMM(7);
                SHIFT_IMM(8); SHIFT_IMM(9); SHIFT_IMM(10); SHIFT_IMM(11); SHIFT_IMM(12); SHIFT_IMM(13); SHIFT_IMM(14); SHIFT_IMM(15);
                SHIFT_IMM(16); SHIFT_IMM(17); SHIFT_IMM(18); SHIFT_IMM(19); SHIFT_IMM(20); SHIFT_IMM(21); SHIFT_IMM(22); SHIFT_IMM(23);
                SHIFT_IMM(24); SHIFT_IMM(25); SHIFT_IMM(26); SHIFT_IMM(27); SHIFT_IMM(28); SHIFT_IMM(29); SHIFT_IMM(30); SHIFT_IMM(31);
                SHIFT_IMM(32); SHIFT_IMM(33); SHIFT_IMM(34); SHIFT_IMM(35); SHIFT_IMM(36); SHIFT_IMM(37); SHIFT_IMM(38); SHIFT_IMM(39);
                SHIFT_IMM(40); SHIFT_IMM(41); SHIFT_IMM(42); SHIFT_IMM(43); SHIFT_IMM(44); SHIFT_IMM(45); SHIFT_IMM(46); SHIFT_IMM(47);
                SHIFT_IMM(48); SHIFT_IMM(49); SHIFT_IMM(50); SHIFT_IMM(51); SHIFT_IMM(52); SHIFT_IMM(53); SHIFT_IMM(54); SHIFT_IMM(55);
                SHIFT_IMM(56); SHIFT_IMM(57); SHIFT_IMM(58); SHIFT_IMM(59); SHIFT_IMM(60); SHIFT_IMM(61); SHIFT_IMM(62); SHIFT_IMM(63);
                SHIFT_IMM(64); SHIFT_IMM(65); SHIFT_IMM(66); SHIFT_IMM(67); SHIFT_IMM(68); SHIFT_IMM(69); SHIFT_IMM(70); SHIFT_IMM(71);
                SHIFT_IMM(72); SHIFT_IMM(73); SHIFT_IMM(74); SHIFT_IMM(75); SHIFT_IMM(76); SHIFT_IMM(77); SHIFT_IMM(78); SHIFT_IMM(79);
                SHIFT_IMM(80); SHIFT_IMM(81); SHIFT_IMM(82); SHIFT_IMM(83); SHIFT_IMM(84); SHIFT_IMM(85); SHIFT_IMM(86); SHIFT_IMM(87);
                SHIFT_IMM(88); SHIFT_IMM(89); SHIFT_IMM(90); SHIFT_IMM(91); SHIFT_IMM(92); SHIFT_IMM(93); SHIFT_IMM(94); SHIFT_IMM(95);
                SHIFT_IMM(96); SHIFT_IMM(97); SHIFT_IMM(98); SHIFT_IMM(99); SHIFT_IMM(100); SHIFT_IMM(101); SHIFT_IMM(102); SHIFT_IMM(103);
                SHIFT_IMM(104); SHIFT_IMM(105); SHIFT_IMM(106); SHIFT_IMM(107); SHIFT_IMM(108); SHIFT_IMM(109); SHIFT_IMM(110); SHIFT_IMM(111);
                SHIFT_IMM(112); SHIFT_IMM(113); SHIFT_IMM(114); SHIFT_IMM(115); SHIFT_IMM(116); SHIFT_IMM(117); SHIFT_IMM(118); SHIFT_IMM(119);
                SHIFT_IMM(120); SHIFT_IMM(121); SHIFT_IMM(122); SHIFT_IMM(123); SHIFT_IMM(124); SHIFT_IMM(125); SHIFT_IMM(126); SHIFT_IMM(127);
                SHIFT_IMM(128); SHIFT_IMM(129); SHIFT_IMM(130); SHIFT_IMM(131); SHIFT_IMM(132); SHIFT_IMM(133); SHIFT_IMM(134); SHIFT_IMM(135);
                SHIFT_IMM(136); SHIFT_IMM(137); SHIFT_IMM(138); SHIFT_IMM(139); SHIFT_IMM(140); SHIFT_IMM(141); SHIFT_IMM(142); SHIFT_IMM(143);
                SHIFT_IMM(144); SHIFT_IMM(145); SHIFT_IMM(146); SHIFT_IMM(147); SHIFT_IMM(148); SHIFT_IMM(149); SHIFT_IMM(150); SHIFT_IMM(151);
                SHIFT_IMM(152); SHIFT_IMM(153); SHIFT_IMM(154); SHIFT_IMM(155); SHIFT_IMM(156); SHIFT_IMM(157); SHIFT_IMM(158); SHIFT_IMM(159);
                SHIFT_IMM(160); SHIFT_IMM(161); SHIFT_IMM(162); SHIFT_IMM(163); SHIFT_IMM(164); SHIFT_IMM(165); SHIFT_IMM(166); SHIFT_IMM(167);
                SHIFT_IMM(168); SHIFT_IMM(169); SHIFT_IMM(170); SHIFT_IMM(171); SHIFT_IMM(172); SHIFT_IMM(173); SHIFT_IMM(174); SHIFT_IMM(175);
                SHIFT_IMM(176); SHIFT_IMM(177); SHIFT_IMM(178); SHIFT_IMM(179); SHIFT_IMM(180); SHIFT_IMM(181); SHIFT_IMM(182); SHIFT_IMM(183);
                SHIFT_IMM(184); SHIFT_IMM(185); SHIFT_IMM(186); SHIFT_IMM(187); SHIFT_IMM(188); SHIFT_IMM(189); SHIFT_IMM(190); SHIFT_IMM(191);
                SHIFT_IMM(192); SHIFT_IMM(193); SHIFT_IMM(194); SHIFT_IMM(195); SHIFT_IMM(196); SHIFT_IMM(197); SHIFT_IMM(198); SHIFT_IMM(199);
                SHIFT_IMM(200); SHIFT_IMM(201); SHIFT_IMM(202); SHIFT_IMM(203); SHIFT_IMM(204); SHIFT_IMM(205); SHIFT_IMM(206); SHIFT_IMM(207);
                SHIFT_IMM(208); SHIFT_IMM(209); SHIFT_IMM(210); SHIFT_IMM(211); SHIFT_IMM(212); SHIFT_IMM(213); SHIFT_IMM(214); SHIFT_IMM(215);
                SHIFT_IMM(216); SHIFT_IMM(217); SHIFT_IMM(218); SHIFT_IMM(219); SHIFT_IMM(220); SHIFT_IMM(221); SHIFT_IMM(222); SHIFT_IMM(223);
                SHIFT_IMM(224); SHIFT_IMM(225); SHIFT_IMM(226); SHIFT_IMM(227); SHIFT_IMM(228); SHIFT_IMM(229); SHIFT_IMM(230); SHIFT_IMM(231);
                SHIFT_IMM(232); SHIFT_IMM(233); SHIFT_IMM(234); SHIFT_IMM(235); SHIFT_IMM(236); SHIFT_IMM(237); SHIFT_IMM(238); SHIFT_IMM(239);
                SHIFT_IMM(240); SHIFT_IMM(241); SHIFT_IMM(242); SHIFT_IMM(243); SHIFT_IMM(244); SHIFT_IMM(245); SHIFT_IMM(246); SHIFT_IMM(247);
                SHIFT_IMM(248); SHIFT_IMM(249); SHIFT_IMM(250); SHIFT_IMM(251); SHIFT_IMM(252); SHIFT_IMM(253); SHIFT_IMM(254); SHIFT_IMM(255);
            }
#undef SHIFT_IMM
            break;
        default: *result=left;*flags=initial_flags;return;
    }
    *result=left;*flags=(initial_flags & ~0x8d5) | (observed & 0x8d5);
#undef ALU_CASE
#undef ALU_ASM
}
static BOOL software_bridge_arithmetic(const BYTE *code,CONTEXT *c,struct software_bridge_effect *e)
{
    unsigned int p=0,rex=0,op,m,reg,rm,width,operation=0,dst=0,no_write=0;
    ULONG64 left=0,right=0;LONG imm32; signed char imm8;
    memset(e,0,sizeof(*e));
    if(code[p]>=0x40 && code[p]<=0x4f)rex=code[p++];
    width=(rex&8)?64:32;op=code[p++];
    if(op>=0xb8 && op<=0xbf)
    {
        dst=op-0xb8+((rex&1)?8:0);if(dst==4 || (rex&6))return FALSE;
        if(width==64){memcpy(&e->value[0],code+p,8);p+=8;}
        else{ULONG value;memcpy(&value,code+p,4);e->value[0]=value;p+=4;}
        e->dst=dst;e->length=p;return TRUE;
    }
    if(op==0x81 || op==0x83 || op==0xc1 || op==0xd3 || op==0xf7)
    {
        m=code[p++];if((m&0xc0)!=0xc0 || (rex&6))return FALSE;
        operation=(m>>3)&7;dst=(m&7)+((rex&1)?8:0);
        no_write=(op==0x81 || op==0x83) && operation==7;
        if(dst==4 && !no_write)return FALSE;
        left=*software_bridge_gpr(c,dst);
        if(op==0xf7)
        {
            if(operation!=2)return FALSE;
            e->value[0]=width==64?~left:(ULONG)~left;e->dst=dst;e->length=p;return TRUE;
        }
        if(op==0xc1 || op==0xd3)
        {
            if(operation!=4 && operation!=5)return FALSE;
            operation=operation==4?(op==0xc1?12:11):(op==0xc1?10:9);
            right=op==0xc1?code[p++]:c->Rcx;
        }
        else
        {
            if(operation==2 || operation==3)return FALSE;
            if(op==0x83){memcpy(&imm8,code+p,1);p++;right=(LONG64)imm8;}
            else{memcpy(&imm32,code+p,4);p+=4;right=(LONG64)imm32;}
        }
    }
    else if(op==0x05 || op==0x0d || op==0x25 || op==0x2d || op==0x35 || op==0x3d)
    {
        if(rex&7)return FALSE;
        operation=(op>>3)&7;dst=0;no_write=operation==7;left=c->Rax;
        memcpy(&imm32,code+p,4);p+=4;right=(LONG64)imm32;
    }
    else
    {
        switch(op)
        {
            case 0x01:case 0x03:operation=0;break;
            case 0x09:case 0x0b:operation=1;break;
            case 0x21:case 0x23:operation=4;break;
            case 0x29:case 0x2b:operation=5;break;
            case 0x31:case 0x33:operation=6;break;
            case 0x39:case 0x3b:operation=7;no_write=1;break;
            case 0x85:operation=8;no_write=1;break;
            default:return FALSE;
        }
        m=code[p++];if((m&0xc0)!=0xc0 || (rex&2))return FALSE;
        reg=((m>>3)&7)+((rex&4)?8:0);rm=(m&7)+((rex&1)?8:0);
        dst=(op&2)?reg:rm;right=*software_bridge_gpr(c,(op&2)?rm:reg);
        if(dst==4 && !no_write)return FALSE;
        left=*software_bridge_gpr(c,dst);
    }
    e->dst=dst;e->length=p;e->no_write=no_write;e->flags_valid=1;
    software_bridge_alu(operation,width,left,right,c->EFlags,&e->value[0],&e->flags);
    return TRUE;
}

static BOOL software_bridge_registers(const BYTE *code,CONTEXT *c,struct software_bridge_effect *e)
{
    unsigned int p=0,p66=0,rex=0,op,m,reg,rm,width,i;
    ULONG64 value,src[2],dst[2];ULONG lanes[4],output[4];
    memset(e,0,sizeof(*e));
    if(code[p]==0x66){p66=1;p++;}
    if(code[p]>=0x40 && code[p]<=0x4f)rex=code[p++];
    op=code[p++];
    if(op==0x8b || op==0x89){
        m=code[p++];if((m&0xc0)!=0xc0)return FALSE;
        reg=((m>>3)&7)+((rex&4)?8:0);rm=(m&7)+((rex&1)?8:0);
        e->dst=op==0x8b?reg:rm;if(e->dst==4)return FALSE;
        value=*software_bridge_gpr(c,op==0x8b?rm:reg);width=(rex&8)?64:p66?16:32;
        e->value[0]=width==64?value:width==32?(ULONG)value:(*software_bridge_gpr(c,e->dst)&~(ULONG64)0xffff)|(value&0xffff);
        e->length=p;return TRUE;
    }
    if(op!=0x0f || !p66)return FALSE;
    op=code[p++];m=code[p++];if((m&0xc0)!=0xc0)return FALSE;
    reg=((m>>3)&7)+((rex&4)?8:0);rm=(m&7)+((rex&1)?8:0);
    if(op==0x7e){
        e->dst=rm;if(rm==4)return FALSE;
        value=c->FltSave.XmmRegisters[reg].Low;e->value[0]=(rex&8)?value:(ULONG)value;e->length=p;return TRUE;
    }
    if(op!=0x6f && op!=0x70 && op!=0xd4)return FALSE;
    memcpy(src,&c->FltSave.XmmRegisters[rm],16);memcpy(dst,&c->FltSave.XmmRegisters[reg],16);
    e->dst=reg;e->vector=1;
    if(op==0x6f)memcpy(e->value,src,16);
    else if(op==0xd4){e->value[0]=dst[0]+src[0];e->value[1]=dst[1]+src[1];}
    else{unsigned int imm=code[p++];memcpy(lanes,src,16);for(i=0;i<4;i++)output[i]=lanes[(imm>>(2*i))&3];memcpy(e->value,output,16);}
    e->length=p;return TRUE;
}
/* Mode-invalid multi-byte instructions still require their encoded bytes to
 * be fetchable on this runtime. At a page boundary the real fault can be an
 * execute access violation, not #UD. Never synthesize over that fault.
 * Rosetta also faults in fixtures where the nominal 2/7-byte encoding fits
 * but the following page is inaccessible. Conservatively require the complete
 * 16-byte decoder window inside one executable region and verify readability.
 * This is an eligibility guard, not a change to the actual fallback fault. */
static BOOL software_chain_target_ud(BYTE opcode,ULONG_PTR address,const MEMORY_BASIC_INFORMATION *info)
{
    SIZE_T size=1,bytes=0;BYTE code[16];ULONG_PTR offset=address-(ULONG_PTR)info->BaseAddress;
    if(!software_guaranteed_ud_byte(opcode,software_legacy_d5))return FALSE;
    if(opcode==0xd4 || opcode==0xd5 || opcode==0x9a)size=sizeof code;
    if(size==1)return TRUE;
    if(offset>info->RegionSize || info->RegionSize-offset<size)return FALSE;
    if(NtReadVirtualMemory(GetCurrentProcess(),(void*)address,code,size,&bytes) || bytes!=size)return FALSE;
    return code[0]==opcode;
}

/* The seven-byte byte-load bridge remains supported. New register/SIMD cases
 * read fresh code and preserve legacy SIMD upper lanes, MXCSR and EFLAGS.
 * VEX/EVEX, memory SIMD operands, memory writes and stack destinations remain
 * unsupported. Supported arithmetic stages its flags before validation; all
 * refusal paths leave the original guest context intact. */
/* 0: fallback unchanged; 1: next real opcode is #UD; 2: resume normal code. */
static unsigned int software_chain_load_bridge(CONTEXT *context,LONG64 *row)
{
    MEMORY_BASIC_INFORMATION info;SIZE_T bytes;BYTE code[16],next,value;
    LONG64 *entry;LONG displacement;struct software_bridge_effect effect;NTSTATUS status;
    BOOL byte_load, next_is_ud=TRUE;ULONG_PTR base=(ULONG_PTR)NtCurrentTeb()->Peb->ImageBaseAddress,target;
    IMAGE_NT_HEADERS *nt=RtlImageNtHeader((void*)base);
    struct bridge_refusal_record *trace;
    software_chain_count(3);trace=bridge_refusal_begin(context);
#define REFUSE_EARLY(reason,detail) do{bridge_refusal_end(trace,reason,detail);return FALSE;}while(0)
    if(!nt)REFUSE_EARLY(3,0);
    status=NtQueryVirtualMemory(GetCurrentProcess(),(void*)context->Rip,MemoryBasicInformation,&info,sizeof info,NULL);
    if(status)REFUSE_EARLY(4,(ULONG)status);
    if(info.State!=MEM_COMMIT || info.Type!=MEM_PRIVATE || (info.Protect&(PAGE_GUARD|PAGE_NOACCESS)))REFUSE_EARLY(5,((ULONG64)info.State<<32)|info.Protect);
    if((info.Protect&0xff)!=PAGE_EXECUTE_READ && (info.Protect&0xff)!=PAGE_EXECUTE_READWRITE)REFUSE_EARLY(6,info.Protect);
    if(context->Rip-(ULONG_PTR)info.BaseAddress>info.RegionSize || info.RegionSize-(context->Rip-(ULONG_PTR)info.BaseAddress)<sizeof code)REFUSE_EARLY(7,info.RegionSize);
    status=NtReadVirtualMemory(GetCurrentProcess(),(void*)context->Rip,code,sizeof code,&bytes);
    if(status || bytes!=sizeof code)REFUSE_EARLY(8,(ULONG)status);
    if(trace){memcpy(trace->code,code,sizeof code);trace->valid|=1;}
    entry=software_bridge_census(context,row);
#define BRIDGE_REFUSE(k,reason,detail) do{if(entry)InterlockedIncrement64(entry+(k));REFUSE_EARLY(reason,detail);}while(0)
    byte_load=code[0]==0x8a && code[1]==0x01;
    if(byte_load){memset(&effect,0,sizeof effect);effect.length=2;}
    else if(!(software_alu_enabled && software_bridge_arithmetic(code,context,&effect)) && !software_bridge_registers(code,context,&effect))BRIDGE_REFUSE(2,9,0);
    if(trace)trace->length=effect.length;
    if(effect.length+5>sizeof code || code[effect.length]!=0xe9)BRIDGE_REFUSE(2,10,0);
    memcpy(&displacement,code+effect.length+1,4);target=context->Rip+effect.length+5+(LONG_PTR)displacement;
    if(trace){trace->target=target;trace->valid|=2;}
    if(target<base || target-base>=nt->OptionalHeader.SizeOfImage)BRIDGE_REFUSE(3,11,0);
    status=NtQueryVirtualMemory(GetCurrentProcess(),(void*)target,MemoryBasicInformation,&info,sizeof info,NULL);
    if(status)BRIDGE_REFUSE(3,12,(ULONG)status);
    if(info.State!=MEM_COMMIT || (info.Protect&(PAGE_GUARD|PAGE_NOACCESS)))BRIDGE_REFUSE(3,13,((ULONG64)info.State<<32)|info.Protect);
    if((info.Protect&0xff)!=PAGE_EXECUTE_READ && (info.Protect&0xff)!=PAGE_EXECUTE_READWRITE && (info.Protect&0xff)!=PAGE_EXECUTE_WRITECOPY)BRIDGE_REFUSE(3,14,info.Protect);
    status=NtReadVirtualMemory(GetCurrentProcess(),(void*)target,&next,1,&bytes);
    if(status || bytes!=1)BRIDGE_REFUSE(3,15,(ULONG)status);
    if(trace){trace->next=next;trace->valid|=4;}
    next_is_ud=software_chain_target_ud(next,target,&info);
    if(!next_is_ud && !software_bridge_resume)BRIDGE_REFUSE(3,16,0);
    if(byte_load){
        status=NtQueryVirtualMemory(GetCurrentProcess(),(void*)context->Rcx,MemoryBasicInformation,&info,sizeof info,NULL);
        if(status)BRIDGE_REFUSE(4,17,(ULONG)status);
        if(info.State!=MEM_COMMIT || (info.Type!=MEM_PRIVATE && info.Type!=MEM_IMAGE) || (info.Protect&(PAGE_GUARD|PAGE_NOACCESS)))BRIDGE_REFUSE(4,18,((ULONG64)info.State<<32)|info.Protect);
        switch(info.Protect&0xff){case PAGE_READONLY:case PAGE_READWRITE:case PAGE_WRITECOPY:case PAGE_EXECUTE_READ:case PAGE_EXECUTE_READWRITE:case PAGE_EXECUTE_WRITECOPY:break;default:BRIDGE_REFUSE(4,19,info.Protect);}
        status=NtReadVirtualMemory(GetCurrentProcess(),(void*)context->Rcx,&value,1,&bytes);
        if(status || bytes!=1)BRIDGE_REFUSE(4,20,(ULONG)status);
        context->Rax=(context->Rax&~(ULONG64)0xff)|value;
    }else if(effect.vector)memcpy(&context->FltSave.XmmRegisters[effect.dst],effect.value,16);
    else if(!effect.no_write)*software_bridge_gpr(context,effect.dst)=effect.value[0];
    if(effect.flags_valid)context->EFlags=effect.flags;
    context->Rip=target;
    software_chain_count(4);if(entry)InterlockedIncrement64(entry+1);
    if(!next_is_ud)software_chain_count(5);
    bridge_refusal_end(trace,next_is_ud?1:2,0);
#undef BRIDGE_REFUSE
#undef REFUSE_EARLY
    return next_is_ud ? 1 : 2;
}
static unsigned int software_chain_next_reason(CONTEXT *context,ULONG64 *a,ULONG64 *b,LONG64 *row)
{
    MEMORY_BASIC_INFORMATION info;
    SIZE_T bytes=0;
    BYTE opcode;
    NTSTATUS status;
    ULONG_PTR base=(ULONG_PTR)NtCurrentTeb()->Peb->ImageBaseAddress;
    IMAGE_NT_HEADERS *nt=RtlImageNtHeader((void*)base);
    if(!nt || context->Rip<base || context->Rip-base>=nt->OptionalHeader.SizeOfImage)
    {
        unsigned int bridge=software_chain_load_bridge(context,row);
        if(bridge==1)return 0;
        /* The bridge's real effects are committed, but the destination is not
         * a #UD. Return through the ordinary NtContinue path, without making
         * an exception record or invoking VEH for that valid instruction. */
        if(bridge==2){*a=context->Rip;*b=2;return 19;}
        *a=base;*b=context->Rip;return 15;
    }
    status=NtQueryVirtualMemory(GetCurrentProcess(),(void*)context->Rip,MemoryBasicInformation,&info,sizeof(info),NULL);
    if(status){*a=status;return 16;}
    *a=info.State;*b=info.Protect;
    if(info.State!=MEM_COMMIT || (info.Protect & (PAGE_GUARD|PAGE_NOACCESS)))return 17;
    switch(info.Protect & 0xff){case PAGE_EXECUTE_READ:case PAGE_EXECUTE_READWRITE:case PAGE_EXECUTE_WRITECOPY:break;default:return 17;}
    status=NtReadVirtualMemory(GetCurrentProcess(),(void*)context->Rip,&opcode,1,&bytes);
    if(status || bytes!=1){*a=status;*b=bytes;return 18;}
    *a=opcode;*b=0;
    return software_chain_target_ud(opcode,context->Rip,&info)?0:19;
}

/* Bounded diagnostic only. The controller prefaults storage before arming.
 * One record covers one outer PE delivery, including synthetic links. Nested
 * deliveries have independent records, so totals can double-count nesting.
 * No log, allocation, instruction read or additional handler is introduced.
 * control: enabled, reserved, dropped, active, capacity; remaining reserved. */
#define BURST_CAPACITY 262144
LONG64 __wine_exception_burst_control[8] = {0,0,0,0,BURST_CAPACITY};
struct exception_burst_record
{
    LONG64 begin, end, handler, policy;
    ULONG64 rip_begin, rip_end;
    ULONG tid, links, reason;
    LONG ready;
};
struct exception_burst_record __wine_exception_burst_records[BURST_CAPACITY];
static LONG64 burst_clock(void)
{
    LARGE_INTEGER q;
    NtQueryPerformanceCounter(&q, NULL);
    return q.QuadPart;
}

/* Automatic bounded activation avoids cross-process writes while FH6 runs.
 * QPC gating itself remains present in the reference window and is documented. */
static LONG burst_initialized, burst_gate;
static LONG64 burst_deadline, burst_duration;
static void burst_configure(void)
{
    WCHAR buffer[16];
    UNICODE_STRING name = RTL_CONSTANT_STRING(L"WINE_EXCEPTION_BURST_AUTO");
    UNICODE_STRING value = {0, sizeof(buffer), buffer};
    LARGE_INTEGER q, frequency;
    BOOL probe = FALSE;
    if (burst_initialized || InterlockedCompareExchange(&burst_initialized, 1, 0)) return;
    if (RtlQueryEnvironmentVariable_U(NULL, &name, &value)) return;
    if (value.Length == 5*sizeof(WCHAR) && !memcmp(buffer,L"probe",value.Length)) probe=TRUE;
    else if (value.Length != sizeof(WCHAR) || buffer[0] != '1') return;
    NtQueryPerformanceCounter(&q, &frequency);
    memset(__wine_exception_burst_records,0,sizeof(__wine_exception_burst_records));
    {
        WCHAR trace_value[4];UNICODE_STRING trace_name=RTL_CONSTANT_STRING(L"WINE_BRIDGE_REFUSAL_TRACE");
        UNICODE_STRING value={0,sizeof(trace_value),trace_value};
        if(!RtlQueryEnvironmentVariable_U(NULL,&trace_name,&value) && value.Length==sizeof(WCHAR) && trace_value[0]=='1')
        {
            memset(__wine_bridge_refusal_records,0,sizeof(__wine_bridge_refusal_records));
            InterlockedCompareExchange64(&__wine_bridge_refusal_control[0],1,0);
        }
    }
    __wine_exception_burst_control[5]=frequency.QuadPart;
    burst_deadline=q.QuadPart+(probe?0:240*frequency.QuadPart);
    if (!probe)
    {
        WCHAR digits[32]; unsigned int i; ULONG64 parsed=0;
        UNICODE_STRING start_name=RTL_CONSTANT_STRING(L"FH6_TRACE_START");
        UNICODE_STRING start_value={0,sizeof(digits),digits};
        if (!RtlQueryEnvironmentVariable_U(NULL,&start_name,&start_value) && start_value.Length && start_value.Length<=20*sizeof(WCHAR))
        {
            for(i=0;i<start_value.Length/sizeof(WCHAR);i++)
            {
                if(digits[i]<'0'||digits[i]>'9'||parsed>922337203685477580ULL)break;
                parsed=parsed*10+digits[i]-'0';
            }
            if(i==start_value.Length/sizeof(WCHAR) && parsed>q.QuadPart && parsed-q.QuadPart<600*frequency.QuadPart)burst_deadline=parsed;
        }
    }
    burst_duration=probe?frequency.QuadPart/100:20*frequency.QuadPart;
    InterlockedExchange(&burst_gate,1);
}
static void burst_check_gate(void)
{
    LONG gate=burst_gate;
    LONG64 now;
    if (!gate) return;
    now=burst_clock();
    if (gate==1 && now>=burst_deadline && InterlockedCompareExchange(&burst_gate,3,1)==1)
    {
        __wine_exception_burst_control[6]=now;
        __wine_exception_burst_control[7]=now+burst_duration;
        InterlockedCompareExchange64(&__wine_exception_burst_control[0],1,0);
        InterlockedExchange(&burst_gate,2);
    }
    else if (gate==2 && now>=__wine_exception_burst_control[7])
    {
        InterlockedCompareExchange64(&__wine_exception_burst_control[0],0,1);
        InterlockedExchange(&burst_gate,0);
    }
}

static LONG call_vectored_handlers_chain_body(EXCEPTION_RECORD *rec, CONTEXT *context, struct exception_burst_record *timing)
{
    unsigned int links = 0;
    LONG64 *row=software_chain_diag_row();
    software_chain_diag(row,0,context,context,0,0);
    software_chain_count(0);
    for (;;)
    {
        CONTEXT before = *context;
        ULONG64 a=0,b=0;
        unsigned int reason;
        LONG64 stamp = timing ? burst_clock() : 0;
        LONG ret = call_vectored_handlers(rec, context);
        if (timing) {timing->handler += burst_clock() - stamp; timing->links = links; timing->reason = 3;}
        if (ret != EXCEPTION_CONTINUE_EXECUTION) {software_chain_diag(row,3,&before,context,ret,0);return ret;}
        if (links == 64)
        {
            if (timing) timing->reason = 2;
            software_chain_count(2);
            software_chain_diag(row,2,&before,context,0,0);
            return ret;
        }
        if (rec->ExceptionCode != EXCEPTION_ILLEGAL_INSTRUCTION || rec->ExceptionFlags)
        {if (timing) timing->reason = 4;software_chain_diag(row,4,&before,context,rec->ExceptionCode,rec->ExceptionFlags);return ret;}
        stamp = timing ? burst_clock() : 0;
        reason=software_chain_state_reason(&before,context,&a,&b);
        if(!reason)reason=software_chain_next_reason(context,&a,&b,row);
        if (timing) {timing->policy += burst_clock() - stamp; timing->reason = reason;}
        if(reason){software_chain_diag(row,reason,&before,context,a,b);return ret;}
        software_chain_diag(row,1,&before,context,a,b);
        memset(rec, 0, sizeof(*rec));
        rec->ExceptionCode = EXCEPTION_ILLEGAL_INSTRUCTION;
        rec->ExceptionAddress = (void *)context->Rip;
        ++links;
        software_chain_count(1);
        /* The next iteration runs the real complete VEH chain. If it declines,
         * dispatch_exception proceeds to SEH/second chance exactly once. */
    }
}
static LONG call_vectored_handlers_with_chain(EXCEPTION_RECORD *rec, CONTEXT *context)
{
    struct exception_burst_record *timing = NULL;
    LONG ret;
    burst_check_gate();
    if (__wine_exception_burst_control[0])
    {
        LONG64 index;
        InterlockedIncrement64(&__wine_exception_burst_control[3]);
        if (__wine_exception_burst_control[0])
        {
            index = InterlockedIncrement64(&__wine_exception_burst_control[1]) - 1;
            if (index < BURST_CAPACITY)
            {
                timing = &__wine_exception_burst_records[index];
                timing->tid = HandleToULong(NtCurrentTeb()->ClientId.UniqueThread);
                timing->rip_begin = context->Rip;
                timing->begin = burst_clock();
            }
            else InterlockedIncrement64(&__wine_exception_burst_control[2]);
        }
        if (!timing) InterlockedDecrement64(&__wine_exception_burst_control[3]);
    }
    ret = call_vectored_handlers_chain_body(rec, context, timing);
    if (timing)
    {
        timing->end = burst_clock();
        timing->rip_end = context->Rip;
        InterlockedExchange(&timing->ready, 1);
        InterlockedDecrement64(&__wine_exception_burst_control[3]);
    }
    return ret;
}
#endif
