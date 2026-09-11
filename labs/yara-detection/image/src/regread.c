/* Benign: reads one string value out of HKLM and prints it. ADVAPI32. */
#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    HKEY k;
    char val[512];
    DWORD n = sizeof val, type = 0;
    const char *path = argc > 1 ? argv[1] : "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
    const char *name = argc > 2 ? argv[2] : "ProductName";
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, &k) != ERROR_SUCCESS) return 1;
    if (RegQueryValueExA(k, name, NULL, &type, (LPBYTE)val, &n) != ERROR_SUCCESS) { RegCloseKey(k); return 1; }
    RegCloseKey(k);
    printf("%s\n", val);
    return 0;
}
