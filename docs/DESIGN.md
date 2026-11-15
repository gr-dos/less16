# less16 — Minimal Full-Screen Pager for DOS

**Status:** Implemented in v0.01 (decisions in §10)
**Implementation language:** Free Pascal
**Executable:** `LESS.EXE` (required output name; verify the compiler/linker produces this filename)
**Target:** GR-DOS / MS-DOS 4.00-compatible real-mode DOS, including 8086/8088 systems
**Scope:** Small, useful, read-only full-screen text pager; not a port of GNU `less`
**Repository template:** [`gr-dos/hello16`](https://github.com/gr-dos/hello16) conventions, adapted for Free Pascal (see §11)

## 1. Purpose

`less16` (distributed as `LESS.EXE`, invoked as `LESS`) provides interactive, full-screen viewing of text files on vintage DOS computers. Unlike `MORE`, it supports moving **backward as well as forward**, one line or one page at a time. In non-wrapping mode, it also scrolls horizontally.

It must support both a named file and standard input:

```dos
LESS AUTOEXEC.BAT
LESS C:\DOS\README.TXT
CAT FOO.TXT | LESS
TYPE FOO.TXT | LESS
LESS < FOO.TXT
```

`CAT` is an example of an external command, not a dependency. The standard DOS `TYPE` command and DOS input redirection must work as well.

This is deliberately **not** a feature-complete clone of Unix `less`. Search, multiple files, marks, color, regular expressions, mouse support, and configurable key bindings are out of scope for the first release.

## 2. Design goals

1. **8086-compatible:** Real-mode DOS executable with no 286+, DOS extender, DPMI, XMS, or EMS requirement.
2. **Small and responsive:** Minimal dependencies and conventional-memory usage; operate on files much larger than available RAM.
3. **Read-only:** Never change the viewed file or user data.
4. **Predictable controls:** Cursor keys and Page Up/Page Down work on ordinary PC-compatible keyboards.
5. **DOS-native I/O:** Accept a filename *or* redirected/piped stdin while taking interactive navigation keys from the keyboard, not from stdin.
6. **Text-mode display:** Full-screen viewer with a compact one-line status/help bar and no graphics-mode requirement.
7. **Incremental design:** Clean separation between input, line layout, navigation, and rendering so features can be added later.

## 3. User interface

### 3.1 Command line

```text
LESS [options] [filename]

Options:
  -w, /W        Wrap long lines (default)
  -S, /S        Do not wrap long lines; enable horizontal scrolling
  -h, -?, /?,
  --help        Display short usage help and exit
  --version     Print "less (dos-less16) VERSION" and exit
```

- `--help` and `--version` are required by the hello16 template conventions. `--version` prints exactly `less (dos-less16) <VERSION>`, where `<VERSION>` is the single line in the `VERSION` file (DOS-style: `0.01`, `0.02`, … `1.00`), compiled into the program at build time. `make test` checks that the output matches `VERSION`.
- `--help`/`--version` exit with status 0. A bad option or operand exits with status 1, as in hello16. Additional nonzero codes for I/O failures are listed in §7.

- Accept **zero or one** filename. With a filename, open that file for reading. Without a filename, read stdin **only if redirected or piped**; otherwise print usage and exit instead of treating navigation keys as file data.
- Recognize DOS drive-qualified and relative/absolute paths. DOS option parsing must not mistake `C:\...` for a switch.
- Reject unknown options and multiple filenames with a useful diagnostic.
- File names containing spaces and multiple input files are deferred; ordinary DOS quoted-argument handling can be investigated later.
- Make option names case-insensitive.

### 3.2 Keyboard controls

| Key | Wrapping enabled | Wrapping disabled |
|---|---|---|
| **Up arrow** | Previous displayed row | Previous logical line |
| **Down arrow** | Next displayed row | Next logical line |
| **Page Up** | One screenful up | One screenful up |
| **Page Down** | One screenful down | One screenful down |
| **Ctrl+Y** | Same as Page Up | Same as Page Up |
| **Space**, **Ctrl+V** | Same as Page Down | Same as Page Down |
| **Left arrow** | No effect | Scroll viewport left |
| **Right arrow** | No effect | Scroll viewport right |
| **Home** | Beginning of input | Beginning of input |
| **End** | End of available input | End of available input |
| **W** | Toggle wrapping off | Toggle wrapping on |
| **Q**, **Esc** | Quit | Quit |

Page navigation should overlap by **one displayed row** so the reader retains context. In non-wrapping mode, Page Up/Down operate on logical lines; when wrapping is enabled, they operate on rendered rows. The left/right scroll increment defaults to **8 columns**, clamped to column zero and the maximum meaningful horizontal offset. Home/End are low-cost conveniences; other keys are deferred.

If input cannot be positioned backward (an exceptional fallback), disable unsupported navigation visibly rather than silently misbehaving.

### 3.3 Screen layout

- Use the current text-mode screen dimensions, normally **80 columns × 25 rows**, without assuming that all hardware is 80-column.
- Use **all but the final row** for file contents; reserve the last row for status and a terse key reminder.
- Suggested status content: filename or `[stdin]`, `WRAP`/`NOWRAP`, top line (and optional line count if known), horizontal column when applicable, and `Q quit`.
- Show a clear end-of-file indicator in the status row when appropriate.
- Do not change video mode, palette, or screen dimensions.
- Save and restore the cursor shape/visibility if changed. A full restoration of the pre-launch screen contents is **not** required in v0.1; on exit leave a clean DOS prompt and sensible cursor state.
- Detect unsupported video environments and exit cleanly. Monochrome MDA and standard CGA/EGA/VGA **text modes** should be considered for testing.

## 4. Text handling

### 4.1 Lines and characters

- Recognize **CRLF** (DOS standard), bare **LF**, and bare **CR** as line endings; treat CRLF as a single break even across read-buffer boundaries.
- Handle files without a trailing newline and empty files.
- Expand tabs to the next **8-column tab stop**, counting virtual display columns.
- Treat input as **single-byte DOS text**, displayed using the active character set/code page. UTF-8 decoding and Unicode are out of scope.
- Render NUL and other nonprinting control bytes safely (e.g. as `.` or a consistent placeholder); never interpret file bytes as terminal escape commands.
- Handle unusually long logical lines without fixed-length Pascal string limits or buffer overflows.
- Do not implement automatic encoding conversion, ANSI escape-sequence interpretation, search, or syntax coloring in v0.1.

### 4.2 Wrapping and horizontal scrolling

- **Default:** wrap long logical lines at the available content width. Each wrapped segment is a separate *display row* for navigation purposes.
- **No-wrap (`-S`):** each logical line uses one display row. Characters beyond the right edge are clipped until the user presses Right; Left scrolls back.
- Maintain a **horizontal column offset** in no-wrap mode, initially zero. Horizontal scroll must not alter vertical position.
- The tab expansion rule must be applied before deciding where content appears at a horizontal offset.
- Toggling wrap should preserve the current logical line as closely as possible, reset horizontal offset when entering wrapping mode, and redraw.
- A single logical line may span many virtual rows. Never require an entire expanded line to be allocated in memory.

## 5. Input and buffering architecture

### 5.1 Named files

Open a named file through DOS file-handle APIs for read-only, random-access I/O. Maintain **32-bit file offsets** so scrolling does not depend on keeping the whole file in conventional memory or on 64 KiB segment limits. Confirm the chosen Free Pascal runtime's seek APIs and offset types on the i8086 target; use narrowly scoped DOS calls if necessary.

### 5.2 Piped or redirected stdin

The viewer must distinguish **input stream** from **keyboard input**:

- File data comes from DOS handle **0** when no filename is given.
- Navigation keys are read independently through BIOS keyboard services or a verified, non-stdin keyboard API.
- Full-screen drawing uses BIOS/video services or a verified display API and must not depend on redirected stdout being a console.

DOS shells may implement pipes with temporary files, but **do not assume stdin is seekable**. Use a seek test where safe, and otherwise stage input into a seekable backing store. This is essential for Up/Page Up on piped text.

**v0.1 staging policy:**

1. For a seekable redirected handle, use it directly after verifying that seeking works.
2. Otherwise, copy the finite input stream to a scratch file **before entering the interactive viewer**. Once staging completes, the pager supports full backward/forward navigation.
3. Select scratch storage from `TEMP` or `TMP` **only when explicitly configured and writable**. Never silently write to the B: data floppy or erase/overwrite an existing file. Use a unique generated filename and remove it on normal exit and handled errors.
4. If no safe scratch directory is configured, or storage is insufficient, emit a clear diagnostic explaining how to set `TEMP`/`TMP`. The program must not corrupt data, silently truncate input, or pretend that backward scrolling works.
5. Spooling an **unbounded/live stream** is not supported in v0.1; completion/EOF is required before the interactive display. A later version can implement streaming ingestion and a bounded-memory backward history.

This makes `TYPE FOO.TXT | LESS` and `CAT FOO.TXT | LESS` functional on systems with suitable scratch space, while being candid about DOS machines that only have two floppy drives. A future optimization may spool in RAM or use a bounded-memory ring buffer before needing disk space, but neither is required initially.

For a two-floppy system, users should prefer `LESS B:\FOO.TXT` (direct seekable access), avoiding any scratch disk requirement.

### 5.3 Line index and memory use

- Use fixed-size read buffers (proposed starting point: **4–8 KiB**, tune by measurements).
- Index **logical line boundaries by file offset**. A sparse index with checkpoints (e.g. every 32 or 64 lines) avoids allocating four bytes for every line in very large files; scan forward from a checkpoint as required.
- Keep a small cache of recent screen rows or line offsets for responsive Up/Down navigation.
- Do not materialize entire files, large expanded strings, or every wrapped row.
- Prefer correctness and deterministic resource limits over elaborate caching in the first release.
- Measure startup and redraw performance on an XT-class CPU; indexing may be lazy for named files or done once during staging for stdin. The precise cache/index size is an implementation tuning parameter.

## 6. Implementation structure (Free Pascal)

Suggested modules, which may initially be collapsed into fewer source files. The source/project name may remain `less16`, but the packaged executable **must be named `LESS.EXE`**:

| Unit | Responsibility |
|---|---|
| `less16.pas` | Argument parsing, startup/shutdown, event loop, exit status |
| `input16.pas` | DOS handles, seek/read, input detection, safe stdin spooling |
| `lines16.pas` | CR/LF normalization, sparse logical-line index, tab expansion |
| `view16.pas` | Vertical/horizontal position and wrap/no-wrap layout |
| `screen16.pas` | Screen geometry, text-mode rendering, status bar, cursor cleanup |
| `keys16.pas` | Keyboard input and extended scan-code mapping |

**Executable name:** the main program unit is `less16.pas`, so the compiler's default output would be `less16.exe`. The Makefile must set the output name explicitly (`-oless.exe`) so the build produces `less.exe`. DOS file names are case-insensitive, so `less.exe` on the Linux build host is `LESS.EXE` on DOS. CI and the release attach `less.exe`.

### 6.1 Toolchain

Use the **Free Pascal i8086 / MS-DOS real-mode cross-compiler** on Linux. Do not accidentally target Free Pascal's separate **GO32v2/DPMI** DOS environment: it requires a newer CPU/runtime model and would defeat the 8086 goal. The distribution packages of `fpc` (e.g. Ubuntu's 3.2.2) contain no i8086 target, so the cross-compiler is fetched separately.

