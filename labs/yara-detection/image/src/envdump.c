/* Benign: prints the process environment block one variable per line. */
#include <windows.h>
#include <stdio.h>
int main(void)
{
    LPCH env = GetEnvironmentStringsA(), p;
    if (!env) return 1;
    for (p = env; *p; p += lstrlenA(p) + 1) printf("%s\n", p);
    FreeEnvironmentStringsA(env);
    return 0;
}
