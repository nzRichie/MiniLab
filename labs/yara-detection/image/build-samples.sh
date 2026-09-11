#!/bin/sh
# Builds every sample in the lab from the C sources in src/.
#
# It runs inside the image build and writes nothing to the host filesystem, so
# no PE that imports WININET and is compressed with UPX ever lands on a
# university machine's disk where its antivirus would quarantine it. Nothing
# here is downloaded and nothing here is real malware: every file is compiled
# by x86_64-w64-mingw32-gcc from a source in src/, so every property the
# handout quotes about a sample is a property of that exact build.
#
# Output:
#   /out/corpus/set-a   the unpacked corpus Part 1 works on
#   /out/corpus/set-b   the packed builds and the benign files Part 2 adds
#   /out/holdout        the ten files Part 3 is scored against
#   /out/uploads        the two files the client posts to the scanner in Part 4
#
# Family builds are named nightjar-NN.exe and benign ones bn-NN.exe, which is
# the corpus's ground truth: this lab hands the labels over, because what it
# grades is the rule and not the triage. The holdout is named hs-NN.exe with no
# label in the name, and its answer sits in /srv/holdout/.truth inside the
# holdout container, which is the only container that reads it.
set -eu

SRC=/src
OUT=/out
CC=x86_64-w64-mingw32-gcc
WINDRES=x86_64-w64-mingw32-windres

mkdir -p "$OUT/corpus/set-a" "$OUT/corpus/set-b" "$OUT/holdout" "$OUT/uploads"

# ---------------------------------------------------------------------------
# The family's configuration blocks. Every one of them opens with the same ten
# bytes, NJCFG3|c2=, and differs after that in the C2 address, the build tag
# and the key. That split is what Part 3 turns on: a rule keyed on a whole
# configuration block matches one build, and a rule keyed on the tag matches
# every build including the ones in the holdout.
M1='NJCFG3|c2=126.9.0.40:8443|id=WKS-01|k=7f2a1c'
M2='NJCFG3|c2=126.9.0.40:8443|id=WKS-04|k=1d9e05'
M3='NJCFG3|c2=126.9.0.91:443|id=SRV-02|k=aa41b7'
M4='NJCFG3|c2=126.9.0.77:8080|id=LAP-11|k=c0ff3e'
M5='NJCFG3|c2=126.9.0.77:8080|id=LAP-19|k=44de10'
M6='NJCFG3|c2=126.9.0.12:9443|id=DC-03|k=90ab55'
M7='NJCFG3|c2=126.9.0.40:8443|id=FIN-08|k=2b7c91'

# build_family <out.exe> <marker> <host> <port> <where: data|resource> <flags...>
build_family() {
    out=$1; marker=$2; host=$3; port=$4; where=$5
    shift 5
    if [ "$where" = resource ]; then
        # windres compiles the configuration block into an RCDATA resource, so
        # the build gains a .rsrc section and the string is nowhere near .data.
        printf '#include <windows.h>\n1 RCDATA\n{\n  "%s\\0"\n}\n' "$marker" > /tmp/njcfg.rc
        $WINDRES /tmp/njcfg.rc -O coff -o /tmp/njcfg.o
        $CC "$@" -DNJ_CFG_IN_RESOURCE -DNJ_HOST="\"$host\"" -DNJ_PORT="$port" \
            -o "$out" "$SRC/nightjar.c" /tmp/njcfg.o -lwininet -lcrypt32
        rm -f /tmp/njcfg.rc /tmp/njcfg.o
    else
        $CC "$@" -DNJ_CFG="\"$marker\"" -DNJ_HOST="\"$host\"" -DNJ_PORT="$port" \
            -o "$out" "$SRC/nightjar.c" -lwininet -lcrypt32
    fi
}

# build_benign <out.exe> <source stem> <libs> <flags...>
build_benign() {
    out=$1; stem=$2; libs=$3
    shift 3
    # shellcheck disable=SC2086
    $CC "$@" -o "$out" "$SRC/$stem.c" $libs
}

pack() { upx -9 -q "$1" >/dev/null 2>&1 || { echo "upx failed on $1" >&2; exit 1; }; }

A="$OUT/corpus/set-a"
B="$OUT/corpus/set-b"
H="$OUT/holdout"
U="$OUT/uploads"

# ---------------------------------------------------------------------------
# set-a: the unpacked corpus. Five family builds and fifteen benign ones.
build_family "$A/nightjar-01.exe" "$M1" 126.9.0.40 8443 data     -O0
build_family "$A/nightjar-02.exe" "$M1" 126.9.0.40 8443 data     -O2 -s
build_family "$A/nightjar-03.exe" "$M2" 126.9.0.40 8443 resource -O2
build_family "$A/nightjar-04.exe" "$M3" 126.9.0.91 443  data     -Os
build_family "$A/nightjar-05.exe" "$M2" 126.9.0.40 8443 data     -O2

