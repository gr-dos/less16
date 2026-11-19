#!/bin/sh
#
# Test less.exe under DOSBox-X emulating an 8086 (cputype=8086,
# core=normal), so an instruction from a later CPU is an illegal opcode.
#
# One batch file runs every DOS-side step, and the results are checked
# on the host afterwards.  Each step N records the exit status in RN.TXT
# and standard output in ON.TXT.  DOS cannot redirect standard error, so
# diagnostics are not checked.  rc.bat uses goto rather than
# "if errorlevel N echo ... >file" because the DOSBox-X shell opens the
# redirection even when the test is false.
#
# Only non-interactive behavior is covered here; see docs/DESIGN.md §8
# for the interactive test plan.
#
# To add a test: add a step to steps.bat (command, then "call rc N")
# and the matching rc/expect/check lines below.
#
# Usage: tests/run.sh [path/to/less.exe]
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/less.exe}
DOSBOX=${DOSBOX:-dosbox-x}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
[ -f "$exe" ] || { echo "$exe not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/dosless.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
cp "$exe" less.exe

# a.txt: 30 CRLF lines.  b.txt: a tab, a 109-column line, LF-only and
# CR-only line ends, a control byte and a final Ctrl+Z.  e.txt: empty.
# big.txt: 10000 lines (254 KB).  crlf.txt: a CRLF split across the
# 4 KiB block boundary.  long.txt: a 70000-byte line.
i=1
while [ $i -le 30 ]; do printf 'line %d\r\n' $i; i=$((i + 1)); done > a.txt
x=$(printf '%100s' '' | tr ' ' x)
printf 'tab\there\r\nlong %s end\nlf only\rcr only\r\n\001ctl\032' "$x" > b.txt
: > e.txt
awk 'BEGIN { for (i = 1; i <= 10000; i++)
    printf "line %05d %s\r\n", i, substr("abcdefghijklmnopqrstuvwxyz", 1, i % 27) }' > big.txt
{ head -c 4095 /dev/zero | tr '\0' a; printf '\r\nnext\r\nafter\r\n'; } > crlf.txt
{ head -c 70000 /dev/zero | tr '\0' y; printf '\nEND\n'; } > long.txt
# mixed.txt: 3000 lines ending LF, CR, CRLF in turn (ends fall on every
# position relative to the block boundaries)
awk 'BEGIN { e[0] = "\n"; e[1] = "\r"; e[2] = "\r\n";
    for (i = 1; i <= 3000; i++) printf "m %04d%s", i, e[i % 3] }' > mixed.txt

# r.txt: CRLF, LF and CR line ends at known offsets, for byte ranges:
#   aaa 0-2, CRLF 3-4, bbb 5-7, CRLF 8-9, ccc 10-12, LF 13,
#   ddd 14-16, CR 17, eee 18-20, CRLF 21-22 (23 bytes)
printf 'aaa\r\nbbb\r\nccc\nddd\reee\r\n' > r.txt
# big.txt ranges: from 5 bytes into line 5000 (past 64 KiB) to 4 bytes
# into line 7000; b.txt's last 4 bytes end in a Ctrl+Z
big5000=$(($(head -n 4999 big.txt | wc -c) + 5))
big7000=$(($(head -n 6999 big.txt | wc -c) + 4))
btail=$(($(wc -c < b.txt) - 4))

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOS

cat > steps.bat <<'EOS'
@echo off
rem --- help
less --help >o1.txt
call rc 1
less -h >o2.txt
call rc 2
less -? >o3.txt
call rc 3
less /? >o4.txt
call rc 4
less --HELP >o5.txt
call rc 5
rem --- version
less --version >o6.txt
call rc 6
rem --- usage errors
less --bogus >o7.txt
call rc 7
less /x >o8.txt
call rc 8
less a.txt b.txt >o9.txt
call rc 9
rem --- no filename, stdin is the console
less >o10.txt
call rc 10
rem --- viewer, driven by the hidden test mode
less --test-screen=40x6 --test-keys=.D.N.E.P.H. a.txt >o11.txt
call rc 11
less --test-screen=40x6 --test-keys=.DD.W.RRR.LL.W. b.txt >o12.txt
call rc 12
less --test-screen=40x4 --test-keys=.E. e.txt >o13.txt
call rc 13
type a.txt | less --test-screen=40x4 --test-keys=.E. >o14.txt
call rc 14
less --test-screen=40x4 --test-keys=.N. <a.txt >o15.txt
call rc 15
less --test-screen=40x4 --test-keys=.E.PP.U.H.N. big.txt >o16.txt
call rc 16
less -S --test-screen=40x5 --test-keys=. crlf.txt >o17.txt
call rc 17
less /s --test-screen=40x4 --test-keys=RRRRRRRRRR.E.R.LLLLLLLLLLL. long.txt >o18.txt
call rc 18
less --test-screen=40x4 --test-keys=E. long.txt >o19.txt
call rc 19
less --test-screen=40x4 --test-keys=E.PPPPPPPPPP. mixed.txt >o28.txt
call rc 28
rem --- key aliases: Space and Ctrl+V page down, Ctrl+Y pages up
less --test-screen=40x6 --test-keys=.N.N.P. a.txt >o29.txt
call rc 29
less --test-screen=40x6 --test-keys=.#32.#22.#25. a.txt >o30.txt
call rc 30
rem --- input errors
less missing.txt >o20.txt
call rc 20
less --test-screen=10x4 a.txt >o21.txt
call rc 21
rem --- non-seekable stdin (a device) needs a scratch file in TEMP/TMP
set TEMP=
set TMP=
less --test-keys=. <NUL >o22.txt
call rc 22
set TEMP=C:\NOSUCH
less --test-keys=. <NUL >o23.txt
call rc 23
mkdir scratch
set TEMP=C:\SCRATCH
less --test-screen=40x4 --test-keys=. <NUL >o24.txt
call rc 24
dir /b scratch >o25.txt
EOS

