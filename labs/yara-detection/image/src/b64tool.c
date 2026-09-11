/* Benign: base64-encodes a file with CryptBinaryToStringA. This is the corpus's
 * CRYPT32 mimic: it imports the same library the family uses to encode its
 * configuration block, and it opens no network connection at all. */
#include <windows.h>
#include <wincrypt.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    HANDLE f = CreateFileA(argc > 1 ? argv[1] : "input.bin", GENERIC_READ,
                           FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    BYTE buf[3072];
    char out[8192];
    DWORD n = 0, outn;
    if (f == INVALID_HANDLE_VALUE) return 1;
    while (ReadFile(f, buf, sizeof buf, &n, NULL) && n) {
        outn = sizeof out;
        if (!CryptBinaryToStringA(buf, n, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, out, &outn))
            { CloseHandle(f); return 1; }
        fwrite(out, 1, outn, stdout);
    }
    printf("\n");
    CloseHandle(f);
    return 0;
}
