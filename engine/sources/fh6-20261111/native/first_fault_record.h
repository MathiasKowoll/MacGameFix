/* Opt-in first-fault evidence. No allocation, formatting, locks or symbolication
 * in signal context. The observer never changes exception handling. */
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>

#define FF_MAGIC UINT64_C(0x31464c5446364846)
#define FF_WORDS 48
struct first_fault_packet { uint64_t value[FF_WORDS]; };
_Static_assert(sizeof(struct first_fault_packet) == 384, "stable evidence format");
_Static_assert(__atomic_always_lock_free(sizeof(unsigned int), 0), "signal-safe claim must be lock-free");
static int first_fault_fd = -1;
static unsigned int first_fault_claimed;
static uint64_t first_fault_pid;
static struct first_fault_packet first_fault_packet;

/* Called during ordinary startup, before handlers are installed. Only regular
 * files are accepted. O_APPEND gives each single write a separate file range. */
static int first_fault_open(const char *path)
{
    struct stat st;
    struct first_fault_packet armed = {{0}};
    int fd;
    if (!path || path[0] != '/') return 0;
    fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0600);
    if (fd < 0) return 0;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)) { close(fd); return 0; }
    first_fault_pid = (uint64_t)getpid();
    armed.value[0] = FF_MAGIC;
    armed.value[1] = 1;
    armed.value[2] = sizeof(armed);
    armed.value[3] = 0; /* armed, not a fault */
    armed.value[4] = first_fault_pid;
    if (write(fd, &armed, sizeof(armed)) != sizeof(armed)) { close(fd); return 0; }
    first_fault_fd = fd;
    return 1;
}

/* The caller checks the exact fatal-stack condition before claiming. A second
 * thread or reentrant signal cannot modify the first recorder's storage. */
static struct first_fault_packet *first_fault_begin(void)
{
    if (first_fault_fd < 0 || __atomic_exchange_n(&first_fault_claimed, 1, __ATOMIC_RELAXED)) return 0;
    first_fault_packet.value[0] = FF_MAGIC;
    first_fault_packet.value[1] = 1;
    first_fault_packet.value[2] = sizeof(first_fault_packet);
    first_fault_packet.value[3] = 1;
    first_fault_packet.value[4] = first_fault_pid;
    return &first_fault_packet;
}

static void first_fault_commit(void)
{
    int saved_errno = errno;
    /* One bounded best-effort write. An incomplete record is detectable by the
     * decoder; no retry, blocking lock or recovery is introduced in the game. */
    (void)write(first_fault_fd, &first_fault_packet, sizeof(first_fault_packet));
    errno = saved_errno;
}
