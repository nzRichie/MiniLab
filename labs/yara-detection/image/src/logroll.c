/* Benign: renames a log file out of the way and starts a new empty one. */
#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "service.log";
    char old[MAX_PATH];
    HANDLE h;
    wsprintfA(old, "%s.1", path);
    DeleteFileA(old);
    if (!MoveFileExA(path, old, MOVEFILE_REPLACE_EXISTING)) {
        fprintf(stderr, "logroll: rename failed (%lu)\n", (unsigned long)GetLastError());
        return 1;
    }
    h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return 1;
    CloseHandle(h);
    printf("rolled %s -> %s\n", path, old);
    return 0;
}
