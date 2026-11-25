// IPv4 socket options on a dual-stack socket, applied as their IPv6 counterparts: engine patch
// 0026 as a NotProton plugin, for the games that need it.
//
// Windows applies IPPROTO_IP options on an AF_INET6 socket to its IPv4 traffic (a dual-stack
// socket's IPv4-mapped peers). macOS refuses them there with EINVAL, so a program that sets one
// on a dual-stack socket sees WSAEINVAL. Forza Horizon 6 binds its UDP game socket to [::]:3074
// with IPV6_V6ONLY off, sets IP_DONTFRAGMENT and IP_TTL, and closes the socket when either
// fails: no online session is ever joined.
//
// Patch 0026 does this inside ntdll.so's sock_ioctl for every game. This does the same from
// outside it, in the game's process only: it replaces the syscall table's entry for
// NtDeviceIoControlFile (../mgf_hooks.h), so NotProton's ntdll stays as it is. Every ioctl goes
// to ntdll first, unchanged. Only when one of the four options' get or set ioctls comes back
// STATUS_INVALID_PARAMETER, and the host refuses the IPv4 option on that socket with EINVAL, and
// the socket is AF_INET6, is the IPv6 counterpart set or read instead, as 0026 does:
//   IP_DONTFRAGMENT -> IPV6_DONTFRAG, IP_TTL -> IPV6_UNICAST_HOPS,
//   IP_MULTICAST_TTL -> IPV6_MULTICAST_HOPS, IP_MULTICAST_LOOP -> IPV6_MULTICAST_LOOP.
// On macOS the IPv6 option does reach IPv4-mapped traffic (a datagram sent to ::ffff:127.0.0.1
// with IPV6_UNICAST_HOPS 200 arrives with TTL 200). It reaches the socket's IPv6 traffic too,
// which an IPv4 option does not on Windows; on an IPV6_V6ONLY socket that is all it does. A
// hop limit not yet set reads -1, the system default; the IPv4 option then reports the value in
// use, as Windows does: net.inet.ip.ttl, or 1 for the multicast TTL. With patch 0026 in ntdll
// (MacGameFix's own runner modules) the ioctl succeeds and this never steps in.
//
// It is part of mgf-engine.dylib (../mgf-engine.c), which arms it in Forza Horizon 6.
// build-engine.sh builds it and runs its check (check.c): a Windows program that sets and reads
// IP_TTL and IP_DONTFRAGMENT on a dual-stack UDP socket, under a runner without 0026, with and
// without this fix armed.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

// IPV6_DONTFRAG and the other RFC 3542 options, as Wine's socket.c has them.
#define __APPLE_USE_RFC_3542
#include "../mgf_hooks.h"

#include <errno.h>
#include <netinet/in.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <unistd.h>

#define TAG "dualstack-ipv4"

typedef int32_t NTSTATUS;
#define STATUS_SUCCESS ((NTSTATUS)0)
#define STATUS_INVALID_PARAMETER ((NTSTATUS)0xC000000D)

// include/wine/afd.h: CTL_CODE(FILE_DEVICE_NETWORK, x, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define AFD(x) ((0x12u << 16) | ((uint32_t)(x) << 2))
#define GET_IP_DONTFRAGMENT AFD(242)
#define SET_IP_DONTFRAGMENT AFD(243)
#define GET_IP_MULTICAST_LOOP AFD(250)
#define SET_IP_MULTICAST_LOOP AFD(251)
#define GET_IP_MULTICAST_TTL AFD(252)
#define SET_IP_MULTICAST_TTL AFD(253)
#define GET_IP_TTL AFD(260)
#define SET_IP_TTL AFD(261)

// The IO_STATUS_BLOCK of a 64-bit process.
struct iosb {
    union { NTSTATUS status; void *pointer; };
    uintptr_t information;
};

// ntdll.so is built for the host ABI, not ms_abi.
typedef NTSTATUS (*ioctl_fn)(void *handle, void *event, void *apc, void *apc_context, struct iosb *io,
                             uint32_t code, void *in, uint32_t in_size, void *out, uint32_t out_size);
typedef NTSTATUS (*to_fd_fn)(void *handle, unsigned access, int *fd, unsigned *options);

static const struct np_plugin_api *api;
static ioctl_fn real_ioctl;
static to_fd_fn to_fd;
static int said;

// The ioctl's IPv4 option, its IPv6 counterpart, whether it is a set, and whether Wine takes it
// on datagram sockets only. 0 when the ioctl is not one of them.
static int which(uint32_t code, int *option, int *option6, int *set, int *dgram) {
    *dgram = 0;
    switch (code) {
    case GET_IP_DONTFRAGMENT: case SET_IP_DONTFRAGMENT:
        *option = IP_DONTFRAG; *option6 = IPV6_DONTFRAG; break;
    case GET_IP_TTL: case SET_IP_TTL:
        *option = IP_TTL; *option6 = IPV6_UNICAST_HOPS; break;
    case GET_IP_MULTICAST_TTL: case SET_IP_MULTICAST_TTL:
        *option = IP_MULTICAST_TTL; *option6 = IPV6_MULTICAST_HOPS; *dgram = 1; break;
    case GET_IP_MULTICAST_LOOP: case SET_IP_MULTICAST_LOOP:
        *option = IP_MULTICAST_LOOP; *option6 = IPV6_MULTICAST_LOOP; *dgram = 1; break;
    default: return 0;
    }
    *set = (code & 4) != 0;  // the set ioctls are the odd functions
    return 1;
}

