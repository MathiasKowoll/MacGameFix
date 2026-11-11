/* Own-code test only. Pending execution on the experimental dispatcher. */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern uint64_t chain_run(void),boundary_run(void),ud2_run(void);
extern unsigned char chain_begin[],chain_end[],boundary_first[],boundary_second[],ud2_first[],ud2_second[];
static volatile LONG failures,handler_calls,first_handler_calls;
static _Thread_local unsigned nesting;
static _Thread_local int request_nested;
static volatile LONG64 *stats;
struct RefusalRecord {LONG64 begin,end;ULONG64 rip,target;BYTE code[16];ULONG64 detail;ULONG tid,outcome,valid,length,next;LONG ready;};
static int new_alu_enabled=1;
static int count_enabled=1, expect_resume=0, register_resume=0;
static _Thread_local int omit_fp_group;

extern uint64_t load_bridge_run(const unsigned char*,uint64_t);
extern unsigned char load_bridge_first[],load_bridge_second[];
static unsigned char *bridge_code;
static volatile LONG bridge_av;
static LONG CALLBACK bridge_handler(EXCEPTION_POINTERS *ep){
 CONTEXT *c=ep->ContextRecord;
 if(ep->ExceptionRecord->ExceptionCode==EXCEPTION_ACCESS_VIOLATION && c->Rip==(uintptr_t)bridge_code){
  InterlockedIncrement(&bridge_av);
  if(ep->ExceptionRecord->ExceptionAddress!=bridge_code || ep->ExceptionRecord->ExceptionInformation[0]!=0 || ep->ExceptionRecord->ExceptionInformation[1]!=c->Rcx)InterlockedIncrement(&failures);
  c->Rip+=2;return EXCEPTION_CONTINUE_EXECUTION;
 }
 if(ep->ExceptionRecord->ExceptionCode!=EXCEPTION_ILLEGAL_INSTRUCTION)return EXCEPTION_CONTINUE_SEARCH;
 if(c->Rip==(uintptr_t)load_bridge_first){c->Rip=(uintptr_t)bridge_code;InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;}
 if(c->Rip==(uintptr_t)load_bridge_second){c->Rip++;InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;}
 return EXCEPTION_CONTINUE_SEARCH;
}
static DWORD WINAPI bridge_concurrent(void *unused){
 (void)unused;
 for(unsigned i=0;i<1000;i++){
  unsigned char value=(unsigned char)i;uint64_t seed=0xfedcba9876543200ULL|(255-i%256);
  if(load_bridge_run(&value,seed)!=((seed&~255ULL)|value))InterlockedIncrement(&failures);
 }return 0;
}
static void test_load_bridge(int enabled){
 LONG64 *trace=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_bridge_refusal_control");
 LONG64 *window=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_exception_burst_control");
 struct RefusalRecord *records=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_bridge_refusal_records");
 int recording=enabled&&trace&&trace[0];if(recording)InterlockedExchange64(window,1);
 uintptr_t image=(uintptr_t)GetModuleHandleA(NULL);
 for(unsigned i=1;i<16 && !bridge_code;i++)bridge_code=VirtualAlloc((void*)(image+0x1000000*i),4096,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
 if(!bridge_code){InterlockedIncrement(&failures);return;}
 bridge_code[0]=0x8a;bridge_code[1]=0x01;bridge_code[2]=0xe9;
 int64_t delta=(intptr_t)load_bridge_second-((intptr_t)bridge_code+7);if(delta<INT32_MIN||delta>INT32_MAX){InterlockedIncrement(&failures);return;}
 int32_t rel=(int32_t)delta;memcpy(bridge_code+3,&rel,4);
 DWORD old;VirtualProtect(bridge_code,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),bridge_code,7);
 PVOID h=AddVectoredExceptionHandler(0,bridge_handler);LONG64 before=stats[4];
 bridge_concurrent(NULL);
 HANDLE t[4];for(unsigned i=0;i<4;i++){t[i]=CreateThread(NULL,0,bridge_concurrent,NULL,0,NULL);if(!t[i])ExitProcess(9);}
 WaitForMultipleObjects(4,t,TRUE,INFINITE);for(unsigned i=0;i<4;i++)CloseHandle(t[i]);
 LONG64 accepted=stats[4]-before;if(accepted!=(enabled&&count_enabled?5000:0))InterlockedIncrement(&failures);
 /* A valid NOP between the load and jump must be rejected as a template,
  * then execute normally, preserving the exact load result. */
 VirtualProtect(bridge_code,4096,PAGE_READWRITE,&old);bridge_code[2]=0x90;bridge_code[3]=0xe9;
 rel=(int32_t)((intptr_t)load_bridge_second-((intptr_t)bridge_code+8));memcpy(bridge_code+4,&rel,4);
 VirtualProtect(bridge_code,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),bridge_code,16);
 unsigned char sample=0x5a;uint64_t sentinel=0x123456789abcdeffULL;
 if(load_bridge_run(&sample,sentinel)!=((sentinel&~255ULL)|sample))InterlockedIncrement(&failures);
 if(recording && (!trace[1] || records[trace[1]-1].outcome!=10 || records[trace[1]-1].code[2]!=0x90))InterlockedIncrement(&failures);
 VirtualProtect(bridge_code,4096,PAGE_READWRITE,&old);bridge_code[2]=0xe9;
 rel=(int32_t)((intptr_t)load_bridge_second-((intptr_t)bridge_code+7));memcpy(bridge_code+3,&rel,4);
 VirtualProtect(bridge_code,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),bridge_code,16);
 void *bad=VirtualAlloc(NULL,4096,MEM_RESERVE|MEM_COMMIT,PAGE_NOACCESS);uint64_t seed=0xfedcba9876543210ULL;
 if(!bad || load_bridge_run(bad,seed)!=seed || bridge_av!=1 || stats[4]-before!=accepted)InterlockedIncrement(&failures);
 if(recording && (!trace[1] || records[trace[1]-1].outcome!=18 || records[trace[1]-1].valid!=7))InterlockedIncrement(&failures);
 if(recording)InterlockedExchange64(window,0);
 printf("REFUSAL_MEMORY_TEMPLATE nop_jump=normal_execution noaccess=real_fault failures=%ld\n",failures);
 VirtualFree(bad,0,MEM_RELEASE);RemoveVectoredExceptionHandler(h);VirtualFree(bridge_code,0,MEM_RELEASE);
 printf("LOAD_BRIDGE accepted=%lld expected=%d fault_fallbacks=%ld failures=%ld\n",accepted,enabled&&count_enabled?5000:0,bridge_av,failures);
}

extern uint64_t resume_fault_run(const unsigned char*,uint64_t,const void*);
extern unsigned char resume_fault_first[],resume_fault_target[],resume_fault_end[];
extern uint64_t resume_ud2_run(const unsigned char*,uint64_t);
extern unsigned char resume_ud2_first[],resume_ud2_target[],resume_ud2_end[];
static volatile LONG resume_ud2_calls;
static int arithmetic_fault_check;static unsigned char *resume_code;static uint64_t resume_expected;static volatile LONG resume_av;
static LONG CALLBACK resume_fault_handler(EXCEPTION_POINTERS *ep){
 CONTEXT *c=ep->ContextRecord;
 if(ep->ExceptionRecord->ExceptionCode==EXCEPTION_ILLEGAL_INSTRUCTION && (c->Rip==(uintptr_t)resume_fault_first || c->Rip==(uintptr_t)resume_ud2_first)){c->Rip=(uintptr_t)resume_code;InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;}
 if(ep->ExceptionRecord->ExceptionCode==EXCEPTION_ILLEGAL_INSTRUCTION && c->Rip==(uintptr_t)resume_ud2_target){
  if(ep->ExceptionRecord->ExceptionAddress!=resume_ud2_target || ep->ExceptionRecord->NumberParameters || c->Rax!=resume_expected)InterlockedIncrement(&failures);
  InterlockedIncrement(&resume_ud2_calls);InterlockedIncrement(&handler_calls);c->Rip=(uintptr_t)resume_ud2_end;return EXCEPTION_CONTINUE_EXECUTION;
 }
 if(ep->ExceptionRecord->ExceptionCode==EXCEPTION_ACCESS_VIOLATION && c->Rip==(uintptr_t)resume_fault_target){
  if(ep->ExceptionRecord->ExceptionAddress!=resume_fault_target || ep->ExceptionRecord->ExceptionInformation[0]!=0 || ep->ExceptionRecord->ExceptionInformation[1]!=c->R8 || c->Rax!=resume_expected)InterlockedIncrement(&failures);
  if(arithmetic_fault_check && (c->EFlags&0x8d5)!=0x15)InterlockedIncrement(&failures);
  InterlockedIncrement(&resume_av);c->Rip=(uintptr_t)resume_fault_end;return EXCEPTION_CONTINUE_EXECUTION;
 }return EXCEPTION_CONTINUE_SEARCH;
}
static void test_resume_fault(int enabled){
 uintptr_t image=(uintptr_t)GetModuleHandleA(NULL);
 for(unsigned i=1;i<32&&!resume_code;i++)resume_code=VirtualAlloc((void*)(image+i*0x1000000),4096,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
 if(!resume_code)ExitProcess(17);
 resume_code[0]=0x8a;resume_code[1]=0x01;resume_code[2]=0xe9;
 int64_t delta=(intptr_t)resume_fault_target-((intptr_t)resume_code+7);if(delta<INT32_MIN||delta>INT32_MAX)ExitProcess(18);int32_t rel=(int32_t)delta;memcpy(resume_code+3,&rel,4);
 DWORD old;VirtualProtect(resume_code,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),resume_code,7);
 unsigned char value=0x67;void *bad=VirtualAlloc(NULL,4096,MEM_RESERVE|MEM_COMMIT,PAGE_NOACCESS);if(!bad)ExitProcess(19);
 uint64_t seed=0xfedcba9876543210ULL;resume_expected=(seed&~255ULL)|value;LONG64 before=stats[5];
 PVOID h=AddVectoredExceptionHandler(0,resume_fault_handler);
 if(resume_fault_run(&value,seed,bad)!=resume_expected || resume_av!=1 || stats[5]-before!=(enabled&&expect_resume&&count_enabled?1:0))InterlockedIncrement(&failures);
 printf("RESUME_DESTINATION_AV original_address=verified original_context=verified real_faults=%ld resumed=%lld failures=%ld\n",resume_av,stats[5]-before,failures);
 /* Arithmetic must execute once even when the destination raises a genuine
  * access fault. This checks staged flags/context on target refusal/resume. */
 VirtualProtect(resume_code,4096,PAGE_READWRITE,&old);
 resume_code[0]=0x48;resume_code[1]=0x83;resume_code[2]=0xc0;resume_code[3]=7;resume_code[4]=0xe9;
 delta=(intptr_t)resume_fault_target-((intptr_t)resume_code+9);rel=(int32_t)delta;memcpy(resume_code+5,&rel,4);
 VirtualProtect(resume_code,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),resume_code,16);
 resume_av=0;resume_expected=6;arithmetic_fault_check=1;before=stats[5];
 if(resume_fault_run(&value,UINT64_MAX,bad)!=6 || resume_av!=1 || stats[5]-before!=(enabled&&expect_resume&&count_enabled&&new_alu_enabled?1:0))InterlockedIncrement(&failures);
 printf("ARITHMETIC_DESTINATION_AV result=6 flags=0x15 original_faults=%ld failures=%ld\n",resume_av,failures);
 arithmetic_fault_check=0;resume_expected=(seed&~255ULL)|value;
 VirtualProtect(resume_code,4096,PAGE_READWRITE,&old);
 resume_code[0]=0x8a;resume_code[1]=0x01;resume_code[2]=0xe9;
 delta=(intptr_t)resume_ud2_target-((intptr_t)resume_code+7);if(delta<INT32_MIN||delta>INT32_MAX)ExitProcess(20);rel=(int32_t)delta;memcpy(resume_code+3,&rel,4);
 VirtualProtect(resume_code,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),resume_code,7);before=stats[5];
 if(resume_ud2_run(&value,seed)!=resume_expected || resume_ud2_calls!=1 || stats[5]-before!=(enabled&&expect_resume&&count_enabled?1:0))InterlockedIncrement(&failures);
 printf("RESUME_DESTINATION_UD2 original_address=verified real_faults=%ld resumed=%lld failures=%ld\n",resume_ud2_calls,stats[5]-before,failures);
 RemoveVectoredExceptionHandler(h);VirtualFree(bad,0,MEM_RELEASE);VirtualFree(resume_code,0,MEM_RELEASE);
}


