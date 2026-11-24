// Red Dead Online fix
#include "../notproton_plugin.h"

#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define TAG "tcp-noopt"

#define IOCTL_AFD_WINE_CONNECT 0x12032c
#define WS_AF_INET  2
#define WS_AF_INET6 23

struct afd_connect_params {
    int32_t addr_len;
    int32_t synchronous;
};

struct ws_sockaddr_in {
    uint16_t family, port;
    uint8_t  addr[4];
    uint8_t  zero[8];
};

struct ws_sockaddr_in6 {
    uint16_t family, port;
    uint32_t flowinfo;
    uint8_t  addr[16];
    uint32_t scope_id;
};

union ws_sockaddr {
    uint16_t               family;
    struct ws_sockaddr_in  in;
    struct ws_sockaddr_in6 in6;
};

typedef int32_t NTSTATUS;
// ntdll.so is built for the host ABI, not ms_abi
typedef NTSTATUS (*ioctl_fn)(void *handle, void *event, void *apc, void *apc_context, void *io,
                              uint32_t code, void *in, uint32_t in_size, void *out, uint32_t out_size);
typedef NTSTATUS (*to_fd_fn)(void *handle, unsigned access, int *fd, unsigned *options);

static ioctl_fn real_ioctl;
static to_fd_fn to_fd;
static const struct np_plugin_api *api;
static int g_said;

static int remote_peer(const void *in, uint32_t in_size) {
    struct afd_connect_params p;
    union ws_sockaddr a;
    if (!in || in_size < sizeof(p)) return 0;
    memcpy(&p, in, sizeof(p));
    if (p.addr_len < (int32_t)offsetof(struct ws_sockaddr_in, zero) || (uint32_t)p.addr_len > in_size - sizeof(p))
        return 0;
    memset(&a, 0, sizeof(a));
    memcpy(&a, (const unsigned char *)in + sizeof(p), (size_t)p.addr_len < sizeof(a) ? (size_t)p.addr_len : sizeof(a));
    if (a.family == WS_AF_INET) return a.in.addr[0] != 127;
    if (a.family != WS_AF_INET6 || p.addr_len < (int32_t)offsetof(struct ws_sockaddr_in6, scope_id)) return 0;
    static const uint8_t loopback[16] = { [15] = 1 };
    static const uint8_t v4_mapped[12] = { [10] = 0xff, [11] = 0xff };
    if (memcmp(a.in6.addr, loopback, sizeof(loopback)) == 0) return 0;
    return !(memcmp(a.in6.addr, v4_mapped, sizeof(v4_mapped)) == 0 && a.in6.addr[12] == 127);
}

static NTSTATUS ioctl_hook(void *handle, void *event, void *apc, void *apc_context, void *io,
                           uint32_t code, void *in, uint32_t in_size, void *out, uint32_t out_size) {
    int fd = -1;
    if (code == IOCTL_AFD_WINE_CONNECT && remote_peer(in, in_size) && to_fd(handle, 0, &fd, NULL) == 0) {
        int type = 0, one = 1;
        socklen_t len = sizeof(type);
        if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &len) == 0 && type == SOCK_STREAM
            && setsockopt(fd, IPPROTO_TCP, TCP_NOOPT, &one, sizeof(one)) == 0
            && !__atomic_exchange_n(&g_said, 1, __ATOMIC_RELAXED) && api)
            api->log(TAG, "first TCP connection goes out without TCP options");
        close(fd);
    }
    return real_ioctl(handle, event, apc, apc_context, io, code, in, in_size, out, out_size);
}

static void arm(const struct mach_header_64 *mh, intptr_t slide, const char *image) {
    uintptr_t fn = api->symbol(mh, slide, "_NtDeviceIoControlFile");
    to_fd = (to_fd_fn)api->symbol(mh, slide, "_wine_server_handle_to_fd");
    if (!fn || !to_fd) {
        api->log(TAG, "%s has no NtDeviceIoControlFile or wine_server_handle_to_fd, not armed", image);
        return;
    }
    uintptr_t *syscall_entry = NULL;
    int refs = api->count_pointers(mh, slide, fn, &syscall_entry);
    if (refs != 1) {
        api->log(TAG, "%d syscall table entries point at NtDeviceIoControlFile instead of 1, not armed", refs);
        return;
    }
    real_ioctl = (ioctl_fn)fn;
    if (!api->swap_pointer(syscall_entry, fn, (uintptr_t)ioctl_hook)) {
        api->log(TAG, "the syscall table entry could not be written, not armed");
        return;
    }
    api->log(TAG, "TCP connections to other hosts go out without TCP options");
}

#ifndef NP_PLUGIN_TEST
__attribute__((constructor))
#endif
static void tcp_noopt_init(void) {
    if (!(api = np_plugin_api())) {
        fprintf(stderr, TAG ": plugin-host.dylib isn't loaded, not armed\n");
        return;
    }
    api->on_first_image("ntdll.so", "-unix/", arm);
}
