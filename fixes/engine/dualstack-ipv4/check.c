/* The check for the dualstack-ipv4 fix: a Windows program, run under a NotProton runner.
 *
 * It does what Forza Horizon 6 does with its game socket: a UDP socket bound to [::]:0 with
 * IPV6_V6ONLY off, then IP_DONTFRAGMENT and IP_TTL set on it. Then it reads IP_TTL back, and
 * IPV6_UNICAST_HOPS, which is what the host was given. On a runner without patch 0026, macOS
 * refuses the IPv4 options on an IPv6 socket and the sets fail with WSAEINVAL. With the fix, or
 * 0026, they succeed and both reads say 200.
 *
 * Exits 0 when everything worked, 2 when a set failed with WSAEINVAL (the bug), 1 otherwise.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

static int set(SOCKET s, int level, int option, DWORD value, const char *name)
{
    if (!setsockopt(s, level, option, (const char *)&value, sizeof(value))) return 0;
    int err = WSAGetLastError();
    printf("%s: setsockopt %s failed, error %d\n", err == WSAEINVAL ? "bug" : "FAIL", name, err);
    return err == WSAEINVAL ? 2 : 1;
}

int main(void)
{
    WSADATA wsa;
    struct sockaddr_in6 any;
    DWORD off = 0, value = 0;
    int len, rc;
    SOCKET s;

    if (WSAStartup(MAKEWORD(2, 2), &wsa)) { printf("FAIL: WSAStartup\n"); return 1; }
    s = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { printf("FAIL: socket\n"); return 1; }
    if (setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, (const char *)&off, sizeof(off))) { printf("FAIL: IPV6_V6ONLY\n"); return 1; }
    memset(&any, 0, sizeof(any));
    any.sin6_family = AF_INET6;
    if (bind(s, (struct sockaddr *)&any, sizeof(any))) { printf("FAIL: bind [::]:0\n"); return 1; }

    if ((rc = set(s, IPPROTO_IP, IP_DONTFRAGMENT, 1, "IP_DONTFRAGMENT"))) return rc;
    if ((rc = set(s, IPPROTO_IP, IP_TTL, 200, "IP_TTL"))) return rc;

    len = sizeof(value);
    if (getsockopt(s, IPPROTO_IP, IP_TTL, (char *)&value, &len) || value != 200) {
        printf("FAIL: IP_TTL reads %lu (error %d)\n", (unsigned long)value, WSAGetLastError());
        return 1;
    }
    value = 0; len = sizeof(value);
    if (getsockopt(s, IPPROTO_IPV6, IPV6_UNICAST_HOPS, (char *)&value, &len) || value != 200) {
        printf("FAIL: IPV6_UNICAST_HOPS reads %lu (error %d)\n", (unsigned long)value, WSAGetLastError());
        return 1;
    }
    printf("ok: IP_DONTFRAGMENT and IP_TTL set on a dual-stack socket; IP_TTL and IPV6_UNICAST_HOPS read 200\n");
    closesocket(s);
    WSACleanup();
    return 0;
}