static int ipv4_default(int option6) {
    int ttl = 64;
    size_t size = sizeof(ttl);
    if (option6 == IPV6_MULTICAST_HOPS) return 1;
    if (sysctlbyname("net.inet.ip.ttl", &ttl, &size, NULL, 0)) ttl = 64;
    return ttl;
}

// The host's answer on the IPv6 counterpart, as sock_ioctl gives it: a status, with the IO
// status block filled on success. EINVAL from the IPv4 option is checked again here, so another
// cause of STATUS_INVALID_PARAMETER is left as ntdll answered.
static int counterpart(int fd, int option, int option6, int set, struct iosb *io, void *in, uint32_t in_size,
                       void *out, uint32_t out_size, NTSTATUS *status) {
    struct sockaddr_storage addr;
    socklen_t alen = sizeof(addr);
    int value;
    if (getsockname(fd, (struct sockaddr *)&addr, &alen) || addr.ss_family != AF_INET6) return 0;
    if (set) {
        if (!in || in_size < 1) return 0;
        if (!setsockopt(fd, IPPROTO_IP, option, in, in_size) || errno != EINVAL) return 0;
        // The IPv6 options take an int; Windows' take a DWORD, and a few hosts' IPv4 ones a byte.
        if (in_size >= sizeof(value)) memcpy(&value, in, sizeof(value));
        else value = *(unsigned char *)in;
        if (setsockopt(fd, IPPROTO_IPV6, option6, &value, sizeof(value))) return 0;
        if (io) io->status = STATUS_SUCCESS;
    } else {
        socklen_t len = out_size, len6 = sizeof(value);
        if (!out || out_size < 1) return 0;
        if (!getsockopt(fd, IPPROTO_IP, option, out, &len) || errno != EINVAL) return 0;
        if (getsockopt(fd, IPPROTO_IPV6, option6, &value, &len6)) return 0;
        if (value < 0 && (option6 == IPV6_UNICAST_HOPS || option6 == IPV6_MULTICAST_HOPS)) value = ipv4_default(option6);
        if (out_size >= sizeof(value)) { memcpy(out, &value, sizeof(value)); len = sizeof(value); }
        else { *(unsigned char *)out = (unsigned char)value; len = 1; }
        if (io) { io->status = STATUS_SUCCESS; io->information = len; }
    }
    if (!__atomic_exchange_n(&said, 1, __ATOMIC_RELAXED))
        api->log(TAG, "first IPv4 option %d on an IPv6 socket %s as IPv6 option %d (%d)", option,
                 set ? "set" : "read", option6, value);
    *status = STATUS_SUCCESS;
    return 1;
}

static NTSTATUS ioctl_hook(void *handle, void *event, void *apc, void *apc_context, struct iosb *io,
                           uint32_t code, void *in, uint32_t in_size, void *out, uint32_t out_size) {
    NTSTATUS status = real_ioctl(handle, event, apc, apc_context, io, code, in, in_size, out, out_size);
    int option, option6, set, dgram, fd = -1;
    if (status != STATUS_INVALID_PARAMETER || !which(code, &option, &option6, &set, &dgram)) return status;
    if (to_fd(handle, 0, &fd, NULL)) return status;
    if (dgram) {  // Wine refuses the multicast options on other sockets before the host is asked
        int type = 0;
        socklen_t len = sizeof(type);
        if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &len) || (type != SOCK_DGRAM && type != SOCK_RAW)) {
            close(fd);
            return status;
        }
    }
    counterpart(fd, option, option6, set, io, in, in_size, out, out_size, &status);
    close(fd);
    return status;
}

static void arm(const struct mach_header_64 *mh, intptr_t slide) {
    uintptr_t old, *slot = mgf_syscall_slot(api, mh, slide, "_NtDeviceIoControlFile", &old);
    to_fd = (to_fd_fn)api->symbol(mh, slide, "_wine_server_handle_to_fd");
    if (!slot || !to_fd) {
        api->log(TAG, "no one syscall table entry for NtDeviceIoControlFile, or no wine_server_handle_to_fd, not armed");
        return;
    }
    real_ioctl = (ioctl_fn)old;
    if (!api->swap_pointer(slot, old, (uintptr_t)ioctl_hook)) {
        api->log(TAG, "the syscall table could not be written, not armed");
        return;
    }
    api->log(TAG, "IPv4 options the host refuses on an IPv6 socket are applied as their IPv6 counterparts");
}

// mgf-engine.dylib (../mgf-engine.c) arms this for the games that need it.
void mgf_dualstack_ipv4_arm(const struct np_plugin_api *with, const struct mach_header_64 *mh, intptr_t slide) {
    api = with;
    arm(mh, slide);
}
