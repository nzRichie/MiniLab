/* Benign: expands tabs to spaces on standard output. Imports nothing but
 * KERNEL32 and the C runtime, so it is the corpus's plainest file. */
#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    HANDLE h = CreateFileA(argc > 1 ? argv[1] : "input.txt", GENERIC_READ,
                           FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    char buf[4096];
    DWORD n = 0;
    if (h == INVALID_HANDLE_VALUE) { fprintf(stderr, "textutil: cannot open\n"); return 1; }
    while (ReadFile(h, buf, sizeof buf, &n, NULL) && n) {
        DWORD i;
        for (i = 0; i < n; i++) if (buf[i] == '\t') buf[i] = ' ';
        fwrite(buf, 1, n, stdout);
    }
    CloseHandle(h);
    return 0;
}
