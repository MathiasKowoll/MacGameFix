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
