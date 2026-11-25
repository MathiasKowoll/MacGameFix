/* Experimental register-only unsigned MUL. No guest memory access and no
 * context mutation. Both implicit destinations and flags are staged together.
 * Execute MUL on temporary operands so runtime-observed undefined arithmetic
 * flags are captured as well; full equivalence still requires the real-opcode
 * oracle under the target Wine/Rosetta runtime before deployment. */
static BOOL software_bridge_mul(const BYTE *code, CONTEXT *c, struct software_bridge_effect *e)
{
    unsigned int p=0,rex=0,m,src,width;
    ULONG64 low,high,right,seed,observed;
    memset(e,0,sizeof(*e));
    if(code[p]>=0x40 && code[p]<=0x4f)rex=code[p++];
    if(code[p++]!=0xf7)return FALSE;
    m=code[p++];
    /* F7 /4, canonical REX.W/B only. Memory, other operations, operand-size
     * prefixes and stack-source forms remain on the ordinary path. */
    if((m&0xf8)!=0xe0 || (rex&6))return FALSE;
    src=(m&7)+((rex&1)?8:0);
    if(src==4)return FALSE;
    width=(rex&8)?64:32;
    low=c->Rax;right=*software_bridge_gpr(c,src);
    __asm__ volatile("pushfq; popq %0":"=r"(seed)::"memory");
    seed=(seed&~(ULONG64)0x8d5)|(c->EFlags&0x8d5);
    if(width==64)
        __asm__ volatile("pushq %[seed]; popfq; mulq %[right]; pushfq; popq %[flags]"
            :[low]"+&a"(low),[high]"=&d"(high),[flags]"=&r"(observed)
            :[right]"r"(right),[seed]"r"(seed):"cc","memory");
    else
        __asm__ volatile("pushq %[seed]; popfq; mull %k[right]; pushfq; popq %[flags]"
            :[low]"+&a"(low),[high]"=&d"(high),[flags]"=&r"(observed)
            :[right]"r"(right),[seed]"r"(seed):"cc","memory");
    e->length=p;e->dst=0;e->value[0]=width==64?low:(ULONG)low;
    e->gpr2_valid=1;e->gpr2_dst=2;e->gpr2_value=width==64?high:(ULONG)high;
    e->flags_valid=1;e->flags=(c->EFlags&~0x8d5)|(observed&0x8d5);
    return TRUE;
}
