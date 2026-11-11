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
    switch(next){case 0x06:case 0x07:case 0x0e:case 0x16:case 0x17:case 0x1e:case 0x1f:
      case 0x27:case 0x2f:case 0x37:case 0x3f:case 0x60:case 0x61:case 0xce:case 0xea:break;default:next_is_ud=FALSE;break;}
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
