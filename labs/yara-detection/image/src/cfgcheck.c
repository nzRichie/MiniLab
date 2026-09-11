/* Benign, and the corpus's string mimic: a triage helper that reads a text file
 * and prints any line carrying a known beacon configuration tag. It therefore
 * contains the family's tag as a literal, in the same way a signature file
 * contains the strings it looks for. It imports KERNEL32 and the C runtime and
 * nothing else, so nothing but the string connects it to the family. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char *tags[] = {
    "NJCFG3|c2=",
    "BEACONCFG1|",
    "XCFG2|host=",
    NULL
};

int main(int argc, char **argv)
{
    FILE *f = fopen(argc > 1 ? argv[1] : "capture.txt", "r");
    char line[2048];
    int hits = 0, i;
    if (!f) { fprintf(stderr, "cfgcheck: cannot open\n"); return 1; }
    printf("cfgcheck: %d tags loaded\n", 3);
    while (fgets(line, sizeof line, f))
        for (i = 0; tags[i]; i++)
            if (strstr(line, tags[i])) { fputs(line, stdout); hits++; break; }
    fclose(f);
    printf("cfgcheck: %d line(s) matched\n", hits);
    return hits ? 0 : 1;
}
