/* Unprefixed first-byte proof only, for the guarded 64-bit dispatcher.
 * D5 is AAD only when APX is absent; with APX it is the REX2 prefix.
 * Do not add 62/C4/C5 or other prefixes without decoding their full encoding. */
static int software_guaranteed_ud_byte(unsigned int opcode,int legacy_d5)
{
    switch(opcode)
    {
        case 0x06:case 0x07:case 0x0e:case 0x16:case 0x17:case 0x1e:case 0x1f:
        case 0x27:case 0x2f:case 0x37:case 0x3f:case 0x60:case 0x61:case 0xce:
        case 0xea:case 0x9a:case 0xd4:return 1;
        case 0xd5:return legacy_d5;
        default:return 0;
    }
}
static int software_legacy_d5_available(void)
{
    unsigned int a,b,c,d;
    __asm__ volatile("cpuid":"=a"(a),"=b"(b),"=c"(c),"=d"(d):"a"(0),"c"(0));
    if(a<7)return 1;
    __asm__ volatile("cpuid":"=a"(a),"=b"(b),"=c"(c),"=d"(d):"a"(7),"c"(0));
    if(a<1)return 1;
    __asm__ volatile("cpuid":"=a"(a),"=b"(b),"=c"(c),"=d"(d):"a"(7),"c"(1));
    return !(d & (1u<<21)); /* Intel APX_F: CPUID.7.1:EDX[21]. */
}