# byte ranges (--start, --end, --length) and --label
cat >> steps.bat <<EOS
less --test-screen=40x4 --test-keys=. --start=5 --end=10 r.txt >o31.txt
call rc 31
less --test-screen=40x4 --test-keys=.E. --start=5 --length=0 r.txt >o32.txt
call rc 32
less --test-screen=40x4 --test-keys=. --start=6 --length=1 r.txt >o33.txt
call rc 33
less --test-screen=40x4 --test-keys=. --start=4 --end=9 r.txt >o34.txt
call rc 34
less --test-screen=40x4 --test-keys=. --start=1 --end=12 r.txt >o35.txt
call rc 35
less --test-screen=40x4 --test-keys=. --start=11 r.txt >o36.txt
call rc 36
less --test-screen=40x4 --test-keys=. --start=14 --end=18 r.txt >o37.txt
call rc 37
less --test-screen=40x4 --test-keys=. --start=23 r.txt >o38.txt
call rc 38
less --test-screen=40x4 --test-keys=.E.PP.U.H.UP.N. --start=$big5000 --end=$big7000 big.txt >o39.txt
call rc 39
less -S --test-screen=40x4 --test-keys=.RR.W. --start=69990 --end=70004 --label=Topic long.txt >o40.txt
call rc 40
less --test-screen=40x4 --test-keys=. --start=$btail b.txt >o41.txt
call rc 41
less --start=5 --end=4 r.txt >o42.txt
call rc 42
less --end=5 --length=1 r.txt >o43.txt
call rc 43
type r.txt | less --start=1 >o44.txt
call rc 44
less --start=24 r.txt >o45.txt
call rc 45
less --end=24 r.txt >o46.txt
call rc 46
less --start=x r.txt >o47.txt
call rc 47
less --start=2147483648 r.txt >o48.txt
call rc 48
less --start=2147483647 --length=1 r.txt >o49.txt
call rc 49
less --start=0 NUL >o50.txt
call rc 50
less --length=1 missing.txt >o51.txt
call rc 51
less --label=My.Label --test-screen=40x4 --test-keys=. <a.txt >o52.txt
call rc 52
EOS

# Smoke test of the real BIOS keyboard and video path: AUTOTYPE feeds
# the keys (keypad kp_3/kp_9 for PgDn/PgUp: DOSBox-X's "pagedown" drops
# the key after it), and the program must quit with status 0.
cat > smoke.bat <<'EOS'
@echo off
autotype -w 1.5 -p 0.2 down kp_3 end home kp_9 up right w left w q
less big.txt >o26.txt
call rc 26
autotype -w 1.5 -p 0.2 kp_3 esc
type a.txt | less >o27.txt
call rc 27
EOS

# dosbox BATCH SECONDS: run BATCH in a headless DOSBox-X emulating an
# 8086
dosbox() {
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout -k 10 "$2" \
        "$DOSBOX" -defaultconf -silent -nogui -nomenu \
        -set "cputype=8086" -set "core=normal" -set "cpu cycles=max" \
        -c "mount c \"$work\"" -c "c:" \
        -c "$1" -c "exit" >>dosbox.log 2>&1
}

dosbox steps.bat 300

# AUTOTYPE in headless DOSBox-X now and then loses its keys entirely
# (the same keys through --test-keys never hang), so a hung smoke run
# is retried; three hangs in a row fail the steps.
for try in 1 2 3; do
    rm -f R26.TXT R27.TXT O26.TXT O27.TXT
    dosbox smoke.bat 30
    [ -f R26.TXT ] && [ -f R27.TXT ] && break
    echo "note: AUTOTYPE smoke run $try hung"
