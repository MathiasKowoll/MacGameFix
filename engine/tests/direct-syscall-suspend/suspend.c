/* suspend.exe [seconds] [calm] [step]: threads that make system calls with a syscall instruction of their own, and
 * threads that raise exceptions on purpose, while another thread suspends them. For patches 0028 and 0029;
 * run.sh says how to run it.
 *
 * Copy protection does not call ntdll's stubs. It runs the syscall instruction from memory of its own,
 * which Wine on macOS receives as SIGSYS, and it raises exceptions by the thousand (an undefined
 * instruction, a breakpoint, a bad address, a single step) that a handler of its own steps over. Here
 * threads do the same. The system calls go through stubs written into a private page with ntdll's own
 * system call numbers:
 *
 *   - one calls NtQueryPerformanceCounter and NtReleaseSemaphore as fast as it can and checks every
 *     result: the status, a counter that moves, and the semaphore's previous count, which says whether
 *     the release before it happened once, twice or not at all;
 *   - a pair plays ping-pong, one side waiting in a direct NtWaitForSingleObject, the other waking it
 *     with a direct NtSetEvent;
 *   - four more pairs do the same through kernel32, as a control.
 *
 * Three threads raise one kind of exception each, in a loop (an undefined instruction, a breakpoint,
 * a bad address), and a vectored handler steps over the instruction: every call must give exactly one
 * exception, and a thread that stops making calls was ended by Wine ("nested exception on signal
 * stack"). "step" adds a fourth that sets the trap flag. It is left out by default because Rosetta's
 * own runtime can stop the process when a signal reaches that thread at its popfq, whatever Wine does:
 * "assertion failed: emulated forward to an arm pc that isn't in translated code ...
 * (ThreadContextRegisterState.cpp:694 move_to_instruction_boundary)", seen once here, with 0029.
 *
 * A last thread does SuspendThread, GetThreadContext, ResumeThread to all of them in turn, without
 * pause ("calm" leaves it out). The main thread watches: a look that takes two seconds never returned,
 * and a wake-up that takes three is lost.
 *
 * Exit code 0 when nothing went wrong.
 */
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef LONG (*direct_wait)( HANDLE, BOOLEAN, LARGE_INTEGER * );
typedef LONG (*direct_set)( HANDLE, LONG * );
typedef LONG (*direct_counter)( LARGE_INTEGER *, LARGE_INTEGER * );
typedef LONG (*direct_release)( HANDLE, ULONG, ULONG * );

static direct_wait sys_wait;
static direct_set sys_set;
static direct_counter sys_counter;
static direct_release sys_release;

enum kind { DIRECT, EVENT, ANY_OF_TWO, SEMAPHORE, CONDVAR, KINDS };
static const char *const kind_names[KINDS] = { "direct system call", "event", "any of two", "semaphore", "condition variable" };

struct pair
{
    enum kind kind;
    HANDLE wake, never, done;
    CRITICAL_SECTION cs;
    CONDITION_VARIABLE cv;
    volatile LONG flag;
    volatile LONG waiting;      /* 1 while the waiting side has not woken */
    volatile LONG rounds, never_woke, never_seen, failed;
};

static struct pair pairs[KINDS];
static volatile LONG stop;
static volatile LONG calls, wrong_status, wrong_counter, wrong_count;
static volatile LONG looks, look_tid, look_step;

/* mov r10,rcx; mov eax,<number>; syscall; ret -- the number from ntdll's stub of that name */
static void *make_stub( const char *name )
{
    static unsigned char *page;
    static unsigned int used;
    const unsigned char *stub = (const unsigned char *)GetProcAddress( GetModuleHandleA( "ntdll.dll" ), name );
    unsigned char *code;

    if (!page) page = VirtualAlloc( NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE );
    if (!page || !stub || memcmp( stub, "\x4c\x8b\xd1\xb8", 4 ))
    {
        printf( "FAIL: ntdll's %s is not a system call stub\n", name );
        ExitProcess( 2 );
    }
    code = page + used;
    used += 16;
    memcpy( code, "\x4c\x8b\xd1\xb8", 4 );
    memcpy( code + 4, stub + 4, 4 );
    memcpy( code + 8, "\x0f\x05\xc3", 3 );
    return code;
}

