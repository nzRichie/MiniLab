/* Benign, and the sharpest mimic in the lab: a licence checker that base64
 * encodes an installation identifier with CryptBinaryToStringA and posts it to
 * a vendor endpoint over WinInet. It imports both of the libraries the family
 * imports, for its own reasons, and carries no configuration block. A rule
 * built on the import pair alone cannot tell it from the family. */
#include <windows.h>
#include <wininet.h>
#include <wincrypt.h>
#include <stdio.h>

int main(void)
{
    char install_id[64] = "INSTALL-ID:6b21d0f4";
    char encoded[256];
    DWORD encoded_len = sizeof encoded;
    HINTERNET session, conn, req;

    if (!CryptBinaryToStringA((const BYTE *)install_id, (DWORD)lstrlenA(install_id),
                              CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                              encoded, &encoded_len))
        return 1;

    session = InternetOpenA("VendorLicence/4.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!session) return 1;
    conn = InternetConnectA(session, "licence.example.net", INTERNET_DEFAULT_HTTP_PORT,
                            NULL, NULL, INTERNET_SERVICE_HTTP, 0, 0);
    if (conn) {
        req = HttpOpenRequestA(conn, "POST", "/v4/activate", NULL, NULL, NULL, 0, 0);
        if (req && HttpSendRequestA(req, NULL, 0, encoded, encoded_len)) {
            char reply[256];
            DWORD got = 0;
            while (InternetReadFile(req, reply, sizeof reply, &got) && got)
                fwrite(reply, 1, got, stdout);
        }
        if (req) InternetCloseHandle(req);
        InternetCloseHandle(conn);
    }
    InternetCloseHandle(session);
    return 0;
}
