/* Staged register-only extensions. No guest memory access or context mutation.
 * A single canonical REX and default 64-bit address size are supported; other
 * prefixes and stack destinations retain ordinary execution. */
static BOOL software_bridge_extra(const BYTE *code, CONTEXT *c, struct software_bridge_effect *e)
{
    unsigned int p=0,rex=0,op,m,mod,reg,rm,dst,width,shift=0,srcshift=0;
    ULONG64 value=0,left,right=0,seed,observed;
    LONG disp32; signed char disp8;
    memset(e,0,sizeof(*e));
    if(code[p]>=0x40 && code[p]<=0x4f)rex=code[p++];
    op=code[p++];
    if(op!=0x8d && op!=0xff && op!=0x30 && op!=0x32 && op!=0x84)return FALSE;
    m=code[p++];mod=m>>6;reg=((m>>3)&7)+((rex&4)?8:0);rm=(m&7)+((rex&1)?8:0);
    if(op==0x8d)
    {
        BOOL rip_relative=FALSE;
        if(mod==3 || reg==4)return FALSE;
        if((m&7)==4)
        {
            unsigned int sib=code[p++],base=(sib&7)+((rex&1)?8:0);
            unsigned int index=((sib>>3)&7)+((rex&2)?8:0);
            if(index!=4)value=*software_bridge_gpr(c,index) << (sib>>6);
            if(mod==0 && (sib&7)==5)
            {memcpy(&disp32,code+p,4);p+=4;value+=(LONG64)disp32;}
            else value+=*software_bridge_gpr(c,base);
        }
        else if(mod==0 && (m&7)==5)
        {memcpy(&disp32,code+p,4);p+=4;value=(LONG64)disp32;rip_relative=TRUE;}
        else value=*software_bridge_gpr(c,rm);
        if(mod==1){memcpy(&disp8,code+p,1);p++;value+=(LONG64)disp8;}
        else if(mod==2){memcpy(&disp32,code+p,4);p+=4;value+=(LONG64)disp32;}
        if(rip_relative)value+=c->Rip+p;
        e->length=p;e->dst=reg;e->value[0]=(rex&8)?value:(ULONG)value;
        return TRUE;
    }
    if(mod!=3)return FALSE;
    if(op==0xff)
    {
        if(((m>>3)&7)!=0 || (rex&6) || rm==4)return FALSE;
        dst=rm;width=(rex&8)?64:32;left=*software_bridge_gpr(c,dst);
    }
    else
    {
        unsigned int src;
        dst=op==0x32?reg:rm;src=op==0x32?rm:reg;
        if(!rex && dst>=4){dst-=4;shift=8;}
        if(!rex && src>=4){src-=4;srcshift=8;}
        if(dst==4 && op!=0x84)return FALSE;
        left=(*software_bridge_gpr(c,dst)>>shift)&255;
        right=(*software_bridge_gpr(c,src)>>srcshift)&255;width=8;
    }
    __asm__ volatile("pushfq; popq %0":"=r"(seed)::"memory");
    seed=(seed & ~(ULONG64)0x8d5) | (c->EFlags & 0x8d5);
    if(op==0xff)
    {
        if(width==64)
            __asm__ volatile("pushq %[seed]; popfq; incq %[left]; pushfq; popq %[flags]"
                :[left]"+&r"(left),[flags]"=&r"(observed):[seed]"r"(seed):"cc","memory");
        else
            __asm__ volatile("pushq %[seed]; popfq; incl %k[left]; pushfq; popq %[flags]"
                :[left]"+&r"(left),[flags]"=&r"(observed):[seed]"r"(seed):"cc","memory");
        e->value[0]=width==64?left:(ULONG)left;
    }
    else
    {
        if(op==0x84)
            __asm__ volatile("pushq %[seed]; popfq; testb %b[right],%b[left]; pushfq; popq %[flags]"
                :[left]"+&r"(left),[flags]"=&r"(observed):[right]"r"(right),[seed]"r"(seed):"cc","memory");
        else
            __asm__ volatile("pushq %[seed]; popfq; xorb %b[right],%b[left]; pushfq; popq %[flags]"
                :[left]"+&r"(left),[flags]"=&r"(observed):[right]"r"(right),[seed]"r"(seed):"cc","memory");
        e->value[0]=(*software_bridge_gpr(c,dst)&~((ULONG64)255<<shift))|((left&255)<<shift);
        e->no_write=op==0x84;
    }
    e->length=p;e->dst=dst;e->flags_valid=1;
    e->flags=(c->EFlags&~0x8d5)|(observed&0x8d5);
    return TRUE;
}