**Pinned toolchain:**

- Package: `fpc-3.2.2.x86_64-linux.cross.i8086-msdos.tar.xz` from <https://downloads.freepascal.org/fpc/dist/3.2.2/i8086-msdos/>
- SHA-256: `fda88f39548993df9b7345110a6b90e7bd64018e42c1ab51723fa16705b7f671` (about 168 MB)
- Contents: `bin/ppcross8086` and RTL units for each memory model under `lib/fpc/3.2.2/units/msdos/<cpu>-<model>/`. No linker or assembler is included. The package also ships `80186-*`, `80286-*` and `80386-*` unit trees. The build must use the `8086-*` units with `-Cp8086`, or the RTL itself may contain instructions newer than the 8086.

Following hello16's `scripts/fetch-libc16` pattern, `scripts/fetch-fpc8086` downloads the pinned archive, checks its SHA-256 *before* unpacking, and unpacks it into `build/fpc8086`. The script reuses the unpacked tree when the stamp matches. Version and hash change together, deliberately, in one commit. CI caches `build/fpc8086` keyed on the script's hash. For local development the same archive can instead be unpacked into a user location such as `~/opt/fpc/3.2.2`, and the build pointed at it with `make FPC8086_ROOT=$HOME/opt/fpc/3.2.2` (the default is `build/fpc8086`). The compiler is then `$(FPC8086_ROOT)/bin/ppcross8086`, and the units are under `$(FPC8086_ROOT)/lib/fpc/3.2.2/units/msdos/8086-<model>/`.

