/* Native macOS probe for patch 0026: what the kernel does with IPv4 options on a dual-stack
 * (IPV6_V6ONLY off) UDP socket. It checks that each IPPROTO_IP option 0026 handles is refused
 * there with EINVAL, that each IPv6 counterpart 0026 uses instead is taken, and that the
 * counterpart reaches IPv4-mapped traffic: a datagram sent to ::ffff:127.0.0.1 with
 * IPV6_UNICAST_HOPS 200 must reach an IPv4 socket with TTL 200 (the default is 64).
 * run.sh builds it for arm64 and for x86_64 (Rosetta) and runs both. */

#define __APPLE_USE_RFC_3542 1  /* IPV6_DONTFRAG, as Wine's socket.c defines it */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/uio.h>

static int failures, checks;

static void check(int ok, const char *what)
{
    checks++;
    if (ok) return;
    failures++;
    printf("FAIL: %s (%s)\n", what, strerror(errno));
}

/* An IPv4 option on the dual-stack socket: refused with EINVAL, set and read alike. */
static void check_refused(int fd, int option, int value, const char *what)
{
    int got;
    socklen_t length = sizeof(got);

    errno = 0;
    check(setsockopt(fd, IPPROTO_IP, option, &value, sizeof(value)) == -1 && errno == EINVAL, what);
    errno = 0;
    check(getsockopt(fd, IPPROTO_IP, option, &got, &length) == -1 && errno == EINVAL, what);
}

/* An IPv6 counterpart: taken, and read back as set. */
static void check_taken(int fd, int option, int value, const char *what)
{
    int got = -1;
    socklen_t length = sizeof(got);

    errno = 0;
    check(!setsockopt(fd, IPPROTO_IPV6, option, &value, sizeof(value)), what);
    check(!getsockopt(fd, IPPROTO_IPV6, option, &got, &length) && got == value, what);
}

/* The TTL the IPv4 socket saw on its next datagram, -1 if none came within its timeout. */
static int received_ttl(int fd)
{
    char data[16], control[64];
    struct iovec iov = { data, sizeof(data) };
    struct msghdr message;
    struct cmsghdr *header;

    memset(&message, 0, sizeof(message));
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);
    if (recvmsg(fd, &message, 0) < 0) return -1;
    for (header = CMSG_FIRSTHDR(&message); header; header = CMSG_NXTHDR(&message, header))
        if (header->cmsg_level == IPPROTO_IP && header->cmsg_type == IP_RECVTTL)
            return *(unsigned char *)CMSG_DATA(header);
    return -1;
}

int main(void)
{
    struct sockaddr_in6 any6, mapped;
    struct sockaddr_in loopback;
    struct timeval timeout = { 2, 0 };
    socklen_t length = sizeof(loopback);
    int dual, ipv4, off = 0, on = 1, ttl;

    dual = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP);
    check(dual != -1, "socket AF_INET6");
    check(!setsockopt(dual, IPPROTO_IPV6, IPV6_V6ONLY, &off, sizeof(off)), "IPV6_V6ONLY 0");
    memset(&any6, 0, sizeof(any6));
    any6.sin6_len = sizeof(any6);
    any6.sin6_family = AF_INET6;
    any6.sin6_addr = in6addr_any;
    check(!bind(dual, (struct sockaddr *)&any6, sizeof(any6)), "bind [::]");

    check_refused(dual, IP_DONTFRAG, 1, "IP_DONTFRAG refused on AF_INET6");
    check_refused(dual, IP_TTL, 255, "IP_TTL refused on AF_INET6");
    check_refused(dual, IP_MULTICAST_TTL, 4, "IP_MULTICAST_TTL refused on AF_INET6");
    check_refused(dual, IP_MULTICAST_LOOP, 1, "IP_MULTICAST_LOOP refused on AF_INET6");

    check_taken(dual, IPV6_DONTFRAG, 1, "IPV6_DONTFRAG taken");
    check_taken(dual, IPV6_MULTICAST_HOPS, 4, "IPV6_MULTICAST_HOPS taken");
    check_taken(dual, IPV6_MULTICAST_LOOP, 1, "IPV6_MULTICAST_LOOP taken");
    check_taken(dual, IPV6_UNICAST_HOPS, 200, "IPV6_UNICAST_HOPS taken");

    ipv4 = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    check(ipv4 != -1, "socket AF_INET");
    check(!setsockopt(ipv4, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)), "SO_RCVTIMEO");
    check(!setsockopt(ipv4, IPPROTO_IP, IP_RECVTTL, &on, sizeof(on)), "IP_RECVTTL");
    memset(&loopback, 0, sizeof(loopback));
    loopback.sin_len = sizeof(loopback);
    loopback.sin_family = AF_INET;
    loopback.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    check(!bind(ipv4, (struct sockaddr *)&loopback, sizeof(loopback)), "bind 127.0.0.1");
    check(!getsockname(ipv4, (struct sockaddr *)&loopback, &length), "getsockname");

    memset(&mapped, 0, sizeof(mapped));
    mapped.sin6_len = sizeof(mapped);
    mapped.sin6_family = AF_INET6;
    mapped.sin6_port = loopback.sin_port;
    inet_pton(AF_INET6, "::ffff:127.0.0.1", &mapped.sin6_addr);
    check(sendto(dual, "fh6", 3, 0, (struct sockaddr *)&mapped, sizeof(mapped)) == 3, "send to ::ffff:127.0.0.1");
    ttl = received_ttl(ipv4);
    printf("IPv4-mapped datagram arrived with TTL %d\n", ttl);
    check(ttl == 200, "IPV6_UNICAST_HOPS 200 reaches IPv4-mapped traffic");

    close(ipv4);
    close(dual);
    printf("%d of %d checks failed\n", failures, checks);
    return failures != 0;
}
