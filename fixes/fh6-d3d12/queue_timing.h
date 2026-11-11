/* Bounded CPU-side queue observer. Forwards every original argument and return.
 * Wait records submission of a GPU queue wait, not GPU completion. No added
 * fence, query, barrier, resource transition or descriptor mutation. */
#include <stdint.h>
#define QT_CAPACITY 131072
struct qt_record {UINT64 begin,end,queue,object,value,count;DWORD tid,kind,status,type;};
struct qt_header {UINT64 magic,version,size,capacity,count,dropped,active,pid,start,end,frequency,complete,reserved[4];};
static struct qt_header qt_head;
static struct qt_record *qt_records;
static volatile LONG qt_enabled;
static int qt_configured;
struct qt_table {ID3D12CommandQueueVtbl *table;ID3D12CommandQueueVtbl original;volatile LONG ready;};
static struct qt_table qt_tables[32];
static SRWLOCK qt_table_lock=SRWLOCK_INIT;
static UINT64 qt_clock(void){LARGE_INTEGER q;QueryPerformanceCounter(&q);return q.QuadPart;}
static struct qt_table *qt_find(ID3D12CommandQueue *q)
{
    void *vt=*(void**)q;
    for(unsigned i=0;i<32;i++)if(qt_tables[i].ready&&qt_tables[i].table==vt)return &qt_tables[i];
    return NULL;
}
static struct qt_record *qt_begin(ID3D12CommandQueue *q,struct qt_table *t,DWORD kind,UINT64 object,UINT64 value,UINT64 count)
{
    LONG64 index;struct qt_record *r;UINT64 now;
    if(!qt_enabled)return NULL;
    InterlockedIncrement64((LONG64*)&qt_head.active);
    if(!qt_enabled)goto inactive;
    now=qt_clock();if(now<qt_head.start||now>=qt_head.end)goto inactive;
    index=InterlockedIncrement64((LONG64*)&qt_head.count)-1;
    if(index>=QT_CAPACITY){InterlockedIncrement64((LONG64*)&qt_head.dropped);goto inactive;}
    D3D12_COMMAND_QUEUE_DESC desc; t->original.GetDesc(q,&desc);
    r=&qt_records[index];r->type=desc.Type;r->queue=(uintptr_t)q;r->kind=kind;r->tid=GetCurrentThreadId();r->object=object;r->value=value;r->count=count;r->begin=qt_clock();return r;
inactive:InterlockedDecrement64((LONG64*)&qt_head.active);return NULL;
}
static void qt_end(struct qt_record *r,HRESULT status)
{
    if(!r)return;r->end=qt_clock();r->status=status;InterlockedDecrement64((LONG64*)&qt_head.active);
}
static void STDMETHODCALLTYPE qt_execute(ID3D12CommandQueue *q,UINT n,ID3D12CommandList *const *lists)
{
    DWORD saved=GetLastError();struct qt_table *t=qt_find(q);struct qt_record *r=qt_begin(q,t,1,0,0,n);SetLastError(saved);
    t->original.ExecuteCommandLists(q,n,lists);saved=GetLastError();qt_end(r,S_OK);SetLastError(saved);
}
static void STDMETHODCALLTYPE qt_update(ID3D12CommandQueue *q,ID3D12Resource *res,UINT n,const D3D12_TILED_RESOURCE_COORDINATE *coords,const D3D12_TILE_REGION_SIZE *sizes,ID3D12Heap *heap,UINT ranges,const D3D12_TILE_RANGE_FLAGS *flags,const UINT *offsets,const UINT *counts,D3D12_TILE_MAPPING_FLAGS f)
{
    DWORD saved=GetLastError();struct qt_table *t=qt_find(q);struct qt_record *r=qt_begin(q,t,2,(uintptr_t)res,ranges,n);SetLastError(saved);
    t->original.UpdateTileMappings(q,res,n,coords,sizes,heap,ranges,flags,offsets,counts,f);saved=GetLastError();qt_end(r,S_OK);SetLastError(saved);
}
static void STDMETHODCALLTYPE qt_copy(ID3D12CommandQueue *q,ID3D12Resource *dst,const D3D12_TILED_RESOURCE_COORDINATE *dc,ID3D12Resource *src,const D3D12_TILED_RESOURCE_COORDINATE *sc,const D3D12_TILE_REGION_SIZE *sz,D3D12_TILE_MAPPING_FLAGS f)
{
    DWORD saved=GetLastError();struct qt_table *t=qt_find(q);struct qt_record *r=qt_begin(q,t,3,(uintptr_t)dst,(uintptr_t)src,0);SetLastError(saved);
    t->original.CopyTileMappings(q,dst,dc,src,sc,sz,f);saved=GetLastError();qt_end(r,S_OK);SetLastError(saved);
}
static HRESULT STDMETHODCALLTYPE qt_signal(ID3D12CommandQueue *q,ID3D12Fence *f,UINT64 value)
{
    DWORD saved=GetLastError();struct qt_table *t=qt_find(q);struct qt_record *r=qt_begin(q,t,4,(uintptr_t)f,value,0);SetLastError(saved);
    HRESULT hr=t->original.Signal(q,f,value);saved=GetLastError();qt_end(r,hr);SetLastError(saved);return hr;
}
static HRESULT STDMETHODCALLTYPE qt_wait(ID3D12CommandQueue *q,ID3D12Fence *f,UINT64 value)
{
    DWORD saved=GetLastError();struct qt_table *t=qt_find(q);struct qt_record *r=qt_begin(q,t,5,(uintptr_t)f,value,0);SetLastError(saved);
    HRESULT hr=t->original.Wait(q,f,value);saved=GetLastError();qt_end(r,hr);SetLastError(saved);return hr;
}
static void qt_patch_queue(void *iface)
{
    ID3D12CommandQueueVtbl *vt=*(ID3D12CommandQueueVtbl**)iface;struct qt_table *t=NULL;void *ignored=NULL;
    if(!qt_configured)return;
    AcquireSRWLockExclusive(&qt_table_lock);
    for(unsigned i=0;i<32;i++){if(qt_tables[i].ready&&qt_tables[i].table==vt)goto done;if(!qt_tables[i].ready&&!t)t=&qt_tables[i];}
    if(!t)goto done;
    t->original=*vt;t->table=vt;InterlockedExchange(&t->ready,1);
    patch_slot((void**)&vt->ExecuteCommandLists,qt_execute,&ignored);ignored=NULL;
    patch_slot((void**)&vt->UpdateTileMappings,qt_update,&ignored);ignored=NULL;
    patch_slot((void**)&vt->CopyTileMappings,qt_copy,&ignored);ignored=NULL;
    patch_slot((void**)&vt->Signal,qt_signal,&ignored);ignored=NULL;
    patch_slot((void**)&vt->Wait,qt_wait,&ignored);
done:ReleaseSRWLockExclusive(&qt_table_lock);
}
static void qt_sleep_until(UINT64 stop)
{
    UINT64 now;while((now=qt_clock())<stop){UINT64 ms=(stop-now)/10000;Sleep((DWORD)(ms>1000?1000:ms?ms:1));}
}
static DWORD WINAPI qt_writer(void *arg)
{
    HANDLE f=arg;DWORD wrote;
    qt_sleep_until(qt_head.start);InterlockedExchange(&qt_enabled,1);
    qt_sleep_until(qt_head.end);InterlockedExchange(&qt_enabled,0);
    while(InterlockedCompareExchange64((LONG64*)&qt_head.active,0,0))Sleep(1);
    if(qt_head.count>QT_CAPACITY)qt_head.count=QT_CAPACITY;
    qt_head.complete=1;SetFilePointer(f,0,NULL,FILE_BEGIN);
    BOOL ok=WriteFile(f,&qt_head,sizeof qt_head,&wrote,NULL)&&wrote==sizeof qt_head;
    DWORD bytes=(DWORD)(qt_head.count*sizeof(*qt_records));ok=ok&&WriteFile(f,qt_records,bytes,&wrote,NULL)&&wrote==bytes;
    if(!ok){qt_head.complete=2;SetFilePointer(f,0,NULL,FILE_BEGIN);WriteFile(f,&qt_head,sizeof qt_head,&wrote,NULL);}
    CloseHandle(f);return ok?0:1;
}
static void qt_init(void)
{
    char dir[1024],start[64],path[1200],*end;DWORD n,wrote;HANDLE f,worker;LARGE_INTEGER freq;UINT64 now;
    if(sizeof(struct qt_record)!=64||sizeof(struct qt_header)!=128)return;
    n=GetEnvironmentVariableA("FH6_TRACE_DIR",dir,sizeof dir);if(!n||n>=sizeof dir||dir[0]!='/')return;
    n=GetEnvironmentVariableA("FH6_TRACE_START",start,sizeof start);if(!n||n>=sizeof start)return;
    qt_head.start=strtoull(start,&end,10);now=qt_clock();QueryPerformanceFrequency(&freq);
    if(*end||qt_head.start<=now||qt_head.start-now>600*freq.QuadPart||freq.QuadPart!=10000000)return;
    qt_head.end=qt_head.start+20*freq.QuadPart;qt_head.frequency=freq.QuadPart;qt_head.capacity=QT_CAPACITY;
    qt_head.magic=0x4648364752415048ULL;qt_head.version=1;qt_head.size=64;qt_head.pid=GetCurrentProcessId();
    if(snprintf(path,sizeof path,"Z:%s/graphics-%lu.bin",dir,GetCurrentProcessId())>=(int)sizeof path)return;
    for(char *c=path;*c;c++)if(*c=='/')*c='\\';
    f=CreateFileA(path,GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);if(f==INVALID_HANDLE_VALUE)return;
    qt_records=VirtualAlloc(NULL,QT_CAPACITY*sizeof(*qt_records),MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    if(!qt_records){CloseHandle(f);return;}memset(qt_records,0,QT_CAPACITY*sizeof(*qt_records));
    if(!WriteFile(f,&qt_head,sizeof qt_head,&wrote,NULL)||wrote!=sizeof qt_head){CloseHandle(f);return;}
    worker=CreateThread(NULL,0,qt_writer,f,0,NULL);if(!worker){CloseHandle(f);return;}CloseHandle(worker);qt_configured=1;
}