**Linker/assembler:** none required. FPC 3.2.2's i8086-msdos target assembles and links with its internal tools: a test program built with `-Tmsdos -Cp8086 -WmCompact` and no NASM or Open Watcom `wlink` on `PATH` ran correctly under the 8086 DOSBox-X configuration. The only build dependency is the pinned FPC archive.

**Memory model:** use the **compact** model (`-WmCompact`): near code (one 64 KiB code segment, ample for this program) with far data pointers. Read buffers, the sparse line index and the row cache can then be allocated on the heap outside the 64 KiB DGROUP without per-access segment juggling. If code outgrows 64 KiB, move to medium or large deliberately rather than by default. Record the final model and compiler flags in the Makefile and README.

Possible Pascal units include `Dos` and `Crt`, but **verify behavior under redirected stdin/stdout before relying on them**. The Free Pascal `Crt` documentation warns about redirection interactions, so it is safer to isolate screen/keyboard access behind thin routines and use DOS file handles for input. For extended keys, BIOS keyboard scan codes or the documented two-part `ReadKey` convention can be used once tested on the actual i8086 target.

Avoid dynamic allocation designs that assume 32-bit flat pointers or heap objects larger than 64 KiB. Avoid floating-point dependencies.

### 6.2 Event loop (conceptual)