done

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect STEP < expected-lines; compares ON.TXT with CRs removed
expect() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# help
rc 1 0
check "step 1: help" grep -q '^Usage: less' O1.TXT
for n in 2 3 4 5; do
    rc $n 0
    check "step $n: same help as --help" cmp -s O1.TXT "O$n.TXT"
done

# version
rc 6 0
expect 6 <<EOS
less (dos-less16) $(cat "$top/VERSION")
EOS

# usage errors: status 1, nothing on standard output
for n in 7 8 9 10; do
    rc $n 1
    expect $n < /dev/null
done

# viewer: navigation (Down, PgDn with one row of overlap, End, PgUp,
# Home) on a 5-row content area
rc 11 0
expect 11 <<'EOS'
line 1
line 2
line 3
line 4
line 5
 a.txt  Line 1  WRAP
--
line 2
line 3
line 4
line 5
line 6
 a.txt  Line 2  WRAP
--
line 6
line 7
line 8
line 9
line 10
 a.txt  Line 6  WRAP
--
line 26
line 27
line 28
line 29
line 30
 a.txt  Line 26/30  WRAP  (END)
--
line 22
line 23
line 24
line 25
line 26
 a.txt  Line 22/30  WRAP
--
line 1
line 2
line 3
line 4
line 5
 a.txt  Line 1/30  WRAP
--
EOS

# tabs, wrapping, line ends, control bytes, final Ctrl+Z; Down by
# display rows, wrap toggle, horizontal scroll clamped to the widest
# line on screen (109 - 40 = 69)
rc 12 0
expect 12 <<EOS
tab     here
long xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxx end
lf only
 b.txt  Line 1  WRAP
--
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxx end
lf only
cr only
.ctl
 b.txt  Line 2/5  WRAP  (END)
--
tab     here
long xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
lf only
cr only
.ctl
 b.txt  Line 1/5  NOWRAP  (END)
--

xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx



 b.txt  Line 1/5  NOWRAP  Col 25  (END)
--
here
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx



 b.txt  Line 1/5  NOWRAP  Col 9  (END)
--
tab     here
long xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxx end
lf only
 b.txt  Line 1/5  WRAP
--
EOS

# empty input
rc 13 0
expect 13 <<'EOS'



 e.txt  Line 0/0  WRAP  (END)
--



 e.txt  Line 0/0  WRAP  (END)
--
EOS

# piped and redirected standard input
rc 14 0
expect 14 <<'EOS'
line 1
line 2
line 3
 [stdin]  Line 1  WRAP
--
line 28
line 29
line 30
 [stdin]  Line 28/30  WRAP  (END)
--
EOS
rc 15 0
expect 15 <<'EOS'
line 1
line 2
line 3
 [stdin]  Line 1  WRAP
--
line 3
line 4
line 5
 [stdin]  Line 3  WRAP
--
EOS

# larger than 64 KiB: End, back through the sparse index, Home
rc 16 0
expect 16 <<'EOS'
line 00001 a
line 00002 ab
line 00003 abc
 big.txt  Line 1  WRAP
--
line 09998 abcdefgh
line 09999 abcdefghi
line 10000 abcdefghij
 big.txt  Line 9998/10000  WRAP  (END)
--
line 09994 abcd
line 09995 abcde
line 09996 abcdef
 big.txt  Line 9994/10000  WRAP
--
line 09993 abc
line 09994 abcd
line 09995 abcde
 big.txt  Line 9993/10000  WRAP
--
line 00001 a
line 00002 ab
line 00003 abc
 big.txt  Line 1/10000  WRAP
--
line 00003 abc
line 00004 abcd
line 00005 abcde
 big.txt  Line 3/10000  WRAP
--
EOS

# CRLF split across a read-block boundary is one line end
rc 17 0
expect 17 <<'EOS'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
next
after

 crlf.txt  Line 1/3  NOWRAP  (END)
--
EOS

# a 70000-byte line: horizontal scroll, and wrapped to its last rows
rc 18 0
expect 18 <<'EOS'
yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy


 <g.txt  Line 1/2  NOWRAP  Col 81  (END)
--
yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy


 <g.txt  Line 1/2  NOWRAP  Col 81  (END)
--
yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy


 <g.txt  Line 1/2  NOWRAP  Col 89  (END)
--
yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
END

 long.txt  Line 1/2  NOWRAP  (END)
--
EOS
rc 19 0
expect 19 <<'EOS'
yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
END
 long.txt  Line 1/2  WRAP  (END)
--
EOS

# mixed line ends through the indexing fast path
rc 28 0
expect 28 <<'EOS'
m 2998
m 2999
m 3000
 mixed.txt  Line 2998/3000  WRAP  (END)
