/* Diagnostic only: prefaulted bounded storage, lock-free publication and a
 * native worker flushing only after the common capture window. Signal paths
 * perform no allocation, file access, formatting or dynamic symbol lookup. */
#include <mach/mach_time.h>
#include <stdint.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
#define NT_CAPACITY 2097152
struct native_timing_record {uint64_t qpc,rip,rsp,aux;uint32_t tid,kind,ready,pad;};
struct native_timing_header {uint64_t magic,version,record_size,capacity,count,dropped,active,pid,start,end,frequency,complete,reserved[4];};
_Static_assert(sizeof(struct native_timing_record)==48,"native record ABI");
_Static_assert(sizeof(struct native_timing_header)==128,"native header ABI");
_Static_assert(__atomic_always_lock_free(8,0),"signal-safe counters");
static struct native_timing_header nt_header;
static struct native_timing_record *nt_records;
static mach_timebase_info_data_t nt_timebase;
static unsigned int nt_enabled;
static int nt_fd=-1;
static uint64_t nt_clock(void) {return mach_continuous_time()*nt_timebase.numer/nt_timebase.denom/100;}
static int nt_write_all(const void *data,size_t n)
{
    const char *p=data;
    while(n){ssize_t w=write(nt_fd,p,n);if(w<0&&errno==EINTR)continue;if(w<=0)return 0;p+=w;n-=w;}
    return 1;
}
static void nt_wait_until(uint64_t target)
{
    uint64_t now;
    while((now=nt_clock())<target){uint64_t ticks=target-now;struct timespec ts={(time_t)(ticks/10000000),(long)(ticks%10000000)*100};nanosleep(&ts,NULL);}
}
static void *nt_worker(void *unused)
{
    (void)unused;nt_wait_until(nt_header.start);__atomic_store_n(&nt_enabled,1,__ATOMIC_RELEASE);
    nt_wait_until(nt_header.end);__atomic_store_n(&nt_enabled,0,__ATOMIC_RELEASE);
    while(__atomic_load_n(&nt_header.active,__ATOMIC_ACQUIRE)){struct timespec ts={0,1000000};nanosleep(&ts,NULL);}
    if(nt_header.count>NT_CAPACITY)nt_header.count=NT_CAPACITY;
    nt_header.complete=1;lseek(nt_fd,0,SEEK_SET);
    if(!nt_write_all(&nt_header,sizeof nt_header)||!nt_write_all(nt_records,nt_header.count*sizeof(*nt_records)))nt_header.complete=2;
    if(nt_header.complete==2){lseek(nt_fd,0,SEEK_SET);nt_write_all(&nt_header,sizeof nt_header);}
    close(nt_fd);nt_fd=-1;return NULL;
}
void fh6_native_mark(unsigned int kind,unsigned int tid,UINT64 rip,UINT64 rsp,UINT64 aux)
{
    uint64_t i,q;int saved_errno;
    struct native_timing_record *r;
    if(!__atomic_load_n(&nt_enabled,__ATOMIC_RELAXED))return;
    saved_errno=errno;__atomic_add_fetch(&nt_header.active,1,__ATOMIC_ACQUIRE);
    if(!__atomic_load_n(&nt_enabled,__ATOMIC_ACQUIRE))goto done;
    q=nt_clock();if(q<nt_header.start||q>=nt_header.end)goto done;
    i=__atomic_fetch_add(&nt_header.count,1,__ATOMIC_RELAXED);
    if(i>=NT_CAPACITY){__atomic_add_fetch(&nt_header.dropped,1,__ATOMIC_RELAXED);goto done;}
    r=&nt_records[i];r->qpc=q;r->rip=rip;r->rsp=rsp;r->aux=aux;r->tid=tid;r->kind=kind;
    __atomic_store_n(&r->ready,1,__ATOMIC_RELEASE);
done:__atomic_sub_fetch(&nt_header.active,1,__ATOMIC_RELEASE);errno=saved_errno;
}
static void native_timing_init(void)
{
    const char *dir=getenv("FH6_TRACE_DIR"),*start=getenv("FH6_TRACE_START"),*name,*p;
    uint64_t now;char path[2048],*end;pthread_t worker;struct stat st;
    if(!dir||dir[0]!='/'||!start||main_argc<1)return;
    /* init_startup_info has already removed Wine argv[0]. */
    name=main_argv[0];for(p=name;*p;p++)if(*p=='/'||*p=='\\')name=p+1;
    if(strcasecmp(name,"forzahorizon6.exe")&&strcasecmp(name,"exception_chain_probe.exe")&&strcasecmp(name,"timer_probe.exe"))return;
    mach_timebase_info(&nt_timebase);now=nt_clock();
    nt_header.start=strtoull(start,&end,10);
    if(*end||nt_header.start<=now||nt_header.start-now>6000000000ULL)return;
    nt_header.end=nt_header.start+200000000ULL;nt_header.frequency=10000000;nt_header.capacity=NT_CAPACITY;
    nt_header.magic=UINT64_C(0x4648364e41544956);nt_header.version=1;nt_header.record_size=sizeof(*nt_records);nt_header.pid=getpid();
    if(snprintf(path,sizeof path,"%s/native-%d.bin",dir,(int)getpid())>=(int)sizeof path)return;
    nt_fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,0600);if(nt_fd<0)return;
    if(fstat(nt_fd,&st)||!S_ISREG(st.st_mode)){close(nt_fd);nt_fd=-1;return;}
    nt_records=mmap(NULL,NT_CAPACITY*sizeof(*nt_records),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    if(nt_records==MAP_FAILED){nt_records=NULL;close(nt_fd);nt_fd=-1;return;}
    memset(nt_records,0,NT_CAPACITY*sizeof(*nt_records));
    if(!nt_write_all(&nt_header,sizeof nt_header)||pthread_create(&worker,NULL,nt_worker,NULL)){close(nt_fd);nt_fd=-1;return;}
    pthread_detach(worker);
}
