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
EOS

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cputype=8086" -set "core=normal" -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

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

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
