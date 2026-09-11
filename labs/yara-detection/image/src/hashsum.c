/* Benign: SHA-256 of a file through the CryptoAPI. The Crypt* calls it makes
 * live in ADVAPI32, not CRYPT32, which is why this file is not a mimic for the
 * family's cryptography import even though it is the corpus's hashing tool. */
#include <windows.h>
#include <wincrypt.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    HCRYPTPROV p; HCRYPTHASH h; HANDLE f;
    BYTE buf[4096], digest[32];
    DWORD n = 0, dn = sizeof digest, i;
    if (!CryptAcquireContextA(&p, NULL, NULL, PROV_RSA_AES, CRYPT_VERIFYCONTEXT)) return 1;
    if (!CryptCreateHash(p, CALG_SHA_256, 0, 0, &h)) return 1;
    f = CreateFileA(argc > 1 ? argv[1] : "input.bin", GENERIC_READ, FILE_SHARE_READ,
                    NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return 1;
    while (ReadFile(f, buf, sizeof buf, &n, NULL) && n) CryptHashData(h, buf, n, 0);
    CryptGetHashParam(h, HP_HASHVAL, digest, &dn, 0);
    for (i = 0; i < dn; i++) printf("%02x", digest[i]);
    printf("\n");
    CloseHandle(f); CryptDestroyHash(h); CryptReleaseContext(p, 0);
    return 0;
}
