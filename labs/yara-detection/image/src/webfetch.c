/* Benign: downloads a URL to standard output. This is the corpus's WININET
 * mimic: it imports the same library the family beacons over, for the reason
 * the library exists. */
#include <windows.h>
#include <wininet.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    HINTERNET s, u;
    char buf[4096];
    DWORD n = 0;
    s = InternetOpenA("SiteUpdater/2.1", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!s) return 1;
    u = InternetOpenUrlA(s, argc > 1 ? argv[1] : "http://updates.example.net/latest.txt",
                         NULL, 0, INTERNET_FLAG_RELOAD, 0);
    if (!u) { InternetCloseHandle(s); return 1; }
    while (InternetReadFile(u, buf, sizeof buf, &n) && n) fwrite(buf, 1, n, stdout);
    InternetCloseHandle(u);
    InternetCloseHandle(s);
    return 0;
}
