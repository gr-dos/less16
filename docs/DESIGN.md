# less16 — Minimal Full-Screen Pager for DOS

**Status:** Proposed design (v0.1)  
**Implementation language:** Free Pascal  
**Executable:** `LESS16.EXE` (subject to compiler output and link verification)  
**Target:** GR-DOS / MS-DOS 4.00-compatible real-mode DOS, including 8086/8088 systems  
**Scope:** Small, useful, read-only full-screen text pager; not a port of GNU `less`

## 1. Purpose

`less16` provides interactive, full-screen viewing of text files on vintage DOS computers. Unlike `MORE`, it supports moving **backward as well as forward**, one line or one page at a time. In non-wrapping mode, it also scrolls horizontally.

It must support both a named file and standard input:

```dos
LESS16 AUTOEXEC.BAT
LESS16 C:\DOS\README.TXT
CAT FOO.TXT | LESS16
TYPE FOO.TXT | LESS16
LESS16 < FOO.TXT
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
LESS16 [options] [filename]

Options:
  -w, /W        Wrap long lines (default)
  -S, /S        Do not wrap long lines; enable horizontal scrolling
  -h, -?, /?    Display short usage help and exit
```

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

This makes `TYPE FOO.TXT | LESS16` and `CAT FOO.TXT | LESS16` functional on systems with suitable scratch space, while being candid about DOS machines that only have two floppy drives. A future optimization may spool in RAM or use a bounded-memory ring buffer before needing disk space, but neither is required initially.

For a two-floppy system, users should prefer `LESS16 B:\FOO.TXT` (direct seekable access), avoiding any scratch disk requirement.

### 5.3 Line index and memory use

- Use fixed-size read buffers (proposed starting point: **4–8 KiB**, tune by measurements).
- Index **logical line boundaries by file offset**. A sparse index with checkpoints (e.g. every 32 or 64 lines) avoids allocating four bytes for every line in very large files; scan forward from a checkpoint as required.
- Keep a small cache of recent screen rows or line offsets for responsive Up/Down navigation.
- Do not materialize entire files, large expanded strings, or every wrapped row.
- Prefer correctness and deterministic resource limits over elaborate caching in the first release.
- Measure startup and redraw performance on an XT-class CPU; indexing may be lazy for named files or done once during staging for stdin. The precise cache/index size is an implementation tuning parameter.

## 6. Implementation structure (Free Pascal)

Suggested modules, which may initially be collapsed into fewer source files:

| Unit | Responsibility |
|---|---|
| `less16.pas` | Argument parsing, startup/shutdown, event loop, exit status |
| `input16.pas` | DOS handles, seek/read, input detection, safe stdin spooling |
| `lines16.pas` | CR/LF normalization, sparse logical-line index, tab expansion |
| `view16.pas` | Vertical/horizontal position and wrap/no-wrap layout |
| `screen16.pas` | Screen geometry, text-mode rendering, status bar, cursor cleanup |
| `keys16.pas` | Keyboard input and extended scan-code mapping |

### 6.1 Toolchain

Use the **Free Pascal i8086 / MS-DOS real-mode cross-compiler** on Linux. Do not accidentally target Free Pascal's separate **GO32v2/DPMI** DOS environment: it requires a newer CPU/runtime model and would defeat the 8086 goal. Free Pascal publishes an i8086-to-MS-DOS cross-compiler; pin and document the actual version/build and required runtime units during implementation.

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

Automate under GR-DOS in QEMU where possible; check on real 8088/8086 hardware or an XT-accurate emulator as a compatibility milestone.

### Functional tests

- [ ] `LESS16 FOO.TXT` opens a named file and supports Up, Down, Page Up, Page Down, Home, End, Q and Esc.
- [ ] `LESS16 < FOO.TXT` and `TYPE FOO.TXT | LESS16` work with navigation; also test `CAT FOO.TXT | LESS16` when `CAT` is installed.
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
- [ ] Test the **A: boot / B: data** scenario with `LESS16 B:\README.TXT` and no need to write to B:.
- [ ] Document executable size, observed minimum free conventional memory, and responsiveness on XT-class hardware.

## 9. Explicit non-goals for v0.1

Search (`/`, `?`, `n`), multiple files, line numbers, bookmarks, colors/themes, ANSI escape interpretation, Unicode/UTF-8 support, mouse, syntax highlighting, alternate video modes, interactive stdin while producers are still running, and a complete Unix `less` command-line interface are **not required**.

Future work should be additive, using the input, navigation and rendering boundaries in this document.

## 10. Open design decisions to resolve during implementation

1. Which screen and keyboard primitives compile and behave correctly in Free Pascal's **i8086 MS-DOS** target without interfering with redirected stdin?
2. Does the target RTL expose reliable DOS handle seek/read operations with 32-bit offsets, or should a small DOS interrupt wrapper be used?
3. What scratch-file naming/creation strategy is safe on DOS 4.00, and how should `TEMP`/`TMP` be resolved when unset?
4. What sparse-index spacing and cache size give usable XT scrolling without excessive memory use?
5. How should viewport positioning on wrap-toggle behave when currently inside a long wrapped logical line?

Resolve these with prototypes and tests rather than introducing broad features into v0.1.

## References

- Free Pascal's published **i8086 MS-DOS cross-compiler**: <https://www.freepascal.org/_new/docs/download/binary/i8086/msdos/>
- Free Pascal `Crt` unit documentation (including redirection limitations): <https://www.freepascal.org/docs-html/rtl/crt/index.html>
- Free Pascal `ReadKey` documentation (extended-key convention): <https://www.freepascal.org/docs-html/current/rtl/crt/readkey.html>
- GR-DOS issue #17 (boot-floppy distribution policy): <https://github.com/gr-dos/gr-dos/issues/17>