```text
parse options
open named file OR validate/stage stdin
initialize line/seek cache
save console state and enter text viewer
repeat
    layout viewport at current position
    draw content rows and status line
    read a key from the keyboard (not stdin)
    update vertical position / horizontal offset / wrap setting
until Quit
restore console state, close handles, remove owned scratch file
```

Keep rendering deterministic and avoid writing display output through standard output if it may be redirected.

## 7. Error handling

- Clear diagnostics for missing/unreadable input, unsupported argument forms, insufficient memory, failed reads/seeks, unavailable/failed scratch storage, and unsupported display mode.
- Print startup errors to stderr if possible; interactive errors can appear in the status row.
- Exit status: **0** for normal quit after successful open/display, **nonzero** for usage or I/O failures. Assign specific codes during implementation if useful.
- On a read error, do not display uninitialized bytes; keep the viewer stable or exit with a diagnostic.
- On termination, close file handles and remove only scratch files created by `less16`.
- Detect Ctrl+C/break where possible and clean up resources; document that abrupt power-off cannot guarantee temporary-file cleanup.

## 8. Test plan and acceptance criteria

**Emulators.** As in hello16, **DOSBox-X** is the automated test environment for `make test` and CI. Tests run through a wrapper equivalent to hello16's `asm/tests/dosbox-8086` (`cputype=8086`, `core=normal`), so any 186+ instruction is an illegal opcode and the 8086 requirement is checked automatically. **GR-DOS under QEMU** is a manual compatibility check before release (real DOS 4.00 `COMMAND.COM` pipes, `TEMP` handling, `C:\DOS` install), followed by real 8088/8086 hardware or an XT-accurate emulator as a milestone.