#include "guaranteed_ud.h"
extern uint64_t classification_run(uint64_t,uint64_t);
extern unsigned char classification_first[],classification_end[];
extern unsigned char classification_aam[],classification_aad[],classification_callfar[],classification_ud2[],classification_nop[];
extern unsigned char classification_boundary_aam[],classification_boundary_aad[],classification_boundary_callfar[];
extern unsigned char classification_fit_aam[],classification_fit_aad[],classification_fit_callfar[];
extern unsigned char classification_window_aam[],classification_window_aad[],classification_window_callfar[];
static unsigned char *classification_bridge,*classification_target;
static int classification_private,classification_id;
static uint64_t classification_signature;
static ULONG64 classification_rsp,classification_seed;
static DWORD classification_flags;
static volatile LONG classification_faults;
static DWORD classification_code,classification_record_flags,classification_parameters,classification_observed_flags;
static LONG CALLBACK classification_handler(EXCEPTION_POINTERS *ep)
{
 CONTEXT *c=ep->ContextRecord;EXCEPTION_RECORD *r=ep->ExceptionRecord;
 if(c->Rip==(uintptr_t)classification_first && r->ExceptionCode==EXCEPTION_ILLEGAL_INSTRUCTION){
  classification_rsp=c->Rsp;classification_flags=c->EFlags;
  c->Rip=(uintptr_t)(classification_private?classification_bridge:classification_target);
  InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;
 }
 if(c->Rip!=(uintptr_t)classification_target)return EXCEPTION_CONTINUE_SEARCH;
 classification_code=r->ExceptionCode;classification_record_flags=r->ExceptionFlags;classification_parameters=r->NumberParameters;classification_observed_flags=c->EFlags;
 /* Boundary result is compared byte-for-byte (normalized addresses) against
  * disabled execution by run_validation.py. Host page granularity can change
  * which access fault is delivered; never bless either outcome without that
  * independent baseline. Interior fixtures must remain illegal instructions. */
 DWORD expected_code=classification_id>=5?r->ExceptionCode:EXCEPTION_ILLEGAL_INSTRUCTION;
 unsigned expected_params=expected_code==EXCEPTION_ACCESS_VIOLATION?2:0;
 if(expected_code!=EXCEPTION_ILLEGAL_INSTRUCTION && expected_code!=EXCEPTION_ACCESS_VIOLATION)InterlockedIncrement(&failures);
 uint64_t observed[]={r->ExceptionCode,r->ExceptionFlags,r->NumberParameters,c->EFlags,c->Rax,c->Rsp-classification_rsp,c->Rip-(uintptr_t)classification_target,(uintptr_t)r->ExceptionAddress-(uintptr_t)classification_target,r->NumberParameters?r->ExceptionInformation[0]:0,r->NumberParameters?r->ExceptionInformation[1]-(uintptr_t)classification_target:0};
 for(unsigned i=0;i<sizeof(observed)/sizeof(observed[0]);i++)classification_signature=(classification_signature^observed[i])*1099511628211ULL;
 if(r->ExceptionCode!=expected_code || r->ExceptionFlags || r->NumberParameters!=expected_params || r->ExceptionRecord || r->ExceptionAddress!=classification_target || c->Rsp!=classification_rsp || c->Rax!=classification_seed || c->EFlags!=classification_flags){
  printf("UD_CONTEXT code=%lx flags=%lx initial=%lx record_flags=%lx parameters=%lu rsp_equal=%d rax_equal=%d\n",r->ExceptionCode,c->EFlags,classification_flags,r->ExceptionFlags,r->NumberParameters,c->Rsp==classification_rsp,c->Rax==classification_seed);InterlockedIncrement(&failures);
 }
 c->Rip=(uintptr_t)classification_end;InterlockedIncrement(&classification_faults);if(r->ExceptionCode==EXCEPTION_ILLEGAL_INSTRUCTION)InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;
}
static void test_destination_classification(int enabled)
{
 unsigned char *targets[]={classification_aam,classification_aad,classification_callfar,classification_ud2,classification_nop,classification_boundary_aam,classification_boundary_aad,classification_boundary_callfar,classification_fit_aam,classification_fit_aad,classification_fit_callfar,classification_window_aam,classification_window_aad,classification_window_callfar};
 DWORD guard_old[9];unsigned guard_lengths[]={1,1,1,2,2,7,16,16,16};
 for(unsigned i=0;i<9;i++)if(!VirtualProtect(targets[5+i]+guard_lengths[i],4096,PAGE_NOACCESS,guard_old+i))ExitProcess(31);
 int legacy_d5=software_legacy_d5_available();
 /* APX-on/off policy tested independently of this machine's CPUID result. */
 if(!software_guaranteed_ud_byte(0xd4,0)||!software_guaranteed_ud_byte(0x9a,0)||software_guaranteed_ud_byte(0xd5,0)||!software_guaranteed_ud_byte(0xd5,1))InterlockedIncrement(&failures);
 for(unsigned i=0;i<256;i++)if(i==0x62||i==0xc4||i==0xc5||i==0x66||i==0x48||i==0x0f||i==0x90)if(software_guaranteed_ud_byte(i,1))InterlockedIncrement(&failures);
 uintptr_t image=(uintptr_t)GetModuleHandleA(NULL);
 for(unsigned i=1;i<32&&!classification_bridge;i++)classification_bridge=VirtualAlloc((void*)(image+i*0x1000000),4096,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
 if(!classification_bridge)ExitProcess(29);
 PVOID handler=AddVectoredExceptionHandler(0,classification_handler);
 for(unsigned private_path=0;private_path<2;private_path++)for(unsigned id=0;id<14;id++){
  if((id==1||id==6||id==9||id==12)&&!legacy_d5)continue;
  classification_private=private_path;classification_target=targets[id];classification_id=id;classification_signature=1469598103934665603ULL;
  DWORD old;VirtualProtect(classification_bridge,4096,PAGE_READWRITE,&old);
  /* Register move preserves every flag and isolates destination policy. */
  classification_bridge[0]=0x48;classification_bridge[1]=0x8b;classification_bridge[2]=0xc0;classification_bridge[3]=0xe9;
  int64_t delta=(intptr_t)classification_target-((intptr_t)classification_bridge+8);if(delta<INT32_MIN||delta>INT32_MAX)ExitProcess(30);
  int32_t rel=(int32_t)delta;memcpy(classification_bridge+4,&rel,4);
  VirtualProtect(classification_bridge,4096,PAGE_EXECUTE_READ,&old);FlushInstructionCache(GetCurrentProcess(),classification_bridge,16);
  LONG before=classification_faults;LONG64 links=stats[1],accepted=stats[4];
  for(unsigned flags=0;flags<64;flags++){
   uint64_t f=0x202|((flags&1)?1:0)|((flags&2)?4:0)|((flags&4)?0x10:0)|((flags&8)?0x40:0)|((flags&16)?0x80:0)|((flags&32)?0x800:0);
   classification_seed=0x123456789abcdef0ULL^flags;
   if(classification_run(classification_seed,f)!=classification_seed)InterlockedIncrement(&failures);
  }
  LONG64 want=enabled&&count_enabled&&(id<3||id>=8)?64:0;
  if(classification_faults-before!=(id!=4?64:0)||(id<5&&stats[1]-links!=want))InterlockedIncrement(&failures);
  LONG64 want_bridge=private_path&&enabled&&count_enabled&&(id<3||id>=8||expect_resume)?64:0;
  if(id<5&&stats[4]-accepted!=want_bridge)InterlockedIncrement(&failures);
  printf("UD_EQUIVALENCE private=%u id=%u signature=%llx\n",private_path,id,(unsigned long long)classification_signature);
  printf("UD_DESTINATION private=%u id=%u legacy_d5=%d real_handlers=%ld links=%lld accepted=%lld code=%lx context_flags=%lx failures=%ld\n",private_path,id,legacy_d5,classification_faults-before,stats[1]-links,stats[4]-accepted,classification_code,classification_observed_flags,failures);
 }
 RemoveVectoredExceptionHandler(handler);VirtualFree(classification_bridge,0,MEM_RELEASE);
 for(unsigned i=0;i<9;i++){DWORD old;if(!VirtualProtect(targets[5+i]+guard_lengths[i],4096,guard_old[i],&old))ExitProcess(32);}
}

typedef struct __attribute__((aligned(16))) {uint64_t q[4],x0[2],x1[2],x8[2],flags,count;} register_state;
extern void register_native_run(register_state*),register_trap_run(register_state*);
extern unsigned char register_trap_first[],register_trap_second[];
unsigned char *register_native_code;
static unsigned char *register_trap_code;
static _Thread_local uint64_t register_seen_rsp;
static LONG CALLBACK register_handler(EXCEPTION_POINTERS *ep){
 CONTEXT *c=ep->ContextRecord;
 if(ep->ExceptionRecord->ExceptionCode!=EXCEPTION_ILLEGAL_INSTRUCTION)return EXCEPTION_CONTINUE_SEARCH;
 if(c->Rip==(uintptr_t)register_trap_first){
  if(ep->ExceptionRecord->ExceptionAddress!=register_trap_first)InterlockedIncrement(&failures);
  register_seen_rsp=c->Rsp;c->Rip=(uintptr_t)register_trap_code;InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;
 }
 if(c->Rip==(uintptr_t)register_trap_second){
  if(ep->ExceptionRecord->ExceptionAddress!=register_trap_second)InterlockedIncrement(&failures);
  c->Rip++;InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;
 }return EXCEPTION_CONTINUE_SEARCH;
}
struct register_case {const char *name;unsigned char bytes[16];unsigned n,accepted,stack_source;};
static const struct register_case register_cases[]={
 {"mov64",{0x48,0x8b,0xc2},3,1,0},{"mov32_high_source",{0x41,0x8b,0xc2},3,1,0},
 {"mov16_preserve",{0x66,0x41,0x8b,0xc2},4,1,0},{"mov64_high",{0x4d,0x8b,0xd3},3,1,0},
 {"mov64_reverse",{0x4d,0x89,0xda},3,1,0},{"mov_rsp_source",{0x48,0x8b,0xc4},3,1,1},
 {"movdqa",{0x66,0x0f,0x6f,0xc8},4,1,0},{"movdqa_high_dest",{0x66,0x44,0x0f,0x6f,0xc0},5,1,0},
 {"movdqa_high_source",{0x66,0x41,0x0f,0x6f,0xc8},5,1,0},
 {"pshufd",{0x66,0x0f,0x70,0xc8,0x87},5,1,0},{"pshufd_high_alias",{0x66,0x45,0x0f,0x70,0xc0,0x1b},6,1,0},
 {"paddq",{0x66,0x0f,0xd4,0xc8},4,1,0},{"paddq_high_alias",{0x66,0x45,0x0f,0xd4,0xc0},5,1,0},
 {"movq",{0x66,0x48,0x0f,0x7e,0xc8},5,1,0},{"movq_high_gpr",{0x66,0x49,0x0f,0x7e,0xc2},5,1,0},
 {"movd_zero_extend",{0x66,0x0f,0x7e,0xc8},4,1,0},{"movd_high_xmm",{0x66,0x44,0x0f,0x7e,0xc0},5,1,0},
 {"add64_reverse",{0x48,0x01,0xd0},3,1,0},{"unsupported_rsp_dest",{0x48,0x8b,0xe4},3,0,0},
 {"unsupported_simd_memory",{0x66,0x0f,0x6f,0x4b,0x20},5,0,0},
 {"add64",{0x48,0x03,0xc2},3,1,0},{"add32_high",{0x45,0x03,0xd3},3,1,0},
 {"add64_alias",{0x48,0x03,0xc0},3,1,0},{"sub64",{0x48,0x2b,0xc2},3,1,0},
 {"sub32_reverse",{0x45,0x29,0xda},3,1,0},{"cmp64",{0x48,0x3b,0xc2},3,1,0},
 {"cmp32",{0x3b,0xd0},2,1,0},{"cmp64_reverse",{0x4d,0x39,0xda},3,1,0},
 {"or64",{0x48,0x0b,0xc2},3,1,0},{"or32_reverse",{0x45,0x09,0xda},3,1,0},
 {"and64",{0x48,0x23,0xc2},3,1,0},{"and32_reverse",{0x45,0x21,0xda},3,1,0},
 {"xor64",{0x48,0x33,0xc2},3,1,0},{"xor32_alias",{0x45,0x31,0xd2},3,1,0},
 {"test64",{0x48,0x85,0xc2},3,1,0},{"test32_high",{0x45,0x85,0xd3},3,1,0},
 {"shr64_cl",{0x48,0xd3,0xea},3,1,0},{"shr32_cl",{0xd3,0xe8},2,1,0},
 {"shr64_cl_high",{0x49,0xd3,0xea},3,1,0},{"shr64_56",{0x48,0xc1,0xe8,56},4,1,0},
 {"shr32_0",{0x41,0xc1,0xea,0},4,1,0},{"shr32_32",{0xc1,0xe8,32},3,1,0},
 {"shr64_64",{0x49,0xc1,0xea,64},4,1,0},{"shr64_255",{0x48,0xc1,0xea,255},4,1,0},
 {"add_imm8",{0x48,0x83,0xc0,0xff},4,1,0},{"cmp_imm8",{0x49,0x83,0xfa,0x80},4,1,0},
 {"sub_imm32",{0x48,0x81,0xea,0,0,0,0x80},7,1,0},{"and_acc32",{0x25,0xff,0xff,0xff,0x0f},5,1,0},
 {"or_acc64",{0x48,0x0d,0,0,0,0x80},6,1,0},{"xor_imm8",{0x41,0x83,0xf2,0xff},4,1,0},
 {"not64",{0x49,0xf7,0xd2},3,1,0},{"not32",{0xf7,0xd0},2,1,0},
 {"mov_imm64",{0x48,0xb8,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0},10,1,0},
 {"mov_imm32_high",{0x41,0xba,0xff,0xff,0xff,0x80},6,1,0},
 {"fallback_add16",{0x66,0x01,0xd0},3,0,0},{"fallback_cmp_memory",{0x48,0x83,0x7b,8,0},5,0,0},
 {"fallback_adc",{0x48,0x13,0xc2},3,0,0},{"fallback_sar",{0x48,0xd3,0xf8},3,0,0},
 {"all_imm_32_0",{0xc1,0xe8,0x0},3,1,0},
 {"all_imm_32_1",{0xc1,0xe8,0x1},3,1,0},
 {"all_imm_32_2",{0xc1,0xe8,0x2},3,1,0},
 {"all_imm_32_3",{0xc1,0xe8,0x3},3,1,0},
 {"all_imm_32_4",{0xc1,0xe8,0x4},3,1,0},
 {"all_imm_32_5",{0xc1,0xe8,0x5},3,1,0},
 {"all_imm_32_6",{0xc1,0xe8,0x6},3,1,0},
 {"all_imm_32_7",{0xc1,0xe8,0x7},3,1,0},
 {"all_imm_32_8",{0xc1,0xe8,0x8},3,1,0},
 {"all_imm_32_9",{0xc1,0xe8,0x9},3,1,0},
 {"all_imm_32_10",{0xc1,0xe8,0xa},3,1,0},
 {"all_imm_32_11",{0xc1,0xe8,0xb},3,1,0},
 {"all_imm_32_12",{0xc1,0xe8,0xc},3,1,0},
 {"all_imm_32_13",{0xc1,0xe8,0xd},3,1,0},
 {"all_imm_32_14",{0xc1,0xe8,0xe},3,1,0},
 {"all_imm_32_15",{0xc1,0xe8,0xf},3,1,0},
 {"all_imm_32_16",{0xc1,0xe8,0x10},3,1,0},
 {"all_imm_32_17",{0xc1,0xe8,0x11},3,1,0},
 {"all_imm_32_18",{0xc1,0xe8,0x12},3,1,0},
 {"all_imm_32_19",{0xc1,0xe8,0x13},3,1,0},
 {"all_imm_32_20",{0xc1,0xe8,0x14},3,1,0},
 {"all_imm_32_21",{0xc1,0xe8,0x15},3,1,0},
 {"all_imm_32_22",{0xc1,0xe8,0x16},3,1,0},
 {"all_imm_32_23",{0xc1,0xe8,0x17},3,1,0},
 {"all_imm_32_24",{0xc1,0xe8,0x18},3,1,0},
 {"all_imm_32_25",{0xc1,0xe8,0x19},3,1,0},
 {"all_imm_32_26",{0xc1,0xe8,0x1a},3,1,0},
 {"all_imm_32_27",{0xc1,0xe8,0x1b},3,1,0},
 {"all_imm_32_28",{0xc1,0xe8,0x1c},3,1,0},
 {"all_imm_32_29",{0xc1,0xe8,0x1d},3,1,0},
 {"all_imm_32_30",{0xc1,0xe8,0x1e},3,1,0},
 {"all_imm_32_31",{0xc1,0xe8,0x1f},3,1,0},
 {"all_imm_32_32",{0xc1,0xe8,0x20},3,1,0},
 {"all_imm_32_33",{0xc1,0xe8,0x21},3,1,0},
 {"all_imm_32_34",{0xc1,0xe8,0x22},3,1,0},
 {"all_imm_32_35",{0xc1,0xe8,0x23},3,1,0},
 {"all_imm_32_36",{0xc1,0xe8,0x24},3,1,0},
 {"all_imm_32_37",{0xc1,0xe8,0x25},3,1,0},
 {"all_imm_32_38",{0xc1,0xe8,0x26},3,1,0},
 {"all_imm_32_39",{0xc1,0xe8,0x27},3,1,0},
 {"all_imm_32_40",{0xc1,0xe8,0x28},3,1,0},
 {"all_imm_32_41",{0xc1,0xe8,0x29},3,1,0},
 {"all_imm_32_42",{0xc1,0xe8,0x2a},3,1,0},
 {"all_imm_32_43",{0xc1,0xe8,0x2b},3,1,0},
 {"all_imm_32_44",{0xc1,0xe8,0x2c},3,1,0},
 {"all_imm_32_45",{0xc1,0xe8,0x2d},3,1,0},
 {"all_imm_32_46",{0xc1,0xe8,0x2e},3,1,0},
 {"all_imm_32_47",{0xc1,0xe8,0x2f},3,1,0},
 {"all_imm_32_48",{0xc1,0xe8,0x30},3,1,0},
 {"all_imm_32_49",{0xc1,0xe8,0x31},3,1,0},
 {"all_imm_32_50",{0xc1,0xe8,0x32},3,1,0},
 {"all_imm_32_51",{0xc1,0xe8,0x33},3,1,0},
 {"all_imm_32_52",{0xc1,0xe8,0x34},3,1,0},
 {"all_imm_32_53",{0xc1,0xe8,0x35},3,1,0},
 {"all_imm_32_54",{0xc1,0xe8,0x36},3,1,0},
 {"all_imm_32_55",{0xc1,0xe8,0x37},3,1,0},
 {"all_imm_32_56",{0xc1,0xe8,0x38},3,1,0},
 {"all_imm_32_57",{0xc1,0xe8,0x39},3,1,0},
 {"all_imm_32_58",{0xc1,0xe8,0x3a},3,1,0},
 {"all_imm_32_59",{0xc1,0xe8,0x3b},3,1,0},
 {"all_imm_32_60",{0xc1,0xe8,0x3c},3,1,0},
 {"all_imm_32_61",{0xc1,0xe8,0x3d},3,1,0},
 {"all_imm_32_62",{0xc1,0xe8,0x3e},3,1,0},
 {"all_imm_32_63",{0xc1,0xe8,0x3f},3,1,0},
 {"all_imm_32_64",{0xc1,0xe8,0x40},3,1,0},
 {"all_imm_32_65",{0xc1,0xe8,0x41},3,1,0},
 {"all_imm_32_66",{0xc1,0xe8,0x42},3,1,0},
 {"all_imm_32_67",{0xc1,0xe8,0x43},3,1,0},
 {"all_imm_32_68",{0xc1,0xe8,0x44},3,1,0},
 {"all_imm_32_69",{0xc1,0xe8,0x45},3,1,0},
 {"all_imm_32_70",{0xc1,0xe8,0x46},3,1,0},
 {"all_imm_32_71",{0xc1,0xe8,0x47},3,1,0},
 {"all_imm_32_72",{0xc1,0xe8,0x48},3,1,0},
 {"all_imm_32_73",{0xc1,0xe8,0x49},3,1,0},
 {"all_imm_32_74",{0xc1,0xe8,0x4a},3,1,0},
 {"all_imm_32_75",{0xc1,0xe8,0x4b},3,1,0},
 {"all_imm_32_76",{0xc1,0xe8,0x4c},3,1,0},
 {"all_imm_32_77",{0xc1,0xe8,0x4d},3,1,0},
 {"all_imm_32_78",{0xc1,0xe8,0x4e},3,1,0},
 {"all_imm_32_79",{0xc1,0xe8,0x4f},3,1,0},
 {"all_imm_32_80",{0xc1,0xe8,0x50},3,1,0},
 {"all_imm_32_81",{0xc1,0xe8,0x51},3,1,0},
 {"all_imm_32_82",{0xc1,0xe8,0x52},3,1,0},
 {"all_imm_32_83",{0xc1,0xe8,0x53},3,1,0},
 {"all_imm_32_84",{0xc1,0xe8,0x54},3,1,0},
 {"all_imm_32_85",{0xc1,0xe8,0x55},3,1,0},
 {"all_imm_32_86",{0xc1,0xe8,0x56},3,1,0},
 {"all_imm_32_87",{0xc1,0xe8,0x57},3,1,0},
 {"all_imm_32_88",{0xc1,0xe8,0x58},3,1,0},
 {"all_imm_32_89",{0xc1,0xe8,0x59},3,1,0},
 {"all_imm_32_90",{0xc1,0xe8,0x5a},3,1,0},
 {"all_imm_32_91",{0xc1,0xe8,0x5b},3,1,0},
 {"all_imm_32_92",{0xc1,0xe8,0x5c},3,1,0},
 {"all_imm_32_93",{0xc1,0xe8,0x5d},3,1,0},
 {"all_imm_32_94",{0xc1,0xe8,0x5e},3,1,0},
 {"all_imm_32_95",{0xc1,0xe8,0x5f},3,1,0},
 {"all_imm_32_96",{0xc1,0xe8,0x60},3,1,0},
 {"all_imm_32_97",{0xc1,0xe8,0x61},3,1,0},
 {"all_imm_32_98",{0xc1,0xe8,0x62},3,1,0},
 {"all_imm_32_99",{0xc1,0xe8,0x63},3,1,0},
 {"all_imm_32_100",{0xc1,0xe8,0x64},3,1,0},
 {"all_imm_32_101",{0xc1,0xe8,0x65},3,1,0},
 {"all_imm_32_102",{0xc1,0xe8,0x66},3,1,0},
 {"all_imm_32_103",{0xc1,0xe8,0x67},3,1,0},
 {"all_imm_32_104",{0xc1,0xe8,0x68},3,1,0},
 {"all_imm_32_105",{0xc1,0xe8,0x69},3,1,0},
 {"all_imm_32_106",{0xc1,0xe8,0x6a},3,1,0},
 {"all_imm_32_107",{0xc1,0xe8,0x6b},3,1,0},
 {"all_imm_32_108",{0xc1,0xe8,0x6c},3,1,0},
 {"all_imm_32_109",{0xc1,0xe8,0x6d},3,1,0},
 {"all_imm_32_110",{0xc1,0xe8,0x6e},3,1,0},
 {"all_imm_32_111",{0xc1,0xe8,0x6f},3,1,0},
 {"all_imm_32_112",{0xc1,0xe8,0x70},3,1,0},
 {"all_imm_32_113",{0xc1,0xe8,0x71},3,1,0},
 {"all_imm_32_114",{0xc1,0xe8,0x72},3,1,0},
 {"all_imm_32_115",{0xc1,0xe8,0x73},3,1,0},
 {"all_imm_32_116",{0xc1,0xe8,0x74},3,1,0},
 {"all_imm_32_117",{0xc1,0xe8,0x75},3,1,0},
 {"all_imm_32_118",{0xc1,0xe8,0x76},3,1,0},
 {"all_imm_32_119",{0xc1,0xe8,0x77},3,1,0},
 {"all_imm_32_120",{0xc1,0xe8,0x78},3,1,0},
 {"all_imm_32_121",{0xc1,0xe8,0x79},3,1,0},
 {"all_imm_32_122",{0xc1,0xe8,0x7a},3,1,0},
 {"all_imm_32_123",{0xc1,0xe8,0x7b},3,1,0},
 {"all_imm_32_124",{0xc1,0xe8,0x7c},3,1,0},
 {"all_imm_32_125",{0xc1,0xe8,0x7d},3,1,0},
 {"all_imm_32_126",{0xc1,0xe8,0x7e},3,1,0},
 {"all_imm_32_127",{0xc1,0xe8,0x7f},3,1,0},
 {"all_imm_32_128",{0xc1,0xe8,0x80},3,1,0},
 {"all_imm_32_129",{0xc1,0xe8,0x81},3,1,0},
 {"all_imm_32_130",{0xc1,0xe8,0x82},3,1,0},
 {"all_imm_32_131",{0xc1,0xe8,0x83},3,1,0},
 {"all_imm_32_132",{0xc1,0xe8,0x84},3,1,0},
 {"all_imm_32_133",{0xc1,0xe8,0x85},3,1,0},
 {"all_imm_32_134",{0xc1,0xe8,0x86},3,1,0},
 {"all_imm_32_135",{0xc1,0xe8,0x87},3,1,0},
 {"all_imm_32_136",{0xc1,0xe8,0x88},3,1,0},
 {"all_imm_32_137",{0xc1,0xe8,0x89},3,1,0},
 {"all_imm_32_138",{0xc1,0xe8,0x8a},3,1,0},
 {"all_imm_32_139",{0xc1,0xe8,0x8b},3,1,0},
 {"all_imm_32_140",{0xc1,0xe8,0x8c},3,1,0},
 {"all_imm_32_141",{0xc1,0xe8,0x8d},3,1,0},
 {"all_imm_32_142",{0xc1,0xe8,0x8e},3,1,0},
 {"all_imm_32_143",{0xc1,0xe8,0x8f},3,1,0},
 {"all_imm_32_144",{0xc1,0xe8,0x90},3,1,0},
 {"all_imm_32_145",{0xc1,0xe8,0x91},3,1,0},
 {"all_imm_32_146",{0xc1,0xe8,0x92},3,1,0},
 {"all_imm_32_147",{0xc1,0xe8,0x93},3,1,0},
 {"all_imm_32_148",{0xc1,0xe8,0x94},3,1,0},
 {"all_imm_32_149",{0xc1,0xe8,0x95},3,1,0},
 {"all_imm_32_150",{0xc1,0xe8,0x96},3,1,0},
 {"all_imm_32_151",{0xc1,0xe8,0x97},3,1,0},
 {"all_imm_32_152",{0xc1,0xe8,0x98},3,1,0},
 {"all_imm_32_153",{0xc1,0xe8,0x99},3,1,0},
 {"all_imm_32_154",{0xc1,0xe8,0x9a},3,1,0},
 {"all_imm_32_155",{0xc1,0xe8,0x9b},3,1,0},
 {"all_imm_32_156",{0xc1,0xe8,0x9c},3,1,0},
 {"all_imm_32_157",{0xc1,0xe8,0x9d},3,1,0},
 {"all_imm_32_158",{0xc1,0xe8,0x9e},3,1,0},
 {"all_imm_32_159",{0xc1,0xe8,0x9f},3,1,0},
 {"all_imm_32_160",{0xc1,0xe8,0xa0},3,1,0},
 {"all_imm_32_161",{0xc1,0xe8,0xa1},3,1,0},
 {"all_imm_32_162",{0xc1,0xe8,0xa2},3,1,0},
 {"all_imm_32_163",{0xc1,0xe8,0xa3},3,1,0},
 {"all_imm_32_164",{0xc1,0xe8,0xa4},3,1,0},
 {"all_imm_32_165",{0xc1,0xe8,0xa5},3,1,0},
 {"all_imm_32_166",{0xc1,0xe8,0xa6},3,1,0},
 {"all_imm_32_167",{0xc1,0xe8,0xa7},3,1,0},
 {"all_imm_32_168",{0xc1,0xe8,0xa8},3,1,0},
 {"all_imm_32_169",{0xc1,0xe8,0xa9},3,1,0},
 {"all_imm_32_170",{0xc1,0xe8,0xaa},3,1,0},
 {"all_imm_32_171",{0xc1,0xe8,0xab},3,1,0},
 {"all_imm_32_172",{0xc1,0xe8,0xac},3,1,0},
 {"all_imm_32_173",{0xc1,0xe8,0xad},3,1,0},
 {"all_imm_32_174",{0xc1,0xe8,0xae},3,1,0},
 {"all_imm_32_175",{0xc1,0xe8,0xaf},3,1,0},
 {"all_imm_32_176",{0xc1,0xe8,0xb0},3,1,0},
 {"all_imm_32_177",{0xc1,0xe8,0xb1},3,1,0},
 {"all_imm_32_178",{0xc1,0xe8,0xb2},3,1,0},
 {"all_imm_32_179",{0xc1,0xe8,0xb3},3,1,0},
 {"all_imm_32_180",{0xc1,0xe8,0xb4},3,1,0},
 {"all_imm_32_181",{0xc1,0xe8,0xb5},3,1,0},
 {"all_imm_32_182",{0xc1,0xe8,0xb6},3,1,0},
 {"all_imm_32_183",{0xc1,0xe8,0xb7},3,1,0},
 {"all_imm_32_184",{0xc1,0xe8,0xb8},3,1,0},
 {"all_imm_32_185",{0xc1,0xe8,0xb9},3,1,0},
 {"all_imm_32_186",{0xc1,0xe8,0xba},3,1,0},
 {"all_imm_32_187",{0xc1,0xe8,0xbb},3,1,0},
 {"all_imm_32_188",{0xc1,0xe8,0xbc},3,1,0},
 {"all_imm_32_189",{0xc1,0xe8,0xbd},3,1,0},
 {"all_imm_32_190",{0xc1,0xe8,0xbe},3,1,0},
 {"all_imm_32_191",{0xc1,0xe8,0xbf},3,1,0},
 {"all_imm_32_192",{0xc1,0xe8,0xc0},3,1,0},
 {"all_imm_32_193",{0xc1,0xe8,0xc1},3,1,0},
 {"all_imm_32_194",{0xc1,0xe8,0xc2},3,1,0},
 {"all_imm_32_195",{0xc1,0xe8,0xc3},3,1,0},
 {"all_imm_32_196",{0xc1,0xe8,0xc4},3,1,0},
 {"all_imm_32_197",{0xc1,0xe8,0xc5},3,1,0},
 {"all_imm_32_198",{0xc1,0xe8,0xc6},3,1,0},
 {"all_imm_32_199",{0xc1,0xe8,0xc7},3,1,0},
 {"all_imm_32_200",{0xc1,0xe8,0xc8},3,1,0},
 {"all_imm_32_201",{0xc1,0xe8,0xc9},3,1,0},
 {"all_imm_32_202",{0xc1,0xe8,0xca},3,1,0},
 {"all_imm_32_203",{0xc1,0xe8,0xcb},3,1,0},
 {"all_imm_32_204",{0xc1,0xe8,0xcc},3,1,0},
 {"all_imm_32_205",{0xc1,0xe8,0xcd},3,1,0},
 {"all_imm_32_206",{0xc1,0xe8,0xce},3,1,0},
 {"all_imm_32_207",{0xc1,0xe8,0xcf},3,1,0},
 {"all_imm_32_208",{0xc1,0xe8,0xd0},3,1,0},
 {"all_imm_32_209",{0xc1,0xe8,0xd1},3,1,0},
 {"all_imm_32_210",{0xc1,0xe8,0xd2},3,1,0},
 {"all_imm_32_211",{0xc1,0xe8,0xd3},3,1,0},
 {"all_imm_32_212",{0xc1,0xe8,0xd4},3,1,0},
 {"all_imm_32_213",{0xc1,0xe8,0xd5},3,1,0},
 {"all_imm_32_214",{0xc1,0xe8,0xd6},3,1,0},
 {"all_imm_32_215",{0xc1,0xe8,0xd7},3,1,0},
 {"all_imm_32_216",{0xc1,0xe8,0xd8},3,1,0},
 {"all_imm_32_217",{0xc1,0xe8,0xd9},3,1,0},
 {"all_imm_32_218",{0xc1,0xe8,0xda},3,1,0},
 {"all_imm_32_219",{0xc1,0xe8,0xdb},3,1,0},
 {"all_imm_32_220",{0xc1,0xe8,0xdc},3,1,0},
 {"all_imm_32_221",{0xc1,0xe8,0xdd},3,1,0},
 {"all_imm_32_222",{0xc1,0xe8,0xde},3,1,0},
 {"all_imm_32_223",{0xc1,0xe8,0xdf},3,1,0},
 {"all_imm_32_224",{0xc1,0xe8,0xe0},3,1,0},
 {"all_imm_32_225",{0xc1,0xe8,0xe1},3,1,0},
 {"all_imm_32_226",{0xc1,0xe8,0xe2},3,1,0},
 {"all_imm_32_227",{0xc1,0xe8,0xe3},3,1,0},
 {"all_imm_32_228",{0xc1,0xe8,0xe4},3,1,0},
 {"all_imm_32_229",{0xc1,0xe8,0xe5},3,1,0},
 {"all_imm_32_230",{0xc1,0xe8,0xe6},3,1,0},
 {"all_imm_32_231",{0xc1,0xe8,0xe7},3,1,0},
 {"all_imm_32_232",{0xc1,0xe8,0xe8},3,1,0},
 {"all_imm_32_233",{0xc1,0xe8,0xe9},3,1,0},
 {"all_imm_32_234",{0xc1,0xe8,0xea},3,1,0},
 {"all_imm_32_235",{0xc1,0xe8,0xeb},3,1,0},
 {"all_imm_32_236",{0xc1,0xe8,0xec},3,1,0},
 {"all_imm_32_237",{0xc1,0xe8,0xed},3,1,0},
 {"all_imm_32_238",{0xc1,0xe8,0xee},3,1,0},
 {"all_imm_32_239",{0xc1,0xe8,0xef},3,1,0},
 {"all_imm_32_240",{0xc1,0xe8,0xf0},3,1,0},
 {"all_imm_32_241",{0xc1,0xe8,0xf1},3,1,0},
 {"all_imm_32_242",{0xc1,0xe8,0xf2},3,1,0},
 {"all_imm_32_243",{0xc1,0xe8,0xf3},3,1,0},
 {"all_imm_32_244",{0xc1,0xe8,0xf4},3,1,0},
 {"all_imm_32_245",{0xc1,0xe8,0xf5},3,1,0},
 {"all_imm_32_246",{0xc1,0xe8,0xf6},3,1,0},
 {"all_imm_32_247",{0xc1,0xe8,0xf7},3,1,0},
 {"all_imm_32_248",{0xc1,0xe8,0xf8},3,1,0},
 {"all_imm_32_249",{0xc1,0xe8,0xf9},3,1,0},
 {"all_imm_32_250",{0xc1,0xe8,0xfa},3,1,0},
 {"all_imm_32_251",{0xc1,0xe8,0xfb},3,1,0},
 {"all_imm_32_252",{0xc1,0xe8,0xfc},3,1,0},
 {"all_imm_32_253",{0xc1,0xe8,0xfd},3,1,0},
 {"all_imm_32_254",{0xc1,0xe8,0xfe},3,1,0},
 {"all_imm_32_255",{0xc1,0xe8,0xff},3,1,0},
 {"all_imm_64_0",{0x48,0xc1,0xe8,0x0},4,1,0},
 {"all_imm_64_1",{0x48,0xc1,0xe8,0x1},4,1,0},
 {"all_imm_64_2",{0x48,0xc1,0xe8,0x2},4,1,0},
 {"all_imm_64_3",{0x48,0xc1,0xe8,0x3},4,1,0},
 {"all_imm_64_4",{0x48,0xc1,0xe8,0x4},4,1,0},
 {"all_imm_64_5",{0x48,0xc1,0xe8,0x5},4,1,0},
 {"all_imm_64_6",{0x48,0xc1,0xe8,0x6},4,1,0},
 {"all_imm_64_7",{0x48,0xc1,0xe8,0x7},4,1,0},
 {"all_imm_64_8",{0x48,0xc1,0xe8,0x8},4,1,0},
 {"all_imm_64_9",{0x48,0xc1,0xe8,0x9},4,1,0},
 {"all_imm_64_10",{0x48,0xc1,0xe8,0xa},4,1,0},
 {"all_imm_64_11",{0x48,0xc1,0xe8,0xb},4,1,0},
 {"all_imm_64_12",{0x48,0xc1,0xe8,0xc},4,1,0},
 {"all_imm_64_13",{0x48,0xc1,0xe8,0xd},4,1,0},
 {"all_imm_64_14",{0x48,0xc1,0xe8,0xe},4,1,0},
 {"all_imm_64_15",{0x48,0xc1,0xe8,0xf},4,1,0},
 {"all_imm_64_16",{0x48,0xc1,0xe8,0x10},4,1,0},
 {"all_imm_64_17",{0x48,0xc1,0xe8,0x11},4,1,0},
 {"all_imm_64_18",{0x48,0xc1,0xe8,0x12},4,1,0},
 {"all_imm_64_19",{0x48,0xc1,0xe8,0x13},4,1,0},
 {"all_imm_64_20",{0x48,0xc1,0xe8,0x14},4,1,0},
 {"all_imm_64_21",{0x48,0xc1,0xe8,0x15},4,1,0},
 {"all_imm_64_22",{0x48,0xc1,0xe8,0x16},4,1,0},
 {"all_imm_64_23",{0x48,0xc1,0xe8,0x17},4,1,0},
 {"all_imm_64_24",{0x48,0xc1,0xe8,0x18},4,1,0},
 {"all_imm_64_25",{0x48,0xc1,0xe8,0x19},4,1,0},
 {"all_imm_64_26",{0x48,0xc1,0xe8,0x1a},4,1,0},
 {"all_imm_64_27",{0x48,0xc1,0xe8,0x1b},4,1,0},
 {"all_imm_64_28",{0x48,0xc1,0xe8,0x1c},4,1,0},
 {"all_imm_64_29",{0x48,0xc1,0xe8,0x1d},4,1,0},
 {"all_imm_64_30",{0x48,0xc1,0xe8,0x1e},4,1,0},
 {"all_imm_64_31",{0x48,0xc1,0xe8,0x1f},4,1,0},
 {"all_imm_64_32",{0x48,0xc1,0xe8,0x20},4,1,0},
 {"all_imm_64_33",{0x48,0xc1,0xe8,0x21},4,1,0},
 {"all_imm_64_34",{0x48,0xc1,0xe8,0x22},4,1,0},
 {"all_imm_64_35",{0x48,0xc1,0xe8,0x23},4,1,0},
 {"all_imm_64_36",{0x48,0xc1,0xe8,0x24},4,1,0},
 {"all_imm_64_37",{0x48,0xc1,0xe8,0x25},4,1,0},
 {"all_imm_64_38",{0x48,0xc1,0xe8,0x26},4,1,0},
 {"all_imm_64_39",{0x48,0xc1,0xe8,0x27},4,1,0},
 {"all_imm_64_40",{0x48,0xc1,0xe8,0x28},4,1,0},
 {"all_imm_64_41",{0x48,0xc1,0xe8,0x29},4,1,0},
 {"all_imm_64_42",{0x48,0xc1,0xe8,0x2a},4,1,0},
 {"all_imm_64_43",{0x48,0xc1,0xe8,0x2b},4,1,0},
 {"all_imm_64_44",{0x48,0xc1,0xe8,0x2c},4,1,0},
 {"all_imm_64_45",{0x48,0xc1,0xe8,0x2d},4,1,0},
 {"all_imm_64_46",{0x48,0xc1,0xe8,0x2e},4,1,0},
 {"all_imm_64_47",{0x48,0xc1,0xe8,0x2f},4,1,0},
 {"all_imm_64_48",{0x48,0xc1,0xe8,0x30},4,1,0},
 {"all_imm_64_49",{0x48,0xc1,0xe8,0x31},4,1,0},
 {"all_imm_64_50",{0x48,0xc1,0xe8,0x32},4,1,0},
 {"all_imm_64_51",{0x48,0xc1,0xe8,0x33},4,1,0},
 {"all_imm_64_52",{0x48,0xc1,0xe8,0x34},4,1,0},
 {"all_imm_64_53",{0x48,0xc1,0xe8,0x35},4,1,0},
 {"all_imm_64_54",{0x48,0xc1,0xe8,0x36},4,1,0},
 {"all_imm_64_55",{0x48,0xc1,0xe8,0x37},4,1,0},
 {"all_imm_64_56",{0x48,0xc1,0xe8,0x38},4,1,0},
 {"all_imm_64_57",{0x48,0xc1,0xe8,0x39},4,1,0},
 {"all_imm_64_58",{0x48,0xc1,0xe8,0x3a},4,1,0},
 {"all_imm_64_59",{0x48,0xc1,0xe8,0x3b},4,1,0},
 {"all_imm_64_60",{0x48,0xc1,0xe8,0x3c},4,1,0},
 {"all_imm_64_61",{0x48,0xc1,0xe8,0x3d},4,1,0},
 {"all_imm_64_62",{0x48,0xc1,0xe8,0x3e},4,1,0},
 {"all_imm_64_63",{0x48,0xc1,0xe8,0x3f},4,1,0},
 {"all_imm_64_64",{0x48,0xc1,0xe8,0x40},4,1,0},
 {"all_imm_64_65",{0x48,0xc1,0xe8,0x41},4,1,0},
 {"all_imm_64_66",{0x48,0xc1,0xe8,0x42},4,1,0},
 {"all_imm_64_67",{0x48,0xc1,0xe8,0x43},4,1,0},
 {"all_imm_64_68",{0x48,0xc1,0xe8,0x44},4,1,0},
 {"all_imm_64_69",{0x48,0xc1,0xe8,0x45},4,1,0},
 {"all_imm_64_70",{0x48,0xc1,0xe8,0x46},4,1,0},
 {"all_imm_64_71",{0x48,0xc1,0xe8,0x47},4,1,0},
 {"all_imm_64_72",{0x48,0xc1,0xe8,0x48},4,1,0},
 {"all_imm_64_73",{0x48,0xc1,0xe8,0x49},4,1,0},
 {"all_imm_64_74",{0x48,0xc1,0xe8,0x4a},4,1,0},
 {"all_imm_64_75",{0x48,0xc1,0xe8,0x4b},4,1,0},
 {"all_imm_64_76",{0x48,0xc1,0xe8,0x4c},4,1,0},
 {"all_imm_64_77",{0x48,0xc1,0xe8,0x4d},4,1,0},
 {"all_imm_64_78",{0x48,0xc1,0xe8,0x4e},4,1,0},
 {"all_imm_64_79",{0x48,0xc1,0xe8,0x4f},4,1,0},
 {"all_imm_64_80",{0x48,0xc1,0xe8,0x50},4,1,0},
 {"all_imm_64_81",{0x48,0xc1,0xe8,0x51},4,1,0},
 {"all_imm_64_82",{0x48,0xc1,0xe8,0x52},4,1,0},
 {"all_imm_64_83",{0x48,0xc1,0xe8,0x53},4,1,0},
 {"all_imm_64_84",{0x48,0xc1,0xe8,0x54},4,1,0},
 {"all_imm_64_85",{0x48,0xc1,0xe8,0x55},4,1,0},
 {"all_imm_64_86",{0x48,0xc1,0xe8,0x56},4,1,0},
 {"all_imm_64_87",{0x48,0xc1,0xe8,0x57},4,1,0},
 {"all_imm_64_88",{0x48,0xc1,0xe8,0x58},4,1,0},
 {"all_imm_64_89",{0x48,0xc1,0xe8,0x59},4,1,0},
 {"all_imm_64_90",{0x48,0xc1,0xe8,0x5a},4,1,0},
 {"all_imm_64_91",{0x48,0xc1,0xe8,0x5b},4,1,0},
 {"all_imm_64_92",{0x48,0xc1,0xe8,0x5c},4,1,0},
 {"all_imm_64_93",{0x48,0xc1,0xe8,0x5d},4,1,0},
 {"all_imm_64_94",{0x48,0xc1,0xe8,0x5e},4,1,0},
 {"all_imm_64_95",{0x48,0xc1,0xe8,0x5f},4,1,0},
 {"all_imm_64_96",{0x48,0xc1,0xe8,0x60},4,1,0},
 {"all_imm_64_97",{0x48,0xc1,0xe8,0x61},4,1,0},
 {"all_imm_64_98",{0x48,0xc1,0xe8,0x62},4,1,0},
 {"all_imm_64_99",{0x48,0xc1,0xe8,0x63},4,1,0},
 {"all_imm_64_100",{0x48,0xc1,0xe8,0x64},4,1,0},
 {"all_imm_64_101",{0x48,0xc1,0xe8,0x65},4,1,0},
 {"all_imm_64_102",{0x48,0xc1,0xe8,0x66},4,1,0},
 {"all_imm_64_103",{0x48,0xc1,0xe8,0x67},4,1,0},
 {"all_imm_64_104",{0x48,0xc1,0xe8,0x68},4,1,0},
 {"all_imm_64_105",{0x48,0xc1,0xe8,0x69},4,1,0},
 {"all_imm_64_106",{0x48,0xc1,0xe8,0x6a},4,1,0},
 {"all_imm_64_107",{0x48,0xc1,0xe8,0x6b},4,1,0},
 {"all_imm_64_108",{0x48,0xc1,0xe8,0x6c},4,1,0},
 {"all_imm_64_109",{0x48,0xc1,0xe8,0x6d},4,1,0},
 {"all_imm_64_110",{0x48,0xc1,0xe8,0x6e},4,1,0},
 {"all_imm_64_111",{0x48,0xc1,0xe8,0x6f},4,1,0},
 {"all_imm_64_112",{0x48,0xc1,0xe8,0x70},4,1,0},
 {"all_imm_64_113",{0x48,0xc1,0xe8,0x71},4,1,0},
 {"all_imm_64_114",{0x48,0xc1,0xe8,0x72},4,1,0},
 {"all_imm_64_115",{0x48,0xc1,0xe8,0x73},4,1,0},
 {"all_imm_64_116",{0x48,0xc1,0xe8,0x74},4,1,0},
 {"all_imm_64_117",{0x48,0xc1,0xe8,0x75},4,1,0},
 {"all_imm_64_118",{0x48,0xc1,0xe8,0x76},4,1,0},
 {"all_imm_64_119",{0x48,0xc1,0xe8,0x77},4,1,0},
 {"all_imm_64_120",{0x48,0xc1,0xe8,0x78},4,1,0},
 {"all_imm_64_121",{0x48,0xc1,0xe8,0x79},4,1,0},
 {"all_imm_64_122",{0x48,0xc1,0xe8,0x7a},4,1,0},
 {"all_imm_64_123",{0x48,0xc1,0xe8,0x7b},4,1,0},
 {"all_imm_64_124",{0x48,0xc1,0xe8,0x7c},4,1,0},
 {"all_imm_64_125",{0x48,0xc1,0xe8,0x7d},4,1,0},
 {"all_imm_64_126",{0x48,0xc1,0xe8,0x7e},4,1,0},
 {"all_imm_64_127",{0x48,0xc1,0xe8,0x7f},4,1,0},
 {"all_imm_64_128",{0x48,0xc1,0xe8,0x80},4,1,0},
 {"all_imm_64_129",{0x48,0xc1,0xe8,0x81},4,1,0},
 {"all_imm_64_130",{0x48,0xc1,0xe8,0x82},4,1,0},
 {"all_imm_64_131",{0x48,0xc1,0xe8,0x83},4,1,0},
 {"all_imm_64_132",{0x48,0xc1,0xe8,0x84},4,1,0},
 {"all_imm_64_133",{0x48,0xc1,0xe8,0x85},4,1,0},
 {"all_imm_64_134",{0x48,0xc1,0xe8,0x86},4,1,0},
 {"all_imm_64_135",{0x48,0xc1,0xe8,0x87},4,1,0},
 {"all_imm_64_136",{0x48,0xc1,0xe8,0x88},4,1,0},
 {"all_imm_64_137",{0x48,0xc1,0xe8,0x89},4,1,0},
 {"all_imm_64_138",{0x48,0xc1,0xe8,0x8a},4,1,0},
 {"all_imm_64_139",{0x48,0xc1,0xe8,0x8b},4,1,0},
 {"all_imm_64_140",{0x48,0xc1,0xe8,0x8c},4,1,0},
 {"all_imm_64_141",{0x48,0xc1,0xe8,0x8d},4,1,0},
 {"all_imm_64_142",{0x48,0xc1,0xe8,0x8e},4,1,0},
 {"all_imm_64_143",{0x48,0xc1,0xe8,0x8f},4,1,0},
 {"all_imm_64_144",{0x48,0xc1,0xe8,0x90},4,1,0},
 {"all_imm_64_145",{0x48,0xc1,0xe8,0x91},4,1,0},
 {"all_imm_64_146",{0x48,0xc1,0xe8,0x92},4,1,0},
 {"all_imm_64_147",{0x48,0xc1,0xe8,0x93},4,1,0},
 {"all_imm_64_148",{0x48,0xc1,0xe8,0x94},4,1,0},
 {"all_imm_64_149",{0x48,0xc1,0xe8,0x95},4,1,0},
 {"all_imm_64_150",{0x48,0xc1,0xe8,0x96},4,1,0},
 {"all_imm_64_151",{0x48,0xc1,0xe8,0x97},4,1,0},
 {"all_imm_64_152",{0x48,0xc1,0xe8,0x98},4,1,0},
 {"all_imm_64_153",{0x48,0xc1,0xe8,0x99},4,1,0},
 {"all_imm_64_154",{0x48,0xc1,0xe8,0x9a},4,1,0},
 {"all_imm_64_155",{0x48,0xc1,0xe8,0x9b},4,1,0},
 {"all_imm_64_156",{0x48,0xc1,0xe8,0x9c},4,1,0},
 {"all_imm_64_157",{0x48,0xc1,0xe8,0x9d},4,1,0},
 {"all_imm_64_158",{0x48,0xc1,0xe8,0x9e},4,1,0},
 {"all_imm_64_159",{0x48,0xc1,0xe8,0x9f},4,1,0},
 {"all_imm_64_160",{0x48,0xc1,0xe8,0xa0},4,1,0},
 {"all_imm_64_161",{0x48,0xc1,0xe8,0xa1},4,1,0},
 {"all_imm_64_162",{0x48,0xc1,0xe8,0xa2},4,1,0},
 {"all_imm_64_163",{0x48,0xc1,0xe8,0xa3},4,1,0},
 {"all_imm_64_164",{0x48,0xc1,0xe8,0xa4},4,1,0},
 {"all_imm_64_165",{0x48,0xc1,0xe8,0xa5},4,1,0},
 {"all_imm_64_166",{0x48,0xc1,0xe8,0xa6},4,1,0},
 {"all_imm_64_167",{0x48,0xc1,0xe8,0xa7},4,1,0},
 {"all_imm_64_168",{0x48,0xc1,0xe8,0xa8},4,1,0},
 {"all_imm_64_169",{0x48,0xc1,0xe8,0xa9},4,1,0},
 {"all_imm_64_170",{0x48,0xc1,0xe8,0xaa},4,1,0},
 {"all_imm_64_171",{0x48,0xc1,0xe8,0xab},4,1,0},
 {"all_imm_64_172",{0x48,0xc1,0xe8,0xac},4,1,0},
 {"all_imm_64_173",{0x48,0xc1,0xe8,0xad},4,1,0},
 {"all_imm_64_174",{0x48,0xc1,0xe8,0xae},4,1,0},
 {"all_imm_64_175",{0x48,0xc1,0xe8,0xaf},4,1,0},
 {"all_imm_64_176",{0x48,0xc1,0xe8,0xb0},4,1,0},
 {"all_imm_64_177",{0x48,0xc1,0xe8,0xb1},4,1,0},
 {"all_imm_64_178",{0x48,0xc1,0xe8,0xb2},4,1,0},
 {"all_imm_64_179",{0x48,0xc1,0xe8,0xb3},4,1,0},
 {"all_imm_64_180",{0x48,0xc1,0xe8,0xb4},4,1,0},
 {"all_imm_64_181",{0x48,0xc1,0xe8,0xb5},4,1,0},
 {"all_imm_64_182",{0x48,0xc1,0xe8,0xb6},4,1,0},
 {"all_imm_64_183",{0x48,0xc1,0xe8,0xb7},4,1,0},
 {"all_imm_64_184",{0x48,0xc1,0xe8,0xb8},4,1,0},
 {"all_imm_64_185",{0x48,0xc1,0xe8,0xb9},4,1,0},
 {"all_imm_64_186",{0x48,0xc1,0xe8,0xba},4,1,0},
 {"all_imm_64_187",{0x48,0xc1,0xe8,0xbb},4,1,0},
 {"all_imm_64_188",{0x48,0xc1,0xe8,0xbc},4,1,0},
 {"all_imm_64_189",{0x48,0xc1,0xe8,0xbd},4,1,0},
 {"all_imm_64_190",{0x48,0xc1,0xe8,0xbe},4,1,0},
 {"all_imm_64_191",{0x48,0xc1,0xe8,0xbf},4,1,0},
 {"all_imm_64_192",{0x48,0xc1,0xe8,0xc0},4,1,0},
 {"all_imm_64_193",{0x48,0xc1,0xe8,0xc1},4,1,0},
 {"all_imm_64_194",{0x48,0xc1,0xe8,0xc2},4,1,0},
 {"all_imm_64_195",{0x48,0xc1,0xe8,0xc3},4,1,0},
 {"all_imm_64_196",{0x48,0xc1,0xe8,0xc4},4,1,0},
 {"all_imm_64_197",{0x48,0xc1,0xe8,0xc5},4,1,0},
 {"all_imm_64_198",{0x48,0xc1,0xe8,0xc6},4,1,0},
 {"all_imm_64_199",{0x48,0xc1,0xe8,0xc7},4,1,0},
 {"all_imm_64_200",{0x48,0xc1,0xe8,0xc8},4,1,0},
 {"all_imm_64_201",{0x48,0xc1,0xe8,0xc9},4,1,0},
 {"all_imm_64_202",{0x48,0xc1,0xe8,0xca},4,1,0},
 {"all_imm_64_203",{0x48,0xc1,0xe8,0xcb},4,1,0},
 {"all_imm_64_204",{0x48,0xc1,0xe8,0xcc},4,1,0},
 {"all_imm_64_205",{0x48,0xc1,0xe8,0xcd},4,1,0},
 {"all_imm_64_206",{0x48,0xc1,0xe8,0xce},4,1,0},
 {"all_imm_64_207",{0x48,0xc1,0xe8,0xcf},4,1,0},
 {"all_imm_64_208",{0x48,0xc1,0xe8,0xd0},4,1,0},
 {"all_imm_64_209",{0x48,0xc1,0xe8,0xd1},4,1,0},
 {"all_imm_64_210",{0x48,0xc1,0xe8,0xd2},4,1,0},
 {"all_imm_64_211",{0x48,0xc1,0xe8,0xd3},4,1,0},
 {"all_imm_64_212",{0x48,0xc1,0xe8,0xd4},4,1,0},
 {"all_imm_64_213",{0x48,0xc1,0xe8,0xd5},4,1,0},
 {"all_imm_64_214",{0x48,0xc1,0xe8,0xd6},4,1,0},
 {"all_imm_64_215",{0x48,0xc1,0xe8,0xd7},4,1,0},
 {"all_imm_64_216",{0x48,0xc1,0xe8,0xd8},4,1,0},
 {"all_imm_64_217",{0x48,0xc1,0xe8,0xd9},4,1,0},
 {"all_imm_64_218",{0x48,0xc1,0xe8,0xda},4,1,0},
 {"all_imm_64_219",{0x48,0xc1,0xe8,0xdb},4,1,0},
 {"all_imm_64_220",{0x48,0xc1,0xe8,0xdc},4,1,0},
 {"all_imm_64_221",{0x48,0xc1,0xe8,0xdd},4,1,0},
 {"all_imm_64_222",{0x48,0xc1,0xe8,0xde},4,1,0},
 {"all_imm_64_223",{0x48,0xc1,0xe8,0xdf},4,1,0},
 {"all_imm_64_224",{0x48,0xc1,0xe8,0xe0},4,1,0},
 {"all_imm_64_225",{0x48,0xc1,0xe8,0xe1},4,1,0},
 {"all_imm_64_226",{0x48,0xc1,0xe8,0xe2},4,1,0},
 {"all_imm_64_227",{0x48,0xc1,0xe8,0xe3},4,1,0},
 {"all_imm_64_228",{0x48,0xc1,0xe8,0xe4},4,1,0},
 {"all_imm_64_229",{0x48,0xc1,0xe8,0xe5},4,1,0},
 {"all_imm_64_230",{0x48,0xc1,0xe8,0xe6},4,1,0},
 {"all_imm_64_231",{0x48,0xc1,0xe8,0xe7},4,1,0},
 {"all_imm_64_232",{0x48,0xc1,0xe8,0xe8},4,1,0},
 {"all_imm_64_233",{0x48,0xc1,0xe8,0xe9},4,1,0},
 {"all_imm_64_234",{0x48,0xc1,0xe8,0xea},4,1,0},
 {"all_imm_64_235",{0x48,0xc1,0xe8,0xeb},4,1,0},
 {"all_imm_64_236",{0x48,0xc1,0xe8,0xec},4,1,0},
 {"all_imm_64_237",{0x48,0xc1,0xe8,0xed},4,1,0},
 {"all_imm_64_238",{0x48,0xc1,0xe8,0xee},4,1,0},
 {"all_imm_64_239",{0x48,0xc1,0xe8,0xef},4,1,0},
 {"all_imm_64_240",{0x48,0xc1,0xe8,0xf0},4,1,0},
 {"all_imm_64_241",{0x48,0xc1,0xe8,0xf1},4,1,0},
 {"all_imm_64_242",{0x48,0xc1,0xe8,0xf2},4,1,0},
 {"all_imm_64_243",{0x48,0xc1,0xe8,0xf3},4,1,0},
 {"all_imm_64_244",{0x48,0xc1,0xe8,0xf4},4,1,0},
 {"all_imm_64_245",{0x48,0xc1,0xe8,0xf5},4,1,0},
 {"all_imm_64_246",{0x48,0xc1,0xe8,0xf6},4,1,0},
 {"all_imm_64_247",{0x48,0xc1,0xe8,0xf7},4,1,0},
 {"all_imm_64_248",{0x48,0xc1,0xe8,0xf8},4,1,0},
 {"all_imm_64_249",{0x48,0xc1,0xe8,0xf9},4,1,0},
 {"all_imm_64_250",{0x48,0xc1,0xe8,0xfa},4,1,0},
 {"all_imm_64_251",{0x48,0xc1,0xe8,0xfb},4,1,0},
 {"all_imm_64_252",{0x48,0xc1,0xe8,0xfc},4,1,0},
 {"all_imm_64_253",{0x48,0xc1,0xe8,0xfd},4,1,0},
 {"all_imm_64_254",{0x48,0xc1,0xe8,0xfe},4,1,0},
 {"all_imm_64_255",{0x48,0xc1,0xe8,0xff},4,1,0},
 {"shl64_cl_full",{0x48,0xd3,0xe0},3,1,0},
 {"shl32_cl_full",{0xd3,0xe2},2,1,0},
 {"shl64_cl_high",{0x49,0xd3,0xe2},3,1,0},
 {"shl32_cl_high",{0x41,0xd3,0xe3},3,1,0},
 {"shl64_cl_alias",{0x48,0xd3,0xe1},3,1,0},
 {"shl32_cl_alias",{0xd3,0xe1},2,1,0},
 {"shl16_fallback",{0x66,0xc1,0xe0,1},4,0,0},
 {"shl_rsp_zero_fallback",{0x48,0xc1,0xe4,0},4,0,0},
 {"shl_imm_32_0",{0xc1,0xe0,0x0},3,1,0},
 {"shl_imm_32_1",{0xc1,0xe0,0x1},3,1,0},
 {"shl_imm_32_2",{0xc1,0xe0,0x2},3,1,0},
 {"shl_imm_32_3",{0xc1,0xe0,0x3},3,1,0},
 {"shl_imm_32_4",{0xc1,0xe0,0x4},3,1,0},
 {"shl_imm_32_5",{0xc1,0xe0,0x5},3,1,0},
 {"shl_imm_32_6",{0xc1,0xe0,0x6},3,1,0},
 {"shl_imm_32_7",{0xc1,0xe0,0x7},3,1,0},
 {"shl_imm_32_8",{0xc1,0xe0,0x8},3,1,0},
 {"shl_imm_32_9",{0xc1,0xe0,0x9},3,1,0},
 {"shl_imm_32_10",{0xc1,0xe0,0xa},3,1,0},
 {"shl_imm_32_11",{0xc1,0xe0,0xb},3,1,0},
 {"shl_imm_32_12",{0xc1,0xe0,0xc},3,1,0},
 {"shl_imm_32_13",{0xc1,0xe0,0xd},3,1,0},
 {"shl_imm_32_14",{0xc1,0xe0,0xe},3,1,0},
 {"shl_imm_32_15",{0xc1,0xe0,0xf},3,1,0},
 {"shl_imm_32_16",{0xc1,0xe0,0x10},3,1,0},
 {"shl_imm_32_17",{0xc1,0xe0,0x11},3,1,0},
 {"shl_imm_32_18",{0xc1,0xe0,0x12},3,1,0},
 {"shl_imm_32_19",{0xc1,0xe0,0x13},3,1,0},
 {"shl_imm_32_20",{0xc1,0xe0,0x14},3,1,0},
 {"shl_imm_32_21",{0xc1,0xe0,0x15},3,1,0},
 {"shl_imm_32_22",{0xc1,0xe0,0x16},3,1,0},
 {"shl_imm_32_23",{0xc1,0xe0,0x17},3,1,0},
 {"shl_imm_32_24",{0xc1,0xe0,0x18},3,1,0},
 {"shl_imm_32_25",{0xc1,0xe0,0x19},3,1,0},
 {"shl_imm_32_26",{0xc1,0xe0,0x1a},3,1,0},
 {"shl_imm_32_27",{0xc1,0xe0,0x1b},3,1,0},
 {"shl_imm_32_28",{0xc1,0xe0,0x1c},3,1,0},
 {"shl_imm_32_29",{0xc1,0xe0,0x1d},3,1,0},
 {"shl_imm_32_30",{0xc1,0xe0,0x1e},3,1,0},
 {"shl_imm_32_31",{0xc1,0xe0,0x1f},3,1,0},
 {"shl_imm_32_32",{0xc1,0xe0,0x20},3,1,0},
 {"shl_imm_32_33",{0xc1,0xe0,0x21},3,1,0},
 {"shl_imm_32_34",{0xc1,0xe0,0x22},3,1,0},
 {"shl_imm_32_35",{0xc1,0xe0,0x23},3,1,0},
 {"shl_imm_32_36",{0xc1,0xe0,0x24},3,1,0},
 {"shl_imm_32_37",{0xc1,0xe0,0x25},3,1,0},
 {"shl_imm_32_38",{0xc1,0xe0,0x26},3,1,0},
 {"shl_imm_32_39",{0xc1,0xe0,0x27},3,1,0},
 {"shl_imm_32_40",{0xc1,0xe0,0x28},3,1,0},
 {"shl_imm_32_41",{0xc1,0xe0,0x29},3,1,0},
 {"shl_imm_32_42",{0xc1,0xe0,0x2a},3,1,0},
 {"shl_imm_32_43",{0xc1,0xe0,0x2b},3,1,0},
 {"shl_imm_32_44",{0xc1,0xe0,0x2c},3,1,0},
 {"shl_imm_32_45",{0xc1,0xe0,0x2d},3,1,0},
 {"shl_imm_32_46",{0xc1,0xe0,0x2e},3,1,0},
 {"shl_imm_32_47",{0xc1,0xe0,0x2f},3,1,0},
 {"shl_imm_32_48",{0xc1,0xe0,0x30},3,1,0},
 {"shl_imm_32_49",{0xc1,0xe0,0x31},3,1,0},
 {"shl_imm_32_50",{0xc1,0xe0,0x32},3,1,0},
 {"shl_imm_32_51",{0xc1,0xe0,0x33},3,1,0},
 {"shl_imm_32_52",{0xc1,0xe0,0x34},3,1,0},
 {"shl_imm_32_53",{0xc1,0xe0,0x35},3,1,0},
 {"shl_imm_32_54",{0xc1,0xe0,0x36},3,1,0},
 {"shl_imm_32_55",{0xc1,0xe0,0x37},3,1,0},
 {"shl_imm_32_56",{0xc1,0xe0,0x38},3,1,0},
 {"shl_imm_32_57",{0xc1,0xe0,0x39},3,1,0},
 {"shl_imm_32_58",{0xc1,0xe0,0x3a},3,1,0},
 {"shl_imm_32_59",{0xc1,0xe0,0x3b},3,1,0},
 {"shl_imm_32_60",{0xc1,0xe0,0x3c},3,1,0},
 {"shl_imm_32_61",{0xc1,0xe0,0x3d},3,1,0},
 {"shl_imm_32_62",{0xc1,0xe0,0x3e},3,1,0},
 {"shl_imm_32_63",{0xc1,0xe0,0x3f},3,1,0},
 {"shl_imm_32_64",{0xc1,0xe0,0x40},3,1,0},
 {"shl_imm_32_65",{0xc1,0xe0,0x41},3,1,0},
 {"shl_imm_32_66",{0xc1,0xe0,0x42},3,1,0},
 {"shl_imm_32_67",{0xc1,0xe0,0x43},3,1,0},
 {"shl_imm_32_68",{0xc1,0xe0,0x44},3,1,0},
 {"shl_imm_32_69",{0xc1,0xe0,0x45},3,1,0},
 {"shl_imm_32_70",{0xc1,0xe0,0x46},3,1,0},
 {"shl_imm_32_71",{0xc1,0xe0,0x47},3,1,0},
 {"shl_imm_32_72",{0xc1,0xe0,0x48},3,1,0},
 {"shl_imm_32_73",{0xc1,0xe0,0x49},3,1,0},
 {"shl_imm_32_74",{0xc1,0xe0,0x4a},3,1,0},
 {"shl_imm_32_75",{0xc1,0xe0,0x4b},3,1,0},
 {"shl_imm_32_76",{0xc1,0xe0,0x4c},3,1,0},
 {"shl_imm_32_77",{0xc1,0xe0,0x4d},3,1,0},
 {"shl_imm_32_78",{0xc1,0xe0,0x4e},3,1,0},
 {"shl_imm_32_79",{0xc1,0xe0,0x4f},3,1,0},
 {"shl_imm_32_80",{0xc1,0xe0,0x50},3,1,0},
 {"shl_imm_32_81",{0xc1,0xe0,0x51},3,1,0},
 {"shl_imm_32_82",{0xc1,0xe0,0x52},3,1,0},
 {"shl_imm_32_83",{0xc1,0xe0,0x53},3,1,0},
 {"shl_imm_32_84",{0xc1,0xe0,0x54},3,1,0},
 {"shl_imm_32_85",{0xc1,0xe0,0x55},3,1,0},
 {"shl_imm_32_86",{0xc1,0xe0,0x56},3,1,0},
 {"shl_imm_32_87",{0xc1,0xe0,0x57},3,1,0},
 {"shl_imm_32_88",{0xc1,0xe0,0x58},3,1,0},
 {"shl_imm_32_89",{0xc1,0xe0,0x59},3,1,0},
 {"shl_imm_32_90",{0xc1,0xe0,0x5a},3,1,0},
 {"shl_imm_32_91",{0xc1,0xe0,0x5b},3,1,0},
 {"shl_imm_32_92",{0xc1,0xe0,0x5c},3,1,0},
 {"shl_imm_32_93",{0xc1,0xe0,0x5d},3,1,0},
 {"shl_imm_32_94",{0xc1,0xe0,0x5e},3,1,0},
 {"shl_imm_32_95",{0xc1,0xe0,0x5f},3,1,0},
 {"shl_imm_32_96",{0xc1,0xe0,0x60},3,1,0},
 {"shl_imm_32_97",{0xc1,0xe0,0x61},3,1,0},
 {"shl_imm_32_98",{0xc1,0xe0,0x62},3,1,0},
 {"shl_imm_32_99",{0xc1,0xe0,0x63},3,1,0},
 {"shl_imm_32_100",{0xc1,0xe0,0x64},3,1,0},
 {"shl_imm_32_101",{0xc1,0xe0,0x65},3,1,0},
 {"shl_imm_32_102",{0xc1,0xe0,0x66},3,1,0},
 {"shl_imm_32_103",{0xc1,0xe0,0x67},3,1,0},
 {"shl_imm_32_104",{0xc1,0xe0,0x68},3,1,0},
 {"shl_imm_32_105",{0xc1,0xe0,0x69},3,1,0},
 {"shl_imm_32_106",{0xc1,0xe0,0x6a},3,1,0},
 {"shl_imm_32_107",{0xc1,0xe0,0x6b},3,1,0},
 {"shl_imm_32_108",{0xc1,0xe0,0x6c},3,1,0},
 {"shl_imm_32_109",{0xc1,0xe0,0x6d},3,1,0},
 {"shl_imm_32_110",{0xc1,0xe0,0x6e},3,1,0},
 {"shl_imm_32_111",{0xc1,0xe0,0x6f},3,1,0},
 {"shl_imm_32_112",{0xc1,0xe0,0x70},3,1,0},
 {"shl_imm_32_113",{0xc1,0xe0,0x71},3,1,0},
 {"shl_imm_32_114",{0xc1,0xe0,0x72},3,1,0},
 {"shl_imm_32_115",{0xc1,0xe0,0x73},3,1,0},
 {"shl_imm_32_116",{0xc1,0xe0,0x74},3,1,0},
 {"shl_imm_32_117",{0xc1,0xe0,0x75},3,1,0},
 {"shl_imm_32_118",{0xc1,0xe0,0x76},3,1,0},
 {"shl_imm_32_119",{0xc1,0xe0,0x77},3,1,0},
 {"shl_imm_32_120",{0xc1,0xe0,0x78},3,1,0},
 {"shl_imm_32_121",{0xc1,0xe0,0x79},3,1,0},
 {"shl_imm_32_122",{0xc1,0xe0,0x7a},3,1,0},
 {"shl_imm_32_123",{0xc1,0xe0,0x7b},3,1,0},
 {"shl_imm_32_124",{0xc1,0xe0,0x7c},3,1,0},
 {"shl_imm_32_125",{0xc1,0xe0,0x7d},3,1,0},
 {"shl_imm_32_126",{0xc1,0xe0,0x7e},3,1,0},
 {"shl_imm_32_127",{0xc1,0xe0,0x7f},3,1,0},
 {"shl_imm_32_128",{0xc1,0xe0,0x80},3,1,0},
 {"shl_imm_32_129",{0xc1,0xe0,0x81},3,1,0},
 {"shl_imm_32_130",{0xc1,0xe0,0x82},3,1,0},
 {"shl_imm_32_131",{0xc1,0xe0,0x83},3,1,0},
 {"shl_imm_32_132",{0xc1,0xe0,0x84},3,1,0},
 {"shl_imm_32_133",{0xc1,0xe0,0x85},3,1,0},
 {"shl_imm_32_134",{0xc1,0xe0,0x86},3,1,0},
 {"shl_imm_32_135",{0xc1,0xe0,0x87},3,1,0},
 {"shl_imm_32_136",{0xc1,0xe0,0x88},3,1,0},
 {"shl_imm_32_137",{0xc1,0xe0,0x89},3,1,0},
 {"shl_imm_32_138",{0xc1,0xe0,0x8a},3,1,0},
 {"shl_imm_32_139",{0xc1,0xe0,0x8b},3,1,0},
 {"shl_imm_32_140",{0xc1,0xe0,0x8c},3,1,0},
 {"shl_imm_32_141",{0xc1,0xe0,0x8d},3,1,0},
 {"shl_imm_32_142",{0xc1,0xe0,0x8e},3,1,0},
 {"shl_imm_32_143",{0xc1,0xe0,0x8f},3,1,0},
 {"shl_imm_32_144",{0xc1,0xe0,0x90},3,1,0},
 {"shl_imm_32_145",{0xc1,0xe0,0x91},3,1,0},
 {"shl_imm_32_146",{0xc1,0xe0,0x92},3,1,0},
 {"shl_imm_32_147",{0xc1,0xe0,0x93},3,1,0},
 {"shl_imm_32_148",{0xc1,0xe0,0x94},3,1,0},
 {"shl_imm_32_149",{0xc1,0xe0,0x95},3,1,0},
 {"shl_imm_32_150",{0xc1,0xe0,0x96},3,1,0},
 {"shl_imm_32_151",{0xc1,0xe0,0x97},3,1,0},
 {"shl_imm_32_152",{0xc1,0xe0,0x98},3,1,0},
 {"shl_imm_32_153",{0xc1,0xe0,0x99},3,1,0},
 {"shl_imm_32_154",{0xc1,0xe0,0x9a},3,1,0},
 {"shl_imm_32_155",{0xc1,0xe0,0x9b},3,1,0},
 {"shl_imm_32_156",{0xc1,0xe0,0x9c},3,1,0},
 {"shl_imm_32_157",{0xc1,0xe0,0x9d},3,1,0},
 {"shl_imm_32_158",{0xc1,0xe0,0x9e},3,1,0},
 {"shl_imm_32_159",{0xc1,0xe0,0x9f},3,1,0},
 {"shl_imm_32_160",{0xc1,0xe0,0xa0},3,1,0},
 {"shl_imm_32_161",{0xc1,0xe0,0xa1},3,1,0},
 {"shl_imm_32_162",{0xc1,0xe0,0xa2},3,1,0},
 {"shl_imm_32_163",{0xc1,0xe0,0xa3},3,1,0},
 {"shl_imm_32_164",{0xc1,0xe0,0xa4},3,1,0},
 {"shl_imm_32_165",{0xc1,0xe0,0xa5},3,1,0},
 {"shl_imm_32_166",{0xc1,0xe0,0xa6},3,1,0},
 {"shl_imm_32_167",{0xc1,0xe0,0xa7},3,1,0},
 {"shl_imm_32_168",{0xc1,0xe0,0xa8},3,1,0},
 {"shl_imm_32_169",{0xc1,0xe0,0xa9},3,1,0},
 {"shl_imm_32_170",{0xc1,0xe0,0xaa},3,1,0},
 {"shl_imm_32_171",{0xc1,0xe0,0xab},3,1,0},
 {"shl_imm_32_172",{0xc1,0xe0,0xac},3,1,0},
 {"shl_imm_32_173",{0xc1,0xe0,0xad},3,1,0},
 {"shl_imm_32_174",{0xc1,0xe0,0xae},3,1,0},
 {"shl_imm_32_175",{0xc1,0xe0,0xaf},3,1,0},
 {"shl_imm_32_176",{0xc1,0xe0,0xb0},3,1,0},
 {"shl_imm_32_177",{0xc1,0xe0,0xb1},3,1,0},
 {"shl_imm_32_178",{0xc1,0xe0,0xb2},3,1,0},
 {"shl_imm_32_179",{0xc1,0xe0,0xb3},3,1,0},
 {"shl_imm_32_180",{0xc1,0xe0,0xb4},3,1,0},
 {"shl_imm_32_181",{0xc1,0xe0,0xb5},3,1,0},
 {"shl_imm_32_182",{0xc1,0xe0,0xb6},3,1,0},
 {"shl_imm_32_183",{0xc1,0xe0,0xb7},3,1,0},
 {"shl_imm_32_184",{0xc1,0xe0,0xb8},3,1,0},
 {"shl_imm_32_185",{0xc1,0xe0,0xb9},3,1,0},
 {"shl_imm_32_186",{0xc1,0xe0,0xba},3,1,0},
 {"shl_imm_32_187",{0xc1,0xe0,0xbb},3,1,0},
 {"shl_imm_32_188",{0xc1,0xe0,0xbc},3,1,0},
 {"shl_imm_32_189",{0xc1,0xe0,0xbd},3,1,0},
 {"shl_imm_32_190",{0xc1,0xe0,0xbe},3,1,0},
 {"shl_imm_32_191",{0xc1,0xe0,0xbf},3,1,0},
 {"shl_imm_32_192",{0xc1,0xe0,0xc0},3,1,0},
 {"shl_imm_32_193",{0xc1,0xe0,0xc1},3,1,0},
 {"shl_imm_32_194",{0xc1,0xe0,0xc2},3,1,0},
 {"shl_imm_32_195",{0xc1,0xe0,0xc3},3,1,0},
 {"shl_imm_32_196",{0xc1,0xe0,0xc4},3,1,0},
 {"shl_imm_32_197",{0xc1,0xe0,0xc5},3,1,0},
 {"shl_imm_32_198",{0xc1,0xe0,0xc6},3,1,0},
 {"shl_imm_32_199",{0xc1,0xe0,0xc7},3,1,0},
 {"shl_imm_32_200",{0xc1,0xe0,0xc8},3,1,0},
 {"shl_imm_32_201",{0xc1,0xe0,0xc9},3,1,0},
 {"shl_imm_32_202",{0xc1,0xe0,0xca},3,1,0},
 {"shl_imm_32_203",{0xc1,0xe0,0xcb},3,1,0},
 {"shl_imm_32_204",{0xc1,0xe0,0xcc},3,1,0},
 {"shl_imm_32_205",{0xc1,0xe0,0xcd},3,1,0},
 {"shl_imm_32_206",{0xc1,0xe0,0xce},3,1,0},
 {"shl_imm_32_207",{0xc1,0xe0,0xcf},3,1,0},
 {"shl_imm_32_208",{0xc1,0xe0,0xd0},3,1,0},
 {"shl_imm_32_209",{0xc1,0xe0,0xd1},3,1,0},
 {"shl_imm_32_210",{0xc1,0xe0,0xd2},3,1,0},
 {"shl_imm_32_211",{0xc1,0xe0,0xd3},3,1,0},
 {"shl_imm_32_212",{0xc1,0xe0,0xd4},3,1,0},
 {"shl_imm_32_213",{0xc1,0xe0,0xd5},3,1,0},
 {"shl_imm_32_214",{0xc1,0xe0,0xd6},3,1,0},
 {"shl_imm_32_215",{0xc1,0xe0,0xd7},3,1,0},
 {"shl_imm_32_216",{0xc1,0xe0,0xd8},3,1,0},
 {"shl_imm_32_217",{0xc1,0xe0,0xd9},3,1,0},
 {"shl_imm_32_218",{0xc1,0xe0,0xda},3,1,0},
 {"shl_imm_32_219",{0xc1,0xe0,0xdb},3,1,0},
 {"shl_imm_32_220",{0xc1,0xe0,0xdc},3,1,0},
 {"shl_imm_32_221",{0xc1,0xe0,0xdd},3,1,0},
 {"shl_imm_32_222",{0xc1,0xe0,0xde},3,1,0},
 {"shl_imm_32_223",{0xc1,0xe0,0xdf},3,1,0},
 {"shl_imm_32_224",{0xc1,0xe0,0xe0},3,1,0},
 {"shl_imm_32_225",{0xc1,0xe0,0xe1},3,1,0},
 {"shl_imm_32_226",{0xc1,0xe0,0xe2},3,1,0},
 {"shl_imm_32_227",{0xc1,0xe0,0xe3},3,1,0},
 {"shl_imm_32_228",{0xc1,0xe0,0xe4},3,1,0},
 {"shl_imm_32_229",{0xc1,0xe0,0xe5},3,1,0},
 {"shl_imm_32_230",{0xc1,0xe0,0xe6},3,1,0},
 {"shl_imm_32_231",{0xc1,0xe0,0xe7},3,1,0},
 {"shl_imm_32_232",{0xc1,0xe0,0xe8},3,1,0},
 {"shl_imm_32_233",{0xc1,0xe0,0xe9},3,1,0},
 {"shl_imm_32_234",{0xc1,0xe0,0xea},3,1,0},
 {"shl_imm_32_235",{0xc1,0xe0,0xeb},3,1,0},
 {"shl_imm_32_236",{0xc1,0xe0,0xec},3,1,0},
 {"shl_imm_32_237",{0xc1,0xe0,0xed},3,1,0},
 {"shl_imm_32_238",{0xc1,0xe0,0xee},3,1,0},
 {"shl_imm_32_239",{0xc1,0xe0,0xef},3,1,0},
 {"shl_imm_32_240",{0xc1,0xe0,0xf0},3,1,0},
 {"shl_imm_32_241",{0xc1,0xe0,0xf1},3,1,0},
 {"shl_imm_32_242",{0xc1,0xe0,0xf2},3,1,0},
 {"shl_imm_32_243",{0xc1,0xe0,0xf3},3,1,0},
 {"shl_imm_32_244",{0xc1,0xe0,0xf4},3,1,0},
 {"shl_imm_32_245",{0xc1,0xe0,0xf5},3,1,0},
 {"shl_imm_32_246",{0xc1,0xe0,0xf6},3,1,0},
 {"shl_imm_32_247",{0xc1,0xe0,0xf7},3,1,0},
 {"shl_imm_32_248",{0xc1,0xe0,0xf8},3,1,0},
 {"shl_imm_32_249",{0xc1,0xe0,0xf9},3,1,0},
 {"shl_imm_32_250",{0xc1,0xe0,0xfa},3,1,0},
 {"shl_imm_32_251",{0xc1,0xe0,0xfb},3,1,0},
 {"shl_imm_32_252",{0xc1,0xe0,0xfc},3,1,0},
 {"shl_imm_32_253",{0xc1,0xe0,0xfd},3,1,0},
 {"shl_imm_32_254",{0xc1,0xe0,0xfe},3,1,0},
 {"shl_imm_32_255",{0xc1,0xe0,0xff},3,1,0},
 {"shl_imm_64_0",{0x48,0xc1,0xe0,0x0},4,1,0},
 {"shl_imm_64_1",{0x48,0xc1,0xe0,0x1},4,1,0},
 {"shl_imm_64_2",{0x48,0xc1,0xe0,0x2},4,1,0},
 {"shl_imm_64_3",{0x48,0xc1,0xe0,0x3},4,1,0},
 {"shl_imm_64_4",{0x48,0xc1,0xe0,0x4},4,1,0},
 {"shl_imm_64_5",{0x48,0xc1,0xe0,0x5},4,1,0},
 {"shl_imm_64_6",{0x48,0xc1,0xe0,0x6},4,1,0},
 {"shl_imm_64_7",{0x48,0xc1,0xe0,0x7},4,1,0},
 {"shl_imm_64_8",{0x48,0xc1,0xe0,0x8},4,1,0},
 {"shl_imm_64_9",{0x48,0xc1,0xe0,0x9},4,1,0},
 {"shl_imm_64_10",{0x48,0xc1,0xe0,0xa},4,1,0},
 {"shl_imm_64_11",{0x48,0xc1,0xe0,0xb},4,1,0},
 {"shl_imm_64_12",{0x48,0xc1,0xe0,0xc},4,1,0},
 {"shl_imm_64_13",{0x48,0xc1,0xe0,0xd},4,1,0},
 {"shl_imm_64_14",{0x48,0xc1,0xe0,0xe},4,1,0},
 {"shl_imm_64_15",{0x48,0xc1,0xe0,0xf},4,1,0},
 {"shl_imm_64_16",{0x48,0xc1,0xe0,0x10},4,1,0},
 {"shl_imm_64_17",{0x48,0xc1,0xe0,0x11},4,1,0},
 {"shl_imm_64_18",{0x48,0xc1,0xe0,0x12},4,1,0},
 {"shl_imm_64_19",{0x48,0xc1,0xe0,0x13},4,1,0},
 {"shl_imm_64_20",{0x48,0xc1,0xe0,0x14},4,1,0},
 {"shl_imm_64_21",{0x48,0xc1,0xe0,0x15},4,1,0},
 {"shl_imm_64_22",{0x48,0xc1,0xe0,0x16},4,1,0},
 {"shl_imm_64_23",{0x48,0xc1,0xe0,0x17},4,1,0},
 {"shl_imm_64_24",{0x48,0xc1,0xe0,0x18},4,1,0},
 {"shl_imm_64_25",{0x48,0xc1,0xe0,0x19},4,1,0},
 {"shl_imm_64_26",{0x48,0xc1,0xe0,0x1a},4,1,0},
 {"shl_imm_64_27",{0x48,0xc1,0xe0,0x1b},4,1,0},
 {"shl_imm_64_28",{0x48,0xc1,0xe0,0x1c},4,1,0},
 {"shl_imm_64_29",{0x48,0xc1,0xe0,0x1d},4,1,0},
 {"shl_imm_64_30",{0x48,0xc1,0xe0,0x1e},4,1,0},
 {"shl_imm_64_31",{0x48,0xc1,0xe0,0x1f},4,1,0},
 {"shl_imm_64_32",{0x48,0xc1,0xe0,0x20},4,1,0},
 {"shl_imm_64_33",{0x48,0xc1,0xe0,0x21},4,1,0},
 {"shl_imm_64_34",{0x48,0xc1,0xe0,0x22},4,1,0},
 {"shl_imm_64_35",{0x48,0xc1,0xe0,0x23},4,1,0},
 {"shl_imm_64_36",{0x48,0xc1,0xe0,0x24},4,1,0},
 {"shl_imm_64_37",{0x48,0xc1,0xe0,0x25},4,1,0},
 {"shl_imm_64_38",{0x48,0xc1,0xe0,0x26},4,1,0},
 {"shl_imm_64_39",{0x48,0xc1,0xe0,0x27},4,1,0},
 {"shl_imm_64_40",{0x48,0xc1,0xe0,0x28},4,1,0},
 {"shl_imm_64_41",{0x48,0xc1,0xe0,0x29},4,1,0},
 {"shl_imm_64_42",{0x48,0xc1,0xe0,0x2a},4,1,0},
 {"shl_imm_64_43",{0x48,0xc1,0xe0,0x2b},4,1,0},
 {"shl_imm_64_44",{0x48,0xc1,0xe0,0x2c},4,1,0},
 {"shl_imm_64_45",{0x48,0xc1,0xe0,0x2d},4,1,0},
 {"shl_imm_64_46",{0x48,0xc1,0xe0,0x2e},4,1,0},
 {"shl_imm_64_47",{0x48,0xc1,0xe0,0x2f},4,1,0},
 {"shl_imm_64_48",{0x48,0xc1,0xe0,0x30},4,1,0},
 {"shl_imm_64_49",{0x48,0xc1,0xe0,0x31},4,1,0},
 {"shl_imm_64_50",{0x48,0xc1,0xe0,0x32},4,1,0},
 {"shl_imm_64_51",{0x48,0xc1,0xe0,0x33},4,1,0},
 {"shl_imm_64_52",{0x48,0xc1,0xe0,0x34},4,1,0},
 {"shl_imm_64_53",{0x48,0xc1,0xe0,0x35},4,1,0},
 {"shl_imm_64_54",{0x48,0xc1,0xe0,0x36},4,1,0},
 {"shl_imm_64_55",{0x48,0xc1,0xe0,0x37},4,1,0},
 {"shl_imm_64_56",{0x48,0xc1,0xe0,0x38},4,1,0},
 {"shl_imm_64_57",{0x48,0xc1,0xe0,0x39},4,1,0},
 {"shl_imm_64_58",{0x48,0xc1,0xe0,0x3a},4,1,0},
 {"shl_imm_64_59",{0x48,0xc1,0xe0,0x3b},4,1,0},
 {"shl_imm_64_60",{0x48,0xc1,0xe0,0x3c},4,1,0},
 {"shl_imm_64_61",{0x48,0xc1,0xe0,0x3d},4,1,0},
 {"shl_imm_64_62",{0x48,0xc1,0xe0,0x3e},4,1,0},
 {"shl_imm_64_63",{0x48,0xc1,0xe0,0x3f},4,1,0},
 {"shl_imm_64_64",{0x48,0xc1,0xe0,0x40},4,1,0},
 {"shl_imm_64_65",{0x48,0xc1,0xe0,0x41},4,1,0},
 {"shl_imm_64_66",{0x48,0xc1,0xe0,0x42},4,1,0},
 {"shl_imm_64_67",{0x48,0xc1,0xe0,0x43},4,1,0},
 {"shl_imm_64_68",{0x48,0xc1,0xe0,0x44},4,1,0},
 {"shl_imm_64_69",{0x48,0xc1,0xe0,0x45},4,1,0},
 {"shl_imm_64_70",{0x48,0xc1,0xe0,0x46},4,1,0},
 {"shl_imm_64_71",{0x48,0xc1,0xe0,0x47},4,1,0},
 {"shl_imm_64_72",{0x48,0xc1,0xe0,0x48},4,1,0},
 {"shl_imm_64_73",{0x48,0xc1,0xe0,0x49},4,1,0},
 {"shl_imm_64_74",{0x48,0xc1,0xe0,0x4a},4,1,0},
 {"shl_imm_64_75",{0x48,0xc1,0xe0,0x4b},4,1,0},
 {"shl_imm_64_76",{0x48,0xc1,0xe0,0x4c},4,1,0},
 {"shl_imm_64_77",{0x48,0xc1,0xe0,0x4d},4,1,0},
 {"shl_imm_64_78",{0x48,0xc1,0xe0,0x4e},4,1,0},
 {"shl_imm_64_79",{0x48,0xc1,0xe0,0x4f},4,1,0},
 {"shl_imm_64_80",{0x48,0xc1,0xe0,0x50},4,1,0},
 {"shl_imm_64_81",{0x48,0xc1,0xe0,0x51},4,1,0},
 {"shl_imm_64_82",{0x48,0xc1,0xe0,0x52},4,1,0},
 {"shl_imm_64_83",{0x48,0xc1,0xe0,0x53},4,1,0},
 {"shl_imm_64_84",{0x48,0xc1,0xe0,0x54},4,1,0},
 {"shl_imm_64_85",{0x48,0xc1,0xe0,0x55},4,1,0},
 {"shl_imm_64_86",{0x48,0xc1,0xe0,0x56},4,1,0},
 {"shl_imm_64_87",{0x48,0xc1,0xe0,0x57},4,1,0},
 {"shl_imm_64_88",{0x48,0xc1,0xe0,0x58},4,1,0},
 {"shl_imm_64_89",{0x48,0xc1,0xe0,0x59},4,1,0},
 {"shl_imm_64_90",{0x48,0xc1,0xe0,0x5a},4,1,0},
 {"shl_imm_64_91",{0x48,0xc1,0xe0,0x5b},4,1,0},
 {"shl_imm_64_92",{0x48,0xc1,0xe0,0x5c},4,1,0},
 {"shl_imm_64_93",{0x48,0xc1,0xe0,0x5d},4,1,0},
 {"shl_imm_64_94",{0x48,0xc1,0xe0,0x5e},4,1,0},
 {"shl_imm_64_95",{0x48,0xc1,0xe0,0x5f},4,1,0},
 {"shl_imm_64_96",{0x48,0xc1,0xe0,0x60},4,1,0},
 {"shl_imm_64_97",{0x48,0xc1,0xe0,0x61},4,1,0},
 {"shl_imm_64_98",{0x48,0xc1,0xe0,0x62},4,1,0},
 {"shl_imm_64_99",{0x48,0xc1,0xe0,0x63},4,1,0},
 {"shl_imm_64_100",{0x48,0xc1,0xe0,0x64},4,1,0},
 {"shl_imm_64_101",{0x48,0xc1,0xe0,0x65},4,1,0},
 {"shl_imm_64_102",{0x48,0xc1,0xe0,0x66},4,1,0},
 {"shl_imm_64_103",{0x48,0xc1,0xe0,0x67},4,1,0},
 {"shl_imm_64_104",{0x48,0xc1,0xe0,0x68},4,1,0},
 {"shl_imm_64_105",{0x48,0xc1,0xe0,0x69},4,1,0},
 {"shl_imm_64_106",{0x48,0xc1,0xe0,0x6a},4,1,0},
 {"shl_imm_64_107",{0x48,0xc1,0xe0,0x6b},4,1,0},
 {"shl_imm_64_108",{0x48,0xc1,0xe0,0x6c},4,1,0},
 {"shl_imm_64_109",{0x48,0xc1,0xe0,0x6d},4,1,0},
 {"shl_imm_64_110",{0x48,0xc1,0xe0,0x6e},4,1,0},
 {"shl_imm_64_111",{0x48,0xc1,0xe0,0x6f},4,1,0},
 {"shl_imm_64_112",{0x48,0xc1,0xe0,0x70},4,1,0},
 {"shl_imm_64_113",{0x48,0xc1,0xe0,0x71},4,1,0},
 {"shl_imm_64_114",{0x48,0xc1,0xe0,0x72},4,1,0},
 {"shl_imm_64_115",{0x48,0xc1,0xe0,0x73},4,1,0},
 {"shl_imm_64_116",{0x48,0xc1,0xe0,0x74},4,1,0},
 {"shl_imm_64_117",{0x48,0xc1,0xe0,0x75},4,1,0},
 {"shl_imm_64_118",{0x48,0xc1,0xe0,0x76},4,1,0},
 {"shl_imm_64_119",{0x48,0xc1,0xe0,0x77},4,1,0},
 {"shl_imm_64_120",{0x48,0xc1,0xe0,0x78},4,1,0},
 {"shl_imm_64_121",{0x48,0xc1,0xe0,0x79},4,1,0},
 {"shl_imm_64_122",{0x48,0xc1,0xe0,0x7a},4,1,0},
 {"shl_imm_64_123",{0x48,0xc1,0xe0,0x7b},4,1,0},
 {"shl_imm_64_124",{0x48,0xc1,0xe0,0x7c},4,1,0},
 {"shl_imm_64_125",{0x48,0xc1,0xe0,0x7d},4,1,0},
 {"shl_imm_64_126",{0x48,0xc1,0xe0,0x7e},4,1,0},
 {"shl_imm_64_127",{0x48,0xc1,0xe0,0x7f},4,1,0},
 {"shl_imm_64_128",{0x48,0xc1,0xe0,0x80},4,1,0},
 {"shl_imm_64_129",{0x48,0xc1,0xe0,0x81},4,1,0},
 {"shl_imm_64_130",{0x48,0xc1,0xe0,0x82},4,1,0},
 {"shl_imm_64_131",{0x48,0xc1,0xe0,0x83},4,1,0},
 {"shl_imm_64_132",{0x48,0xc1,0xe0,0x84},4,1,0},
 {"shl_imm_64_133",{0x48,0xc1,0xe0,0x85},4,1,0},
 {"shl_imm_64_134",{0x48,0xc1,0xe0,0x86},4,1,0},
 {"shl_imm_64_135",{0x48,0xc1,0xe0,0x87},4,1,0},
 {"shl_imm_64_136",{0x48,0xc1,0xe0,0x88},4,1,0},
 {"shl_imm_64_137",{0x48,0xc1,0xe0,0x89},4,1,0},
 {"shl_imm_64_138",{0x48,0xc1,0xe0,0x8a},4,1,0},
 {"shl_imm_64_139",{0x48,0xc1,0xe0,0x8b},4,1,0},
 {"shl_imm_64_140",{0x48,0xc1,0xe0,0x8c},4,1,0},
 {"shl_imm_64_141",{0x48,0xc1,0xe0,0x8d},4,1,0},
 {"shl_imm_64_142",{0x48,0xc1,0xe0,0x8e},4,1,0},
 {"shl_imm_64_143",{0x48,0xc1,0xe0,0x8f},4,1,0},
 {"shl_imm_64_144",{0x48,0xc1,0xe0,0x90},4,1,0},
 {"shl_imm_64_145",{0x48,0xc1,0xe0,0x91},4,1,0},
 {"shl_imm_64_146",{0x48,0xc1,0xe0,0x92},4,1,0},
 {"shl_imm_64_147",{0x48,0xc1,0xe0,0x93},4,1,0},
 {"shl_imm_64_148",{0x48,0xc1,0xe0,0x94},4,1,0},
 {"shl_imm_64_149",{0x48,0xc1,0xe0,0x95},4,1,0},
 {"shl_imm_64_150",{0x48,0xc1,0xe0,0x96},4,1,0},
 {"shl_imm_64_151",{0x48,0xc1,0xe0,0x97},4,1,0},
 {"shl_imm_64_152",{0x48,0xc1,0xe0,0x98},4,1,0},
 {"shl_imm_64_153",{0x48,0xc1,0xe0,0x99},4,1,0},
 {"shl_imm_64_154",{0x48,0xc1,0xe0,0x9a},4,1,0},
 {"shl_imm_64_155",{0x48,0xc1,0xe0,0x9b},4,1,0},
 {"shl_imm_64_156",{0x48,0xc1,0xe0,0x9c},4,1,0},
 {"shl_imm_64_157",{0x48,0xc1,0xe0,0x9d},4,1,0},
 {"shl_imm_64_158",{0x48,0xc1,0xe0,0x9e},4,1,0},
 {"shl_imm_64_159",{0x48,0xc1,0xe0,0x9f},4,1,0},
 {"shl_imm_64_160",{0x48,0xc1,0xe0,0xa0},4,1,0},
 {"shl_imm_64_161",{0x48,0xc1,0xe0,0xa1},4,1,0},
 {"shl_imm_64_162",{0x48,0xc1,0xe0,0xa2},4,1,0},
 {"shl_imm_64_163",{0x48,0xc1,0xe0,0xa3},4,1,0},
 {"shl_imm_64_164",{0x48,0xc1,0xe0,0xa4},4,1,0},
 {"shl_imm_64_165",{0x48,0xc1,0xe0,0xa5},4,1,0},
 {"shl_imm_64_166",{0x48,0xc1,0xe0,0xa6},4,1,0},
 {"shl_imm_64_167",{0x48,0xc1,0xe0,0xa7},4,1,0},
 {"shl_imm_64_168",{0x48,0xc1,0xe0,0xa8},4,1,0},
 {"shl_imm_64_169",{0x48,0xc1,0xe0,0xa9},4,1,0},
 {"shl_imm_64_170",{0x48,0xc1,0xe0,0xaa},4,1,0},
 {"shl_imm_64_171",{0x48,0xc1,0xe0,0xab},4,1,0},
 {"shl_imm_64_172",{0x48,0xc1,0xe0,0xac},4,1,0},
 {"shl_imm_64_173",{0x48,0xc1,0xe0,0xad},4,1,0},
 {"shl_imm_64_174",{0x48,0xc1,0xe0,0xae},4,1,0},
 {"shl_imm_64_175",{0x48,0xc1,0xe0,0xaf},4,1,0},
 {"shl_imm_64_176",{0x48,0xc1,0xe0,0xb0},4,1,0},
 {"shl_imm_64_177",{0x48,0xc1,0xe0,0xb1},4,1,0},
 {"shl_imm_64_178",{0x48,0xc1,0xe0,0xb2},4,1,0},
 {"shl_imm_64_179",{0x48,0xc1,0xe0,0xb3},4,1,0},
 {"shl_imm_64_180",{0x48,0xc1,0xe0,0xb4},4,1,0},
 {"shl_imm_64_181",{0x48,0xc1,0xe0,0xb5},4,1,0},
 {"shl_imm_64_182",{0x48,0xc1,0xe0,0xb6},4,1,0},
 {"shl_imm_64_183",{0x48,0xc1,0xe0,0xb7},4,1,0},
 {"shl_imm_64_184",{0x48,0xc1,0xe0,0xb8},4,1,0},
 {"shl_imm_64_185",{0x48,0xc1,0xe0,0xb9},4,1,0},
 {"shl_imm_64_186",{0x48,0xc1,0xe0,0xba},4,1,0},
 {"shl_imm_64_187",{0x48,0xc1,0xe0,0xbb},4,1,0},
 {"shl_imm_64_188",{0x48,0xc1,0xe0,0xbc},4,1,0},
 {"shl_imm_64_189",{0x48,0xc1,0xe0,0xbd},4,1,0},
 {"shl_imm_64_190",{0x48,0xc1,0xe0,0xbe},4,1,0},
 {"shl_imm_64_191",{0x48,0xc1,0xe0,0xbf},4,1,0},
 {"shl_imm_64_192",{0x48,0xc1,0xe0,0xc0},4,1,0},
 {"shl_imm_64_193",{0x48,0xc1,0xe0,0xc1},4,1,0},
 {"shl_imm_64_194",{0x48,0xc1,0xe0,0xc2},4,1,0},
 {"shl_imm_64_195",{0x48,0xc1,0xe0,0xc3},4,1,0},
 {"shl_imm_64_196",{0x48,0xc1,0xe0,0xc4},4,1,0},
 {"shl_imm_64_197",{0x48,0xc1,0xe0,0xc5},4,1,0},
 {"shl_imm_64_198",{0x48,0xc1,0xe0,0xc6},4,1,0},
 {"shl_imm_64_199",{0x48,0xc1,0xe0,0xc7},4,1,0},
 {"shl_imm_64_200",{0x48,0xc1,0xe0,0xc8},4,1,0},
 {"shl_imm_64_201",{0x48,0xc1,0xe0,0xc9},4,1,0},
 {"shl_imm_64_202",{0x48,0xc1,0xe0,0xca},4,1,0},
 {"shl_imm_64_203",{0x48,0xc1,0xe0,0xcb},4,1,0},
 {"shl_imm_64_204",{0x48,0xc1,0xe0,0xcc},4,1,0},
 {"shl_imm_64_205",{0x48,0xc1,0xe0,0xcd},4,1,0},
 {"shl_imm_64_206",{0x48,0xc1,0xe0,0xce},4,1,0},
 {"shl_imm_64_207",{0x48,0xc1,0xe0,0xcf},4,1,0},
 {"shl_imm_64_208",{0x48,0xc1,0xe0,0xd0},4,1,0},
 {"shl_imm_64_209",{0x48,0xc1,0xe0,0xd1},4,1,0},
 {"shl_imm_64_210",{0x48,0xc1,0xe0,0xd2},4,1,0},
 {"shl_imm_64_211",{0x48,0xc1,0xe0,0xd3},4,1,0},
 {"shl_imm_64_212",{0x48,0xc1,0xe0,0xd4},4,1,0},
 {"shl_imm_64_213",{0x48,0xc1,0xe0,0xd5},4,1,0},
 {"shl_imm_64_214",{0x48,0xc1,0xe0,0xd6},4,1,0},
 {"shl_imm_64_215",{0x48,0xc1,0xe0,0xd7},4,1,0},
 {"shl_imm_64_216",{0x48,0xc1,0xe0,0xd8},4,1,0},
 {"shl_imm_64_217",{0x48,0xc1,0xe0,0xd9},4,1,0},
 {"shl_imm_64_218",{0x48,0xc1,0xe0,0xda},4,1,0},
 {"shl_imm_64_219",{0x48,0xc1,0xe0,0xdb},4,1,0},
 {"shl_imm_64_220",{0x48,0xc1,0xe0,0xdc},4,1,0},
 {"shl_imm_64_221",{0x48,0xc1,0xe0,0xdd},4,1,0},
 {"shl_imm_64_222",{0x48,0xc1,0xe0,0xde},4,1,0},
 {"shl_imm_64_223",{0x48,0xc1,0xe0,0xdf},4,1,0},
 {"shl_imm_64_224",{0x48,0xc1,0xe0,0xe0},4,1,0},
 {"shl_imm_64_225",{0x48,0xc1,0xe0,0xe1},4,1,0},
 {"shl_imm_64_226",{0x48,0xc1,0xe0,0xe2},4,1,0},
 {"shl_imm_64_227",{0x48,0xc1,0xe0,0xe3},4,1,0},
 {"shl_imm_64_228",{0x48,0xc1,0xe0,0xe4},4,1,0},
 {"shl_imm_64_229",{0x48,0xc1,0xe0,0xe5},4,1,0},
 {"shl_imm_64_230",{0x48,0xc1,0xe0,0xe6},4,1,0},
 {"shl_imm_64_231",{0x48,0xc1,0xe0,0xe7},4,1,0},
 {"shl_imm_64_232",{0x48,0xc1,0xe0,0xe8},4,1,0},
 {"shl_imm_64_233",{0x48,0xc1,0xe0,0xe9},4,1,0},
 {"shl_imm_64_234",{0x48,0xc1,0xe0,0xea},4,1,0},
 {"shl_imm_64_235",{0x48,0xc1,0xe0,0xeb},4,1,0},
 {"shl_imm_64_236",{0x48,0xc1,0xe0,0xec},4,1,0},
 {"shl_imm_64_237",{0x48,0xc1,0xe0,0xed},4,1,0},
 {"shl_imm_64_238",{0x48,0xc1,0xe0,0xee},4,1,0},
 {"shl_imm_64_239",{0x48,0xc1,0xe0,0xef},4,1,0},
 {"shl_imm_64_240",{0x48,0xc1,0xe0,0xf0},4,1,0},
 {"shl_imm_64_241",{0x48,0xc1,0xe0,0xf1},4,1,0},
 {"shl_imm_64_242",{0x48,0xc1,0xe0,0xf2},4,1,0},
 {"shl_imm_64_243",{0x48,0xc1,0xe0,0xf3},4,1,0},
 {"shl_imm_64_244",{0x48,0xc1,0xe0,0xf4},4,1,0},
 {"shl_imm_64_245",{0x48,0xc1,0xe0,0xf5},4,1,0},
 {"shl_imm_64_246",{0x48,0xc1,0xe0,0xf6},4,1,0},
 {"shl_imm_64_247",{0x48,0xc1,0xe0,0xf7},4,1,0},
 {"shl_imm_64_248",{0x48,0xc1,0xe0,0xf8},4,1,0},
 {"shl_imm_64_249",{0x48,0xc1,0xe0,0xf9},4,1,0},
 {"shl_imm_64_250",{0x48,0xc1,0xe0,0xfa},4,1,0},
 {"shl_imm_64_251",{0x48,0xc1,0xe0,0xfb},4,1,0},
 {"shl_imm_64_252",{0x48,0xc1,0xe0,0xfc},4,1,0},
 {"shl_imm_64_253",{0x48,0xc1,0xe0,0xfd},4,1,0},
 {"shl_imm_64_254",{0x48,0xc1,0xe0,0xfe},4,1,0},
 {"shl_imm_64_255",{0x48,0xc1,0xe0,0xff},4,1,0}
};
static uint64_t register_random(uint64_t *v){*v^=*v<<13;*v^=*v>>7;*v^=*v<<17;return *v;}
static void register_compare(unsigned id,unsigned iteration){
 register_state native={0},trap;uint64_t seed=0xbad5eedfeedbabeULL+iteration*37;
 for(unsigned i=0;i<10;i++)((uint64_t*)&native)[i]=register_random(&seed);
 static const uint64_t edge[]={0,1,2,0x7fffffff,0x80000000,0xffffffff,0x100000000ULL,0x7fffffffffffffffULL,0x8000000000000000ULL,0xffffffffffffffffULL,0x5555555555555555ULL,0xaaaaaaaaaaaaaaaaULL};
 static const unsigned counts[]={0,1,2,7,8,15,16,31,32,33,63,64,65,127,128,255};
 if(iteration%256<144){native.q[0]=native.q[2]=edge[(iteration%144)/12];native.q[1]=native.q[3]=edge[iteration%12];}
 if(id>=58)native.q[0]=native.q[2]=edge[iteration%12];
 unsigned bits=iteration&63;native.flags=0x202|((bits&1)?1:0)|((bits&2)?4:0)|((bits&4)?0x10:0)|((bits&8)?0x40:0)|((bits&16)?0x80:0)|((bits&32)?0x800:0);
 native.count=counts[iteration%16];
 if(strstr(register_cases[id].name,"shl") && strstr(register_cases[id].name,"cl_full"))native.count=(iteration/64)&255;
 trap=native;
 register_native_run(&native);register_trap_run(&trap);
 if(register_cases[id].stack_source)native.q[0]=register_seen_rsp;
 if(memcmp(&native,&trap,sizeof native)){
  LONG n=InterlockedIncrement(&failures);if(n<6){printf("REGISTER_MISMATCH case=%s iteration=%u\n",register_cases[id].name,iteration);for(unsigned i=0;i<12;i++)if(((uint64_t*)&native)[i]!=((uint64_t*)&trap)[i])printf(" field=%u native=%llx trap=%llx\n",i,(unsigned long long)((uint64_t*)&native)[i],(unsigned long long)((uint64_t*)&trap)[i]);}
 }
}
static void register_prepare(unsigned id){
 DWORD old;VirtualProtect(register_native_code,4096,PAGE_READWRITE,&old);VirtualProtect(register_trap_code,4096,PAGE_READWRITE,&old);
 unsigned n=register_cases[id].n;memcpy(register_native_code,register_cases[id].bytes,n);register_native_code[n]=0xc3;
 memcpy(register_trap_code,register_cases[id].bytes,n);register_trap_code[n]=0xe9;
 int64_t delta=(intptr_t)(register_trap_second+register_resume)-((intptr_t)register_trap_code+n+5);if(delta<INT32_MIN||delta>INT32_MAX)ExitProcess(11);
 int32_t rel=(int32_t)delta;memcpy(register_trap_code+n+1,&rel,4);
 VirtualProtect(register_native_code,4096,PAGE_EXECUTE_READ,&old);VirtualProtect(register_trap_code,4096,PAGE_EXECUTE_READ,&old);
 FlushInstructionCache(GetCurrentProcess(),register_native_code,4096);FlushInstructionCache(GetCurrentProcess(),register_trap_code,4096);
}
static DWORD WINAPI register_concurrent(void *arg){unsigned id=(unsigned)(uintptr_t)arg;for(unsigned i=0;i<256;i++)register_compare(id,i+900);return 0;}
static void test_register_bridges(int enabled){
 LONG64 *trace=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_bridge_refusal_control");
 LONG64 *window=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_exception_burst_control");
 struct RefusalRecord *records=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_bridge_refusal_records");
 if(!trace||!window||!records||sizeof(*records)!=80)ExitProcess(20);
 int recording=enabled && trace[0];
 if(recording)InterlockedExchange64(window,1);

 uintptr_t image=(uintptr_t)GetModuleHandleA(NULL);
 for(unsigned i=1;i<32 && (!register_native_code || !register_trap_code);i++){
  unsigned char *mem=VirtualAlloc((void*)(image+i*0x1000000),4096,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
  if(mem){if(!register_native_code)register_native_code=mem;else register_trap_code=mem;}
 }
 if(!register_native_code || !register_trap_code)ExitProcess(12);
 PVOID h=AddVectoredExceptionHandler(0,register_handler);unsigned total=sizeof register_cases/sizeof register_cases[0];
 for(unsigned phase=0;phase<2;phase++){
  register_resume=phase;LONG64 before=stats[4],resumed=stats[5];LONG real_before=handler_calls;unsigned expected=0,comparisons=0;
  for(unsigned id=0;id<total;id++){
   register_prepare(id);LONG64 accepted=stats[4],trace_before=trace[1];unsigned iterations=id<58?256:16;
   if(strstr(register_cases[id].name,"shl") && strstr(register_cases[id].name,"cl_full"))iterations=16384;
   else if(strstr(register_cases[id].name,"shl") && strstr(register_cases[id].name,"cl_"))iterations=256;comparisons+=iterations;for(unsigned i=0;i<iterations;i++)register_compare(id,i+phase*4096);
   if(recording){
    unsigned supported=register_cases[id].accepted&&(new_alu_enabled || (id<20 && id!=17));
    unsigned outcome=supported?(phase?(expect_resume?2:16):1):9;
    if(trace[1]-trace_before!=iterations){printf("REFUSAL_COUNT case=%s got=%lld want=%u\n",register_cases[id].name,trace[1]-trace_before,iterations);InterlockedIncrement(&failures);}
    for(LONG64 j=trace_before;j<trace[1]&&j<262144;j++){
     struct RefusalRecord *v=records+j;
     if(v->ready!=1||v->outcome!=outcome||!(v->valid&1)||memcmp(v->code,register_trap_code,16)||v->rip!=(uintptr_t)register_trap_code||v->begin>v->end||!v->tid){
      LONG n=InterlockedIncrement(&failures);if(n<6)printf("REFUSAL_CLASS case=%s phase=%u outcome=%lu want=%u valid=%lu\n",register_cases[id].name,phase,v->outcome,outcome,v->valid);
     }
    }
   }else if(trace[1]!=trace_before)InterlockedIncrement(&failures);
   unsigned want=enabled&&count_enabled&&register_cases[id].accepted&&(new_alu_enabled || (id<20 && id!=17))&&(!phase||expect_resume)?iterations:0;expected+=want;
   if(stats[4]-accepted!=want){printf("ACCEPT_MISMATCH %s phase=%u got=%lld want=%u\n",register_cases[id].name,phase,stats[4]-accepted,want);InterlockedIncrement(&failures);}
  }
  unsigned id=0;while(id<total&&strcmp(register_cases[id].name,"shl64_cl_high"))id++;
  register_prepare(id);HANDLE threads[4];for(unsigned i=0;i<4;i++)threads[i]=CreateThread(NULL,0,register_concurrent,(void*)(uintptr_t)id,0,NULL);
  WaitForMultipleObjects(4,threads,TRUE,INFINITE);for(unsigned i=0;i<4;i++)CloseHandle(threads[i]);
  if(enabled&&count_enabled&&new_alu_enabled&&(!phase||expect_resume))expected+=1024;
  comparisons+=1024;
  if(stats[4]-before!=expected || handler_calls-real_before!=(LONG)(comparisons*(phase?1:2)) || (phase && stats[5]-resumed!=expected))InterlockedIncrement(&failures);
  printf("REGISTER_PHASE phase=%u cases=%u comparisons=%u accepted=%lld expected=%u real_handlers=%ld failures=%ld\n",phase,total,comparisons,stats[4]-before,expected,handler_calls-real_before,failures);
 }
 register_resume=0;
 if(recording){
  for(LONG64 i=0;i<trace[1]&&i<262144;i++){struct RefusalRecord *v=records+i;if(v->ready!=1||v->begin>v->end||v->outcome<1||v->outcome>20||!v->tid)InterlockedIncrement(&failures);}
  if(trace[2]||trace[3])InterlockedIncrement(&failures);
  register_prepare(0);LONG64 old_count=trace[1],old_drop=trace[2];
  InterlockedExchange64(window,0);register_compare(0,0);if(trace[1]!=old_count)InterlockedIncrement(&failures);
  InterlockedExchange64(window,1);InterlockedExchange64(trace,0);register_compare(0,1);if(trace[1]!=old_count)InterlockedIncrement(&failures);
  InterlockedExchange64(trace,1);InterlockedExchange64(trace+1,262143);register_compare(0,2);register_compare(0,3);
  if(trace[1]!=262145||trace[2]!=old_drop+1||trace[3]||records[262143].ready!=1||records[262143].outcome!=1)InterlockedIncrement(&failures);
  InterlockedExchange64(trace+1,old_count);InterlockedExchange64(trace+2,old_drop);
  InterlockedExchange64(window,0);
 }
 printf("REFUSAL_TRACE active=%d records=%lld dropped=%lld outstanding=%lld off_window_and_overflow=checked failures=%ld\n",recording,trace[1],trace[2],trace[3],failures);
 RemoveVectoredExceptionHandler(h);VirtualFree(register_native_code,0,MEM_RELEASE);VirtualFree(register_trap_code,0,MEM_RELEASE);
}
static LONG CALLBACK first_handler(EXCEPTION_POINTERS *ep){
 if(ep->ExceptionRecord->ExceptionCode==EXCEPTION_ILLEGAL_INSTRUCTION)InterlockedIncrement(&first_handler_calls);
 return EXCEPTION_CONTINUE_SEARCH;
}
static LONG CALLBACK handler(EXCEPTION_POINTERS *ep){
 CONTEXT *c=ep->ContextRecord;unsigned char *pc=(void*)c->Rip;unsigned length=1;
 if(ep->ExceptionRecord->ExceptionCode!=EXCEPTION_ILLEGAL_INSTRUCTION)return EXCEPTION_CONTINUE_SEARCH;
 if(pc==ud2_first||pc==ud2_second)length=2;
 else if(!((pc>=chain_begin&&pc<chain_end)||pc==boundary_first||pc==boundary_second))return EXCEPTION_CONTINUE_SEARCH;
 if(ep->ExceptionRecord->ExceptionAddress!=pc||ep->ExceptionRecord->ExceptionFlags||ep->ExceptionRecord->NumberParameters)InterlockedIncrement(&failures);
 if(length==1&&*pc!=0x06)InterlockedIncrement(&failures);
 if(request_nested&&!nesting&&pc==chain_begin){nesting++;if(boundary_run()!=17)InterlockedIncrement(&failures);nesting--;}
 if(omit_fp_group)c->ContextFlags &= ~((DWORD)CONTEXT_FLOATING_POINT & 0xffff);
 c->Rax+=7;c->Rip+=length;InterlockedIncrement(&handler_calls);return EXCEPTION_CONTINUE_EXECUTION;
}
static DWORD WINAPI concurrent(void *unused){(void)unused;for(unsigned i=0;i<100;i++)if(chain_run()!=910)InterlockedIncrement(&failures);return 0;}
int main(int argc,char **argv){
 char alu_env[8];if(GetEnvironmentVariableA("WINE_SOFTWARE_ALU_BRIDGE",alu_env,sizeof alu_env)==1 && alu_env[0]=='0')new_alu_enabled=0;
 LONG64 *timing_control=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_exception_burst_control");
 struct TimingRecord {LONG64 begin,end,handler,policy;ULONG64 rip_begin,rip_end;ULONG tid,links,reason;LONG ready;};
 struct TimingRecord *timing_records=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_exception_burst_records");
 if(!timing_control||!timing_records||sizeof(*timing_records)!=64)return 15;
 InterlockedExchange64(timing_control,1);
 typedef BOOL (WINAPI *ValidContext)(DWORD);
 ValidContext valid=(ValidContext)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_software_exception_chain_context_valid");
 if(!valid)return 14;
 for(unsigned bits=0;bits<32;bits++)if(!!valid(CONTEXT_AMD64|bits)!=(bits==31))InterlockedIncrement(&failures);
 if(valid(0)||valid(0x10000|31)||!valid(CONTEXT_ALL|0x08000000))InterlockedIncrement(&failures);
 printf("CONTEXT_GROUP_CONTRACT cases=35 failures=%ld\n",failures);
 int expect_enabled=argc>1&&!strncmp(argv[1],"enabled",7); int no_detail=argc>1&&(!strcmp(argv[1],"enabled-clean")||!strcmp(argv[1],"enabled-quiet")||!strcmp(argv[1],"enabled-noresume")); expect_resume=expect_enabled&&strcmp(argv[1],"enabled-noresume"); count_enabled=!(argc>1&&!strcmp(argv[1],"enabled-quiet"));setvbuf(stdout,NULL,_IONBF,0);
 stats=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_software_exception_chain_stats");if(!stats){puts("MISSING_EXPERIMENTAL_DISPATCHER");return 2;}
 PVOID h=AddVectoredExceptionHandler(0,handler),first=AddVectoredExceptionHandler(1,first_handler);if(!h||!first)return 3;
 if(GetEnvironmentVariableA("DESTINATION_ONLY",NULL,0)){
  test_destination_classification(expect_enabled);RemoveVectoredExceptionHandler(first);RemoveVectoredExceptionHandler(h);
  printf("SUMMARY destination_only=1 failures=%ld\n",failures);return failures?5:0;
 }
 LONG64 initial=stats[1];LARGE_INTEGER freq,a,b;QueryPerformanceFrequency(&freq);QueryPerformanceCounter(&a);
 for(unsigned i=0;i<1000;i++)if(chain_run()!=910)InterlockedIncrement(&failures);
 QueryPerformanceCounter(&b);LONG64 sequential=stats[1]-initial;
 printf("SEQUENTIAL links=%lld expected=%d us_per_130_traps=%.6f failures=%ld\n",sequential,expect_enabled&&count_enabled?128000:0,(double)(b.QuadPart-a.QuadPart)*1e6/freq.QuadPart/1000,failures);
 if(sequential!=(expect_enabled&&count_enabled?128000:0))InterlockedIncrement(&failures);
 initial=stats[1];if(boundary_run()!=17||ud2_run()!=14)InterlockedIncrement(&failures);if(stats[1]!=initial)InterlockedIncrement(&failures);
 printf("FALLBACKS boundary_and_ud2_links=%lld failures=%ld\n",stats[1]-initial,failures);
 initial=stats[1];omit_fp_group=1;
 if(chain_run()!=910 || stats[1]!=initial)InterlockedIncrement(&failures);
 omit_fp_group=0;
 printf("INCOMPLETE_CONTEXT real_traps=130 synthetic_links=%lld failures=%ld\n",stats[1]-initial,failures);
 request_nested=1;if(chain_run()!=910)InterlockedIncrement(&failures);request_nested=0;
 QueryPerformanceCounter(&a);
 HANDLE threads[4];for(unsigned i=0;i<4;i++){threads[i]=CreateThread(NULL,0,concurrent,NULL,0,NULL);if(!threads[i])return 4;}
 WaitForMultipleObjects(4,threads,TRUE,INFINITE);for(unsigned i=0;i<4;i++)CloseHandle(threads[i]);
 QueryPerformanceCounter(&b);printf("CONCURRENT threads=4 chains=400 elapsed_ms=%.6f failures=%ld\n",(double)(b.QuadPart-a.QuadPart)*1e3/freq.QuadPart,failures);
 for(unsigned char *p=chain_begin;p<chain_end;p++)if(*p!=0x06)InterlockedIncrement(&failures);
 test_load_bridge(expect_enabled);
 test_register_bridges(expect_enabled);
 test_resume_fault(expect_enabled);
 test_destination_classification(expect_enabled);
 LONG64 (*census)[512][8]=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_software_exception_bridge_census");
 if(!census)return 10;
 LONG64 ct=0,ca=0,ce=0;
 for(unsigned i=0;i<64;i++)for(unsigned k=0;k<512;k++){LONG64 *e=census[i][k];ct+=e[0];ca+=e[1];ce+=e[1]+e[2]+e[3]+e[4];}
 if(no_detail ? (ct || ca || ce) : (ca!=stats[4] || ct!=ce))InterlockedIncrement(&failures);
 printf("CENSUS attempts=%lld accepted=%lld outcomes=%lld failures=%ld\n",ct,ca,ce,failures);
 LONG64 (*diag)[101]=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_software_exception_chain_diagnostics");
 if(!diag)return 6;
 LONG64 dh=0,dl=0,dc=0,exits=0;
 for(unsigned row=0;row<64;row++)if(diag[row][0]){dh+=diag[row][1];dl+=diag[row][6];dc+=diag[row][11];for(unsigned reason=2;reason<20;reason++)exits+=diag[row][1+reason*5];}
 if(no_detail ? (dh || dl || dc || exits) : (dh!=stats[0] || dl!=stats[1] || dc!=stats[2] || exits!=dh))InterlockedIncrement(&failures);
 printf("DIAGNOSTICS hardware=%lld links=%lld exits=%lld failures=%ld\n",dh,dl,exits,failures);
 LONG *configuration=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_software_exception_chain_configuration");
 if(!configuration || configuration[0]!=(expect_enabled?(no_detail?3:1):0) || configuration[1]!=count_enabled || configuration[2]!=expect_resume)InterlockedIncrement(&failures);
 if(!count_enabled)for(unsigned i=0;i<6;i++)if(stats[i])InterlockedIncrement(&failures);
 if(expect_enabled && configuration[3]!=new_alu_enabled)InterlockedIncrement(&failures);
 printf("CONFIGURATION mode=%ld counters=%ld resume=%ld alu=%ld failures=%ld\n",configuration?configuration[0]:-9,configuration?configuration[1]:-9,configuration?configuration[2]:-9,configuration?configuration[3]:-9,failures);
 RemoveVectoredExceptionHandler(first);RemoveVectoredExceptionHandler(h);
 if(first_handler_calls!=handler_calls)InterlockedIncrement(&failures);
 if(expect_enabled && (!timing_control[6] || timing_control[7]<=timing_control[6] || timing_control[0]))InterlockedIncrement(&failures);
 InterlockedExchange64(timing_control,0);
 if(timing_control[2] || timing_control[3] || timing_control[1]>262144 || (!!timing_control[1])!=expect_enabled)InterlockedIncrement(&failures);
 for(LONG64 i=0;i<timing_control[1]&&i<262144;i++) {
  struct TimingRecord *t=&timing_records[i];
  if(t->ready!=1||t->begin>t->end||t->handler<0||t->policy<0||t->handler+t->policy>t->end-t->begin||!t->tid)InterlockedIncrement(&failures);
 }
 printf("TIMING records=%lld dropped=%lld active=%lld failures=%ld\n",timing_control[1],timing_control[2],timing_control[3],failures);
 {
  char path[2048];DWORD len=GetEnvironmentVariableA("REFUSAL_PROBE_DUMP_PATH",path,sizeof path);
  if(len && len<sizeof path){
   LONG64 *control=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_bridge_refusal_control");
   struct RefusalRecord *records=(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"),"__wine_bridge_refusal_records");
   struct {uint64_t magic,version,size,count;LONG64 control[8];} head={0x4648365245465553ULL,1,80,0,{0}};
   head.count=control[1];memcpy(head.control,control,sizeof(head.control));FILE *file=fopen(path,"wb");
   if(!file||sizeof(head)!=96||fwrite(&head,sizeof(head),1,file)!=1||fwrite(records,sizeof(*records),head.count,file)!=head.count)InterlockedIncrement(&failures);
   if(file&&fclose(file))InterlockedIncrement(&failures);
  }
 }
 printf("SUMMARY handler_calls=%ld first_handler_calls=%ld links=%lld cap_exits=%lld failures=%ld\n",handler_calls,first_handler_calls,stats[1],stats[2],failures);
 return failures?5:0;
}
