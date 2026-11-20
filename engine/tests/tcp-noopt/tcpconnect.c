/* Probe for patch 0037: connect a TCP socket to 127.0.0.1:<port> with Winsock, wait for the
 * listener to close it, exit 0. run.sh asks the listener which TCP options the connection uses.
 * SPDX-License-Identifier: LGPL-2.1-or-later */
#include <winsock2.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    WSADATA wsa;
    struct sockaddr_in to = {0};
    char buf[16];
    SOCKET s;

    if (argc < 2 || WSAStartup(MAKEWORD(2, 2), &wsa)) return 2;
    s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) return 3;
    to.sin_family = AF_INET;
    to.sin_port = htons((u_short)atoi(argv[1]));
    to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, (struct sockaddr *)&to, sizeof(to))) { printf("connect: %d\n", WSAGetLastError()); return 4; }
    while (recv(s, buf, sizeof(buf), 0) > 0) ;
    closesocket(s);
    WSACleanup();
    return 0;
}