**Test strategy.** hello16's `tests/run.sh` runs one `steps.bat` in headless DOSBox-X and compares captured stdout and exit status on the host. That covers the non-interactive behavior (`--help`, `--version`, usage errors, missing files, no-stdin usage, exit codes). It cannot observe a full-screen viewer that writes to video memory and reads the BIOS keyboard. Interactive behavior is tested in three layers:

1. **Unit tests on the host:** `lines16`, `view16` and, where possible, `input16` are written so they don't depend on the screen or keyboard units. A host test program (native `fpc` on Linux) can then exercise CR/LF/CRLF handling across buffer boundaries, tab expansion, the sparse index, wrapping and horizontal offsets against fixture files. This is fast and needs no emulator.
2. **Scripted interaction in DOSBox-X:** feed keystrokes with DOSBox-X's `AUTOTYPE` command (or an equivalent key-injection mechanism), and capture the screen after each step. Screen capture uses a hidden test option that dumps the text-mode video buffer to a file on quit, or DOSBox-X's own screen capture. Compare against expected screen text on the host. Prototype this early. If it proves unreliable, fall back to layer 3.
3. **Hidden test mode (fallback):** an undocumented option that reads a key script from a file and writes rendered screens to a file. It drives the real event loop with the BIOS keyboard and video layers replaced. It must not change normal behavior and is excluded from `--help`.

**Pipes and redirection in the test emulator.** Early on, verify that the DOSBox-X shell supports `TYPE FOO.TXT | LESS` and `LESS < FOO.TXT`, and what handle 0 looks like in each case. DOSBox implements pipes with temporary files, so stdin may appear seekable there but not under real `COMMAND.COM`. The non-seekable staging path must therefore also be covered by a test that forces it (for example a test option or a character-device stdin) and checked under GR-DOS/QEMU.

### Functional tests

- [ ] `LESS FOO.TXT` opens a named file and supports Up, Down, Page Up, Page Down, Home, End, Q and Esc.
- [ ] `LESS < FOO.TXT` and `TYPE FOO.TXT | LESS` work with navigation; also test `CAT FOO.TXT | LESS` when `CAT` is installed.
- [ ] With `-S`, Left/Right move a horizontally clipped viewport and never modify vertical position.
- [ ] `W` toggles wrapping; navigation and position remain consistent.
- [ ] Page movement is clamped at beginning/end of file; screen overlap and status reflect the current position.
- [ ] Verify 40- and 80-column text modes and common screen heights where supported.
- [ ] Verify CRLF, LF-only, CR-only, empty input, no final newline, tabs, control bytes and long lines.
- [ ] Verify files larger than 64 KiB and larger than available conventional RAM.
- [ ] Verify missing files, invalid switches, unreadable files and I/O errors.
- [ ] Verify stdin that is not seekable, and configured versus missing/full/unwritable scratch storage; no writes to B: unless explicitly configured by the user.
- [ ] Verify keyboard navigation still works when stdin is redirected/piped and when stdout is redirected.
- [ ] Check cursor restoration, handle cleanup and temporary-file cleanup.

### Distribution and hardware

- [ ] Build a real-mode **8086-compatible** executable with the pinned Free Pascal cross-toolchain.
- [ ] Verify no 286/386, DPMI, XMS or EMS requirement.
- [ ] Include in **full GR-DOS CF/hard-disk distribution**, ordinarily under `C:\DOS`.
- [ ] **Do not alter the frozen 360 KB GR-DOS boot image.** Include on larger curated boot disks only when space and utility justify it, per GR-DOS issue #17.
- [ ] Test the **A: boot / B: data** scenario with `LESS B:\README.TXT` and no need to write to B:.
- [ ] Document executable size, observed minimum free conventional memory, and responsiveness on XT-class hardware.

