/* Benign: prints the names and sizes of the files matching a pattern. */
#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(argc > 1 ? argv[1] : "*", &fd);
    if (h == INVALID_HANDLE_VALUE) { fprintf(stderr, "dirlist: no match\n"); return 1; }
    do {
        printf("%-40s %10lu\n", fd.cFileName, (unsigned long)fd.nFileSizeLow);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    return 0;
}
