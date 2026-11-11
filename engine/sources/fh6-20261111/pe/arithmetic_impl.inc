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