--
m 2978
m 2979
m 2980
 mixed.txt  Line 2978/3000  WRAP
--
EOS

# key aliases behave exactly like PgDn and PgUp
rc 29 0
rc 30 0
check "step 29: paged" grep -q 'Line 9 ' O29.TXT
check "step 30: Space, Ctrl+V, Ctrl+Y same as PgDn, PgDn, PgUp" \
    cmp -s O29.TXT O30.TXT

# input errors
rc 20 2
expect 20 < /dev/null
rc 21 1
expect 21 < /dev/null

# non-seekable stdin: no TEMP/TMP, or an unusable one, is an error;
# with one, the input is spooled and the scratch file removed
rc 22 2
expect 22 < /dev/null
rc 23 2
expect 23 < /dev/null
rc 24 0
expect 24 <<'EOS'



 [stdin]  Line 0/0  WRAP  (END)
--
EOS
expect 25 < /dev/null

# byte ranges: exactly the bytes from --start up to --end (or
# --start + --length), viewed as a whole file; a range may start or end
# mid-line or between the CR and LF of a CRLF
rc 31 0
expect 31 <<'EOS'
bbb


 r.txt  Line 1/1  WRAP  (END)
--
EOS
# empty range, and End in it
rc 32 0
expect 32 <<'EOS'



 r.txt  Line 0/0  WRAP  (END)
--



 r.txt  Line 0/0  WRAP  (END)
--
EOS
# one byte
rc 33 0
expect 33 <<'EOS'
b


 r.txt  Line 1/1  WRAP  (END)
--
EOS
# starts on the LF of a CRLF (an empty line), ends on a CR
rc 34 0
expect 34 <<'EOS'

bbb

 r.txt  Line 1/2  WRAP  (END)
--
EOS
# starts and ends mid-line
rc 35 0
expect 35 <<'EOS'
aa
bbb
cc
 r.txt  Line 1/3  WRAP  (END)
--
EOS
# --start alone runs to the end of the file
rc 36 0
expect 36 <<'EOS'
cc
ddd
eee
 r.txt  Line 1/3  WRAP  (END)
--
EOS
# ends on a bare CR
rc 37 0
expect 37 <<'EOS'
ddd


 r.txt  Line 1/1  WRAP  (END)
--
EOS
# starts at the end of the file: empty
rc 38 0
expect 38 <<'EOS'



 r.txt  Line 0/0  WRAP  (END)
--
EOS
# past 64 KiB, mid-line at both ends: End, PgUp, Up, Home, then Up
# and PgUp stay at the range's start, PgDn
rc 39 0
expect 39 <<'EOS'
05000 abcde
line 05001 abcdef
line 05002 abcdefg
 big.txt  Line 1  WRAP
--
line 06998 abcde
line 06999 abcdef
line
 big.txt  Line 1999/2001  WRAP  (END)
--
line 06994 a
line 06995 ab
line 06996 abc
 big.txt  Line 1995/2001  WRAP
--
line 06993
line 06994 a
line 06995 ab
 big.txt  Line 1994/2001  WRAP
--
05000 abcde
line 05001 abcdef
line 05002 abcdefg
 big.txt  Line 1/2001  WRAP
--
05000 abcde
line 05001 abcdef
line 05002 abcdefg
 big.txt  Line 1/2001  WRAP
--
line 05002 abcdefg
line 05003 abcdefgh
line 05004 abcdefghi
 big.txt  Line 3/2001  WRAP
--
EOS
# -S with a range: Right is clamped to the range's widest line; W;
# --label replaces the file name
rc 40 0
expect 40 <<'EOS'
yyyyyyyyyy
END

 Topic  Line 1/2  NOWRAP  (END)
--
yyyyyyyyyy
END

 Topic  Line 1/2  NOWRAP  (END)
--
yyyyyyyyyy
END

 Topic  Line 1/2  WRAP  (END)
--
EOS
# a final Ctrl+Z of the range is dropped, as for a whole file
rc 41 0
expect 41 <<'EOS'
ctl


 b.txt  Line 1/1  WRAP  (END)
--
EOS
# range usage errors: end before start, --end with --length, no
# filename, not a number, too large, start + length overflows
for n in 42 43 44 47 48 49; do
    rc $n 1
    expect $n < /dev/null
done
# range input errors: start or end past the end of the file, a device,
# a missing file
for n in 45 46 50 51; do
    rc $n 2
    expect $n < /dev/null
done
# --label for standard input, case kept
rc 52 0
expect 52 <<'EOS'
line 1
line 2
line 3
 My.Label  Line 1  WRAP
--
EOS

# interactive smoke test: quits normally, nothing on standard output
rc 26 0
expect 26 < /dev/null
rc 27 0
expect 27 < /dev/null

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