## 9. Explicit non-goals for v0.1

Search (`/`, `?`, `n`), multiple files, line numbers, bookmarks, colors/themes, ANSI escape interpretation, Unicode/UTF-8 support, mouse, syntax highlighting, alternate video modes, interactive stdin while producers are still running, and a complete Unix `less` command-line interface are **not required**.

Future work should be additive, using the input, navigation and rendering boundaries in this document.

## 10. Open design decisions to resolve during implementation

All resolved in v0.01; the decisions are recorded here.

1. **Screen and keyboard primitives:** the `Crt` unit is not used. `screen16` writes character/attribute cells directly to video memory (B000h for mode 7, B800h for modes 0–3, at the BIOS page offset), reads the mode and width from INT 10h AH=0Fh and the row count from the BIOS data area when an EGA or later is present (25 otherwise), and hides/restores the cursor with INT 10h. Other video modes exit with a diagnostic. `keys16` reads INT 16h AH=00h. Neither touches standard input or output. Direct writes may show snow on a real IBM CGA in 80-column mode; that is accepted for v0.1.
2. **DOS handle I/O:** a small wrapper over INT 21h (`MsDos` with `Registers`) for open (3Dh, read-only), read (3Fh), seek (42h, 32-bit `LongInt` offsets), IOCTL device information (4400h), create-unique (5Ah), write, close and delete. The RTL's file routines are not used.
3. **Scratch files:** standard input is used directly if IOCTL reports a file and seeking works (MS-DOS `COMMAND.COM` implements pipes with temporary files, and DOSBox-X behaves the same, so pipes and `<` redirection need no scratch file; still to be confirmed under GR-DOS). A device on handle 0 (e.g. `< AUX`, `< NUL`) is spooled with INT 21h 5Ah into `TEMP`, else `TMP`; 5Ah never overwrites an existing file. With neither set, or if creation or writing fails, the program exits with a diagnostic naming `TEMP`/`TMP`. The file is closed and deleted by the exit procedure on every exit path. Ctrl+C/Ctrl+Break in the keyboard buffer abort spooling cleanly.
4. **Index and caches:** a checkpoint every 32 lines (4 bytes each, in 16 KiB chunks allocated on demand: about 125 KiB per million lines), four 4 KiB read blocks with LRU replacement, a 32-entry line cache (start, end, next and display width), and eight column cursors so consecutive rows of a long wrapped line resume rather than rescan. The line-end scan is 8086 assembly, and lines wholly inside a block are indexed in one tight loop. Measured in DOSBox-X at a fixed 300 cycles (roughly XT speed) on a 254 KB, 10,000-line file: start-up about 1 s, End about 8 s (the first time; it then stays indexed), Page Down about 0.4 s, Up about 0.3 s. A single very long line is rescanned from its start when moving *up* within it.
5. **Wrap toggle:** keeps the current top logical line and shows it from its first row (and column 0), then clamps so the screen stays full. Inside a long wrapped line this moves the view back to that line's start.
6. **Toolchain:** FPC 3.2.2's internal assembler and linker suffice (§6.1).
7. **Stdin under DOSBox-X:** `TYPE FOO.TXT | LESS` and `LESS < FOO.TXT` both give a seekable file on handle 0. The non-seekable path is tested in CI with `< NUL` (a device): no `TEMP`/`TMP`, a missing directory, and a working one (checking that the scratch file is removed).
8. **Interactive tests:** the hidden test mode (`--test-keys=SCRIPT`, `--test-screen=CxR`) drives the real event loop with an off-screen buffer and a key script, and `.` in the script writes the screen to standard output; this carries the screen-content tests. `AUTOTYPE` works in headless DOSBox-X as a smoke test of the real BIOS keyboard and video path (the program must quit with status 0), with one quirk: its `pagedown` key drops the key after it, so the tests use the keypad (`kp_3`, `kp_9`). A lost key hangs the step, and the suite fails on the missing result.

