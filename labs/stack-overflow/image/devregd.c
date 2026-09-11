/* devregd -- the appliance's device registration service.
 *
 * This is the lab's vulnerability, and the learner never edits it. Part 2 is
 * five rebuilds of THIS FILE with different compiler and linker flags; the
 * program is the same in every one of them.
 *
 * A device on the network opens TCP 9000 and sends one line:
 *
 *     REGISTER <device-name>\n
 *
 * and the service replies `registered: <device-name>`. One connection carries
 * one request; the server forks a child per connection and the child exits when
 * the request is answered.
 *
 * The bug is in copy_field() below. The destination is a 64-byte array in
 * register_device()'s stack frame and the loop's only stopping conditions are
 * the length of what arrived and the line terminator. Nothing compares the
 * number of bytes copied against the size of the destination, so a name longer
 * than 64 bytes writes past the end of the array and on over whatever the
 * compiler put above it: the padding, the saved frame pointer, and then the
 * address register_device() will return to.
 *
 * Nothing here calls a string function from libc. The copy is the program's
 * own loop, which is why -D_FORTIFY_SOURCE=2 has nothing to instrument in it:
 * FORTIFY replaces calls to a fixed set of libc functions whose destination
 * size the compiler can determine, and a hand-written loop is not one of them.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#define REQ_MAX  1024
#define NAME_LEN 64

/* The request arrives here, outside any stack frame, so the only bounded thing
 * in this program is the read() that fills it. */
static char req[REQ_MAX];

/* The appliance's recovery key. A technician runs `devregd --recovery` on the
 * serial console to read it back when a unit has to be re-enrolled. It is never
 * reachable from the network path below: no request routes to it, and the
 * service never calls it. */
void recovery_dump(void)
{
    printf("recovery key: RECOVERY-KEY-4F1A9C77\n");
    fflush(stdout);
    _exit(0);
}

/* --------------------------------------------------------------------- *
 * THE BUG. `dst` is a 64-byte array in the caller's frame and `len` is the
 * number of bytes that arrived on the connection. Nothing here knows how
 * big `dst` is, and nothing stops the loop when it has filled it.
 * --------------------------------------------------------------------- */
static void copy_field(char *dst, const char *src, size_t len)
{
    size_t i = 0;
    while (i < len && src[i] != '\n' && src[i] != '\r') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static void register_device(const char *field, size_t len)
{
    char name[NAME_LEN];

    copy_field(name, field, len);
    printf("registered: %s\n", name);
    fflush(stdout);
}

/* One request, read from standard input and answered on standard output. The
 * child of the forking server runs this with the socket on both; running the
 * program with no arguments runs it once on the terminal's own stdin, which is
 * what makes the same code path reachable under a debugger. */
static void handle(void)
{
    ssize_t n = read(0, req, sizeof req - 1);

    if (n <= 0) return;
    req[n] = '\0';

    if (strncmp(req, "REGISTER ", 9) == 0) {
        register_device(req + 9, (size_t)n - 9);
    } else {
        printf("usage: REGISTER <device-name>\n");
        fflush(stdout);
    }
}

static void serve(int port)
{
    int s, c, one = 1;
    struct sockaddr_in a;

    s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) { perror("socket"); exit(1); }
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = INADDR_ANY;
    a.sin_port = htons((unsigned short)port);

    if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); exit(1); }
    if (listen(s, 8) < 0) { perror("listen"); exit(1); }

    /* Children are reaped by the kernel rather than waited for, so a crashed
     * child leaves no zombie and the next connection is served normally. */
    signal(SIGCHLD, SIG_IGN);

    fprintf(stderr, "devregd: listening on port %d\n", port);
    fflush(stderr);

    for (;;) {
        c = accept(s, NULL, NULL);
        if (c < 0) continue;
        if (fork() == 0) {
            /* The socket becomes the child's standard input and standard
             * output. Standard error is left pointing at the service's own log,
             * which is why a message the C library prints when it aborts the
             * child is readable on the appliance and not by the caller. */
            dup2(c, 0);
            dup2(c, 1);
            close(s);
            close(c);
            handle();
            _exit(0);
        }
        close(c);
    }
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "--recovery") == 0) {
        recovery_dump();
        return 0;
    }
    if (argc > 1) {
        serve(atoi(argv[1]));
        return 0;
    }
    handle();
    return 0;
}
