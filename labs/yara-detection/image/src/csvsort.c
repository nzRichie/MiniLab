/* Benign: reads lines from a file and prints them in order. C runtime only. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int cmp(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
int main(int argc, char **argv)
{
    FILE *f = fopen(argc > 1 ? argv[1] : "input.csv", "r");
    char *lines[4096], line[1024];
    int n = 0, i;
    if (!f) { fprintf(stderr, "csvsort: cannot open\n"); return 1; }
    while (n < 4096 && fgets(line, sizeof line, f)) lines[n++] = _strdup(line);
    fclose(f);
    qsort(lines, (size_t)n, sizeof lines[0], cmp);
    for (i = 0; i < n; i++) { fputs(lines[i], stdout); free(lines[i]); }
    return 0;
}
