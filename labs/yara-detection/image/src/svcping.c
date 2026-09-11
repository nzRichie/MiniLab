/* Benign: opens a TCP connection to host:port and reports whether it
 * completed. Imports WS2_32, not WININET: it speaks no application protocol. */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    WSADATA wsa;
    struct addrinfo hints, *res = NULL;
    SOCKET s;
    int rc;
    if (argc < 3) { fprintf(stderr, "usage: svcping HOST PORT\n"); return 2; }
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 1;
    ZeroMemory(&hints, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(argv[1], argv[2], &hints, &res) != 0) { WSACleanup(); return 1; }
    s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    rc = connect(s, res->ai_addr, (int)res->ai_addrlen);
    printf("%s:%s %s\n", argv[1], argv[2], rc == 0 ? "open" : "closed");
    closesocket(s);
    freeaddrinfo(res);
    WSACleanup();
    return rc == 0 ? 0 : 1;
}
