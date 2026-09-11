/* diag.cgi -- the appliance's public network-tools page.
 *
 * This is the lab's vulnerability, and the learner never edits it. Every defence
 * in Part 2 is configuration around this program; the program itself is the same
 * before and after.
 *
 * The bug is on one line, marked below. The hostname the caller supplied is
 * pasted into a command string with %s and the string is handed to popen(3),
 * which runs it with `/bin/sh -c`. Nothing quotes the substitution and nothing
 * rejects a character, so every byte the caller sent that /bin/sh treats as
 * syntax IS syntax: `;` ends the ping command and starts another, `|` pipes
 * ping's output somewhere, and `$( )` and backticks substitute the output of a
 * command the caller chose.
 *
 * Everything else here is ordinary CGI plumbing: read QUERY_STRING, pull the
 * `host` parameter out of it, percent-decode it, run the command, and copy the
 * output to standard output behind a CGI header block.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HOST_MAX 192
#define CMD_MAX  512

static int hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* Percent-decode `in` into `out`, which holds at most n bytes including the
 * terminator. `+` becomes a space, as application/x-www-form-urlencoded says.
 * The decode is bounded, so the caller cannot overflow `out` by sending a long
 * parameter; a long parameter is truncated instead. That is deliberate: this
 * lab's bug is the shell metacharacter, not a buffer. */
static void url_decode(const char *in, char *out, size_t n)
{
    size_t o = 0;
    while (*in && o + 1 < n) {
        if (*in == '%' && hexval((unsigned char)in[1]) >= 0
                       && hexval((unsigned char)in[2]) >= 0) {
            out[o++] = (char)(hexval((unsigned char)in[1]) * 16
                            + hexval((unsigned char)in[2]));
            in += 3;
        } else if (*in == '+') {
            out[o++] = ' ';
            in++;
        } else {
            out[o++] = *in++;
        }
    }
    out[o] = '\0';
}

/* Copy the value of the `host` parameter out of a query string into `out`.
 * Returns 1 when the parameter was present, 0 when it was not. */
static int param_host(const char *qs, char *out, size_t n)
{
    const char *p = qs;
    while (p && *p) {
        if (strncmp(p, "host=", 5) == 0) {
            const char *v = p + 5;
            const char *end = strchr(v, '&');
            size_t len = end ? (size_t)(end - v) : strlen(v);
            char raw[CMD_MAX];
            if (len >= sizeof raw) len = sizeof raw - 1;
            memcpy(raw, v, len);
            raw[len] = '\0';
            url_decode(raw, out, n);
            return 1;
        }
        p = strchr(p, '&');
        if (p) p++;
    }
    return 0;
}

int main(void)
{
    const char *qs = getenv("QUERY_STRING");
    char host[HOST_MAX];
    char cmd[CMD_MAX];
    FILE *fp;
    int c;

    printf("Content-Type: text/plain\r\n\r\n");
    printf("appliance diagnostics -- reachability check\r\n");

    if (!qs || !param_host(qs, host, sizeof host) || host[0] == '\0') {
        printf("usage: /cgi-bin/diag.cgi?host=<name or address>\r\n");
        return 0;
    }

    printf("target: %s\r\n\r\n", host);
    fflush(stdout);

    /* ------------------------------------------------------------------ *
     * THE BUG. `host` is caller-controlled and goes into the command
     * string unquoted, and popen(3) runs that string with /bin/sh -c.
     * ------------------------------------------------------------------ */
    snprintf(cmd, sizeof cmd, "ping -c 1 -W 1 %s 2>&1", host);

    fp = popen(cmd, "r");
    if (!fp) {
        printf("could not run the reachability check\r\n");
        return 0;
    }
    while ((c = fgetc(fp)) != EOF) putchar(c);
    pclose(fp);

    return 0;
}
