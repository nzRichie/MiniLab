/* Benign: prints the Windows version the process is running under. */
#include <windows.h>
#include <stdio.h>
int main(void)
{
    OSVERSIONINFOEXA vi;
    ZeroMemory(&vi, sizeof vi);
    vi.dwOSVersionInfoSize = sizeof vi;
    if (!GetVersionExA((OSVERSIONINFOA *)&vi)) return 1;
    printf("%lu.%lu build %lu\n", (unsigned long)vi.dwMajorVersion,
           (unsigned long)vi.dwMinorVersion, (unsigned long)vi.dwBuildNumber);
    return 0;
}