build_benign "$A/bn-01.exe" textutil ""          -O0
build_benign "$A/bn-02.exe" textutil ""          -O2 -s
build_benign "$A/bn-03.exe" dirlist  ""          -O0
build_benign "$A/bn-04.exe" dirlist  ""          -O2 -s
build_benign "$A/bn-05.exe" svcping  "-lws2_32"  -O2
build_benign "$A/bn-06.exe" regread  "-ladvapi32" -O0
build_benign "$A/bn-07.exe" hashsum  "-ladvapi32" -O2
build_benign "$A/bn-08.exe" b64tool  "-lcrypt32" -O0
build_benign "$A/bn-09.exe" b64tool  "-lcrypt32" -O2 -s
build_benign "$A/bn-10.exe" webfetch "-lwininet" -O0
build_benign "$A/bn-11.exe" webfetch "-lwininet" -O2 -s
build_benign "$A/bn-12.exe" envdump  ""          -O2
build_benign "$A/bn-13.exe" csvsort  ""          -O0
build_benign "$A/bn-14.exe" logroll  ""          -O2 -s
build_benign "$A/bn-15.exe" winver   ""          -O0

# ---------------------------------------------------------------------------
# set-b: what Part 2 adds. Three packed family builds, and seven more benign
# files of which two are packed. bn-22 is packed AND imports WININET, so a rule
# that asks for the WinInet import and a UPX section name has a false positive
# waiting for it in this directory.
build_family "$B/nightjar-06.exe" "$M1" 126.9.0.40 8443 data     -O0
build_family "$B/nightjar-07.exe" "$M2" 126.9.0.40 8443 resource -O2
build_family "$B/nightjar-08.exe" "$M3" 126.9.0.91 443  data     -O2 -s
pack "$B/nightjar-06.exe"
pack "$B/nightjar-07.exe"
pack "$B/nightjar-08.exe"

build_benign "$B/bn-16.exe" textutil ""          -Os
build_benign "$B/bn-17.exe" dirlist  ""          -O2
build_benign "$B/bn-18.exe" svcping  "-lws2_32"  -O0 -s
build_benign "$B/bn-19.exe" csvsort  ""          -O2 -s
build_benign "$B/bn-20.exe" winver   ""          -O2 -s
build_benign "$B/bn-21.exe" textutil ""          -O2
build_benign "$B/bn-22.exe" webfetch "-lwininet" -O2
pack "$B/bn-21.exe"
pack "$B/bn-22.exe"

# ---------------------------------------------------------------------------
# The holdout. Three family builds carrying configuration blocks that appear in
# no file the learner can read, and seven benign files, each one aimed at a
# rule that would pass the corpus:
#
#   hs-01  licchk    imports WININET and CRYPT32, for its own reasons
#   hs-03  webfetch  imports WININET
#   hs-04  dirlist   packed
#   hs-06  cfgcheck  carries the family's tag as a literal string
#   hs-07  b64tool   imports CRYPT32
#   hs-09  hashsum   a stock eighteen-section mingw build
#   hs-10  webfetch  imports WININET and is packed
build_benign "$H/hs-01.exe" licchk   "-lwininet -lcrypt32" -O2
build_family "$H/hs-02.exe" "$M4" 126.9.0.77 8080 data     -O2
build_benign "$H/hs-03.exe" webfetch "-lwininet" -O0
build_benign "$H/hs-04.exe" dirlist  ""          -O2
build_family "$H/hs-05.exe" "$M5" 126.9.0.77 8080 data     -O0
build_benign "$H/hs-06.exe" cfgcheck ""          -O2
build_benign "$H/hs-07.exe" b64tool  "-lcrypt32" -O2
build_family "$H/hs-08.exe" "$M6" 126.9.0.12 9443 resource -O2
build_benign "$H/hs-09.exe" hashsum  "-ladvapi32" -O0
build_benign "$H/hs-10.exe" webfetch "-lwininet" -O2
pack "$H/hs-05.exe"
pack "$H/hs-04.exe"
pack "$H/hs-10.exe"
printf 'hs-02.exe\nhs-05.exe\nhs-08.exe\n' > "$H/.truth"

# ---------------------------------------------------------------------------
# The two files the client posts to the scanner in Part 4. invoice-viewer is a
# packed family build; logtag-check is the benign triage helper that carries
# the family's tag as a literal, which is what stops a rule keyed on the tag
# alone from passing this stage.
build_family "$U/invoice-viewer.exe" "$M7" 126.9.0.40 8443 data -O2
pack "$U/invoice-viewer.exe"
build_benign "$U/logtag-check.exe" cfgcheck "" -O0

# ---------------------------------------------------------------------------
# Every mode is set explicitly rather than left to the ambient umask: docker
# exec runs with umask 0022 under a rootful daemon and 0000 under a rootless
# one, so a bare mkdir yields 755 on one and 777 on the other. The corpus is
# 0444 because nothing in the lab writes to a sample and a learner who
# accidentally truncates one gets a corpus the handout no longer describes.
find "$OUT" -type d -exec chmod 755 {} +
find "$OUT" -type f -exec chmod 444 {} +
chmod 400 "$H/.truth"

echo "samples built:"
echo "  set-a   $(ls -1 "$A" | wc -l) files"
echo "  set-b   $(ls -1 "$B" | wc -l) files"
echo "  holdout $(ls -1 "$H" | wc -l) files"
echo "  uploads $(ls -1 "$U" | wc -l) files"