/* ud2; int3; mov eax,[0]; and pushfq, or [rsp],0x100 (the trap flag), popfq, four nops -- each followed by ret */
enum trap { UNDEFINED, BREAKPOINT, BAD_ADDRESS, SINGLE_STEP, TRAPS };
static const char *const trap_names[TRAPS] = { "undefined instruction", "breakpoint", "bad address", "single step" };
static const unsigned char trap_length[TRAPS] = { 2, 1, 7, 0 };
static unsigned char *trap_code;
static volatile LONG trap_made[TRAPS], trap_seen[TRAPS], trap_unexpected;
static int raisers = SINGLE_STEP;  /* TRAPS with "step" */

static LONG CALLBACK step_over( EXCEPTION_POINTERS *info )
{
    ULONG_PTR address = (ULONG_PTR)info->ExceptionRecord->ExceptionAddress;
    int i;

    if (info->ExceptionRecord->ExceptionCode == EXCEPTION_SINGLE_STEP)
    {
        InterlockedIncrement( &trap_seen[SINGLE_STEP] );
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    for (i = 0; i < SINGLE_STEP; i++)
    {
        if (address != (ULONG_PTR)trap_code + 16 * i) continue;
        InterlockedIncrement( &trap_seen[i] );
        info->ContextRecord->Rip = address + trap_length[i];
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    InterlockedIncrement( &trap_unexpected );
    return EXCEPTION_CONTINUE_SEARCH;
}

static DWORD WINAPI raiser( void *arg )
{
    int i = (int)(ULONG_PTR)arg;
    void (*raise_it)(void) = (void (*)(void))(trap_code + 16 * i);

    while (!stop)
    {
        raise_it();
        InterlockedIncrement( &trap_made[i] );
    }
    return 0;
}

static void start_raisers( void )
{
    int i;

    trap_code = VirtualAlloc( NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE );
    if (!trap_code) ExitProcess( 2 );
    memcpy( trap_code + 16 * UNDEFINED, "\x0f\x0b\xc3", 3 );
    memcpy( trap_code + 16 * BREAKPOINT, "\xcc\xc3", 2 );
    memcpy( trap_code + 16 * BAD_ADDRESS, "\x8b\x04\x25\x00\x00\x00\x00\xc3", 8 );
    memcpy( trap_code + 16 * SINGLE_STEP, "\x9c\x48\x81\x0c\x24\x00\x01\x00\x00\x9d\x90\x90\x90\x90\xc3", 15 );
    AddVectoredExceptionHandler( 1, step_over );
    for (i = 0; i < raisers; i++) CreateThread( NULL, 0, raiser, (void *)(ULONG_PTR)i, 0, NULL );
}

static void complain( volatile LONG *count, const char *format, unsigned long a, unsigned long b )
{
    if (InterlockedIncrement( count ) > 5) return;
    printf( format, a, b );
    fflush( stdout );
}

static DWORD WINAPI caller( void *arg )
{
    HANDLE semaphore = CreateSemaphoreA( NULL, 0, 0x7fffffff, NULL );
    LARGE_INTEGER counter, last;
    ULONG expected = 0, previous;
    LONG status;

    (void)arg;
    last.QuadPart = 0;
    while (!stop)
    {
        counter.QuadPart = 0;
        status = sys_counter( &counter, NULL );
        if (status) complain( &wrong_status, "  NtQueryPerformanceCounter returned %08lx (a system call number means it never ran)\n", status, 0 );
        else if (!counter.QuadPart || counter.QuadPart < last.QuadPart) InterlockedIncrement( &wrong_counter );
        else last = counter;

        previous = ~0u;
        status = sys_release( semaphore, 1, &previous );
        if (status == (LONG)0xc0000047)  /* STATUS_SEMAPHORE_LIMIT_EXCEEDED: start again from zero */
        {
            while (WaitForSingleObject( semaphore, 0 ) == WAIT_OBJECT_0) {}
            expected = 0;
        }
        else if (status)
            complain( &wrong_status, "  NtReleaseSemaphore returned %08lx (a system call number means it never ran)\n", status, 0 );
        else if (previous != expected)
        {
            complain( &wrong_count, "  the semaphore had %lu releases where %lu were made\n", previous, expected );
            expected = previous + 1;
        }
        else expected++;
        InterlockedIncrement( &calls );
    }
    return 0;
}

static DWORD WINAPI waiting_side( void *arg )
{
    struct pair *pair = arg;
    HANDLE handles[2];

    for (;;)
    {
        pair->waiting = 1;
        switch (pair->kind)
        {
        case DIRECT:
            if (sys_wait( pair->wake, FALSE, NULL )) InterlockedIncrement( &pair->failed );
            break;
        case EVENT:
        case SEMAPHORE:
            WaitForSingleObject( pair->wake, INFINITE );
            break;
        case ANY_OF_TWO:
            handles[0] = pair->never;
            handles[1] = pair->wake;
            WaitForMultipleObjects( 2, handles, FALSE, INFINITE );
            break;
        case CONDVAR:
            EnterCriticalSection( &pair->cs );
            while (!pair->flag) SleepConditionVariableCS( &pair->cv, &pair->cs, INFINITE );
            pair->flag = 0;
            LeaveCriticalSection( &pair->cs );
            break;
        default:
            break;
        }
        pair->waiting = 0;
        SetEvent( pair->done );
    }
    return 0;
}

static DWORD WINAPI waking_side( void *arg )
{
    struct pair *pair = arg;

    while (!stop)
    {
        switch (pair->kind)
        {
        case DIRECT:
            if (sys_set( pair->wake, NULL )) InterlockedIncrement( &pair->failed );
            break;
        case EVENT:
        case ANY_OF_TWO:
            SetEvent( pair->wake );
            break;
        case SEMAPHORE:
            ReleaseSemaphore( pair->wake, 1, NULL );
            break;
        case CONDVAR:
            EnterCriticalSection( &pair->cs );
            pair->flag = 1;
            LeaveCriticalSection( &pair->cs );
            WakeConditionVariable( &pair->cv );
            break;
        default:
            break;
        }
        if (WaitForSingleObject( pair->done, 3000 ) == WAIT_TIMEOUT)
        {
            if (pair->waiting)
            {
                InterlockedIncrement( &pair->never_woke );
                continue;  /* wake it again */
            }
            InterlockedIncrement( &pair->never_seen );
        }
        InterlockedIncrement( &pair->rounds );
    }
    return 0;
}

static DWORD WINAPI suspender( void *arg )
{
    static HANDLE threads[64];
    static DWORD ids[64];
    DWORD self = GetCurrentThreadId(), main_thread = (DWORD)(ULONG_PTR)arg;
    HANDLE snapshot = CreateToolhelp32Snapshot( TH32CS_SNAPTHREAD, 0 );
    THREADENTRY32 entry;
    CONTEXT context;
    int count = 0, i;

    entry.dwSize = sizeof(entry);
    if (Thread32First( snapshot, &entry )) do
    {
        if (entry.th32OwnerProcessID != GetCurrentProcessId() || count == 64) continue;
        if (entry.th32ThreadID == self || entry.th32ThreadID == main_thread) continue;
        threads[count] = OpenThread( THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT, FALSE, entry.th32ThreadID );
        if (threads[count]) ids[count++] = entry.th32ThreadID;
    } while (Thread32Next( snapshot, &entry ));
    CloseHandle( snapshot );

    while (!stop)
    {
        for (i = 0; i < count; i++)
        {
            look_tid = ids[i];
            look_step = 1;
            if (SuspendThread( threads[i] ) == (DWORD)-1) continue;
            look_step = 2;
            context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
            GetThreadContext( threads[i], &context );
            look_step = 3;
            ResumeThread( threads[i] );
            look_step = 0;
            InterlockedIncrement( &looks );
        }
    }
    return 0;
}

int main( int argc, char **argv )
{
    static const char *const steps[] = { "between looks", "SuspendThread", "GetThreadContext", "ResumeThread" };
    int seconds = argc > 1 ? atoi( argv[1] ) : 20, calm = 0;
    int i, second, stuck = 0, bad = 0, suspended_seconds = 0;
    LONG last_looks = 0, made_before[TRAPS], made_under[TRAPS];

    setvbuf( stdout, NULL, _IONBF, 0 );
    for (i = 2; i < argc; i++)
    {
        if (!strcmp( argv[i], "calm" )) calm = 1;
        if (!strcmp( argv[i], "step" )) raisers = TRAPS;
    }
    sys_wait = make_stub( "NtWaitForSingleObject" );
    sys_set = make_stub( "NtSetEvent" );
    sys_counter = make_stub( "NtQueryPerformanceCounter" );
    sys_release = make_stub( "NtReleaseSemaphore" );

    CreateThread( NULL, 0, caller, NULL, 0, NULL );
    start_raisers();
    for (i = 0; i < KINDS; i++)
    {
        struct pair *pair = &pairs[i];

        pair->kind = i;
        pair->wake = i == SEMAPHORE ? CreateSemaphoreA( NULL, 0, 1000, NULL ) : CreateEventA( NULL, FALSE, FALSE, NULL );
        pair->never = CreateEventA( NULL, TRUE, FALSE, NULL );
        pair->done = CreateEventA( NULL, FALSE, FALSE, NULL );
        InitializeCriticalSection( &pair->cs );
        InitializeConditionVariable( &pair->cv );
        CreateThread( NULL, 0, waiting_side, pair, 0, NULL );
        CreateThread( NULL, 0, waking_side, pair, 0, NULL );
    }
    Sleep( 300 );
    for (i = 0; i < raisers; i++) made_before[i] = trap_made[i];
    if (!calm) CreateThread( NULL, 0, suspender, (void *)(ULONG_PTR)GetCurrentThreadId(), 0, NULL );

    for (second = 0; second < seconds && stuck < 2; second++)
    {
        Sleep( 1000 );
        if (!calm) stuck = looks == last_looks ? stuck + 1 : 0;
        last_looks = looks;
        /* what each raiser did in the last second: one that Wine ended makes no more calls */
        if (second == seconds - 2) for (i = 0; i < raisers; i++) made_under[i] = trap_made[i];
    }
    suspended_seconds = second;
    stop = 1;
    Sleep( 200 );

    printf( "%ld looks at %d threads in %d s; %ld pairs of direct system calls\n", looks, 11 + raisers, suspended_seconds, calls );
    if (stuck >= 2)
    {
        printf( "FAIL: a look at thread %lu never returned from %s\n", (unsigned long)look_tid, steps[look_step & 3] );
        bad = 1;
    }
    if (wrong_status || wrong_counter || wrong_count)
    {
        printf( "FAIL: direct system calls with a wrong status %ld, a wrong counter %ld, run twice or not at all %ld\n",
                wrong_status, wrong_counter, wrong_count );
        bad = 1;
    }
    for (i = 0; i < KINDS; i++)
    {
        const struct pair *pair = &pairs[i];

        printf( "%-20s %8ld rounds, never woke %ld, answer never seen %ld, calls failed %ld\n", kind_names[i],
                pair->rounds, pair->never_woke, pair->never_seen, pair->failed );
        if (pair->never_woke || pair->never_seen || pair->failed || !pair->rounds) bad = 1;
    }
    for (i = 0; i < raisers; i++)
    {
        LONG made = trap_made[i], seen = trap_seen[i];
        /* the thread may have been stopped between an exception and the count of its call */
        int mismatch = seen < made || seen > made + 1;
        int ended = seconds >= 3 && stuck < 2 && made == made_under[i];

        printf( "%-22s %8ld raised, %8ld seen%s%s\n", trap_names[i], made, seen,
                mismatch ? ", MISMATCH" : "", ended ? ", THREAD STOPPED" : "" );
        if (mismatch || ended || made == made_before[i]) bad = 1;
    }
    if (trap_unexpected)
    {
        printf( "FAIL: %ld exceptions from somewhere else\n", trap_unexpected );
        bad = 1;
    }
    if (!calls) bad = 1;
    printf( "%s\n", bad ? "FAILED" : "passed" );
    TerminateProcess( GetCurrentProcess(), bad );
    return bad;
}