Other decisions made during implementation:

- A single Ctrl+Z as the **last byte** of the input is treated as the DOS end-of-text marker and not shown. Other control bytes (0–31 except tab) show as `.`.
- INT 23h (Ctrl+C) is replaced by an `IRET` handler and BREAK is turned off while running (restored on exit), so DOS cannot abort the program past its cleanup. Ctrl+C and Ctrl+Break are read from the BIOS as quit keys. INT 24h (critical error) returns *Fail*, so a drive error becomes a diagnostic rather than an *Abort, Retry, Fail* prompt over the viewer. DOS restores both vectors at exit.
- Right-arrow scrolling is clamped to the widest line currently on the screen.
- Exit status: 0 normal quit, 1 usage error (including no filename with console stdin), 2 input, memory, display or scratch-file error. The unit structure adds a small `util16` (fatal errors, messages) to the units of §6.
- Host-native unit tests (§8 layer 1) were not needed: the test mode covers the line and layout logic in the real DOS build.

Resolve these with prototypes and tests rather than introducing broad features into v0.1.

## 11. Repository conventions (hello16 template, Free Pascal layout)

hello16 defines three layouts (C only, assembly only, C reference plus assembly). less16 is a fourth, **Free Pascal only**, and otherwise follows the template's conventions:

- **Build:** GNU make on a Linux host. `make` fetches the pinned cross-compiler (`scripts/fetch-fpc8086`) and builds `less.exe`. `make test` runs `tests/run.sh` under DOSBox-X (override with `DOSBOX=`, `KEEP=1` keeps the work directory). `make clean` removes build outputs but not the `build/` tool cache.
- **Version:** the one line in `VERSION`, starting at `0.01` and compiled in. `--version` output is checked by `make test`.
- **`main` is protected:** changes land only through pull requests from feature branches (e.g. `graham/impl`). The required `test` status check comes from `ci.yml`. The rules apply to administrators, and force pushes and deletion are disabled (same `gh api` settings as hello16).
- **CI (`.github/workflows/ci.yml`):** on every PR and every push to `main`: restore or fetch the cached FPC toolchain (in place of hello16's libc16/Watcom cache), install `dosbox-x` (no NASM or Watcom needed), then `make` and `make test`.
- **Release (`.github/workflows/release.yml`):** on a push to `main`, if `VERSION` names a version without a `v<VERSION>` tag: build, test, tag, and publish a GitHub release with `less.exe` attached.
- **README:** adapt hello16's README. Replace the libc16/Open Watcom sections with the pinned FPC toolchain, memory model and compiler flags. Describe the Free Pascal layout. Document usage, keys, exit codes and the `TEMP`/`TMP` requirement for piped input.
- **Files:** `less16.pas` and its units, `Makefile`, `VERSION`, `scripts/fetch-fpc8086`, `tests/run.sh` (plus the 8086 DOSBox-X wrapper and any host unit tests), the two workflows, `README.md`, `LICENSE`, and `.gitignore` (ignoring `*.o`, `*.ppu`, `*.exe`, `*.map`, `/build/`).

## References

- Free Pascal's published **i8086 MS-DOS cross-compiler**: <https://www.freepascal.org/_new/docs/download/binary/i8086/msdos/>
- Free Pascal `Crt` unit documentation (including redirection limitations): <https://www.freepascal.org/docs-html/rtl/crt/index.html>
- Free Pascal `ReadKey` documentation (extended-key convention): <https://www.freepascal.org/docs-html/current/rtl/crt/readkey.html>
- GR-DOS issue #17 (boot-floppy distribution policy): <https://github.com/gr-dos/gr-dos/issues/17>
