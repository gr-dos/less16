# less16

A minimal full-screen text pager for 16-bit MS-DOS, written in Free
Pascal. It is distributed as `LESS.EXE` and invoked as `LESS`.

Unlike `MORE`, it moves backward as well as forward, and in no-wrap mode
it scrolls horizontally. It is a small read-only viewer, not a port of
GNU `less`. The design is in [`docs/DESIGN.md`](docs/DESIGN.md).

`less.exe` is a compact-model, real-mode 8086 executable that runs on
any DOS from an original PC up. It needs no DPMI, XMS or EMS.

`less.exe` is about 41 KB. It reads files of any size (32-bit offsets,
a sparse line index) without loading them into memory: it keeps 16 KB
of read buffers and 4 bytes per 32 lines of input.

## Usage

    LESS [options] [filename]
    TYPE FOO.TXT | LESS
    LESS < FOO.TXT

    -w, /W         wrap long lines (default)
    -S, /S         do not wrap long lines; scroll horizontally
    -h, -?, /?,
        --help     display help and exit
        --version  display version and exit

Options are case-insensitive. With no filename, standard input is read
only if it is redirected or piped.

| Key | Action |
|---|---|
| Up / Down | one row (a wrapped segment, or a line with `-S`) |
| PgUp / PgDn | one screen, keeping one row of overlap |
| Ctrl+Y / Space, Ctrl+V | the same as PgUp / PgDn |
| Home / End | beginning / end of the input |
| Left / Right | scroll 8 columns (no-wrap mode only) |
| `W` | toggle wrapping |
| `Q`, Esc, Ctrl+C | quit |

The bottom row shows the file name (or `[stdin]`), the top line number
(and the line count once known), `WRAP`/`NOWRAP`, the column when
scrolled, and `(END)` when the end is on screen.

Text is shown as single-byte characters in the current code page. Line
ends may be CRLF, LF or CR; tabs expand to 8-column stops; other control
bytes show as `.`; a final Ctrl+Z is ignored. The video mode must be a
text mode (MDA, CGA, EGA or VGA; 40 or 80 columns, any number of rows).

**Piped input:** `TYPE FOO.TXT | LESS` and `LESS < FOO.TXT` read DOS's
pipe or redirection file directly. Input that cannot be seeked (a
device, such as `LESS < AUX`) is first copied to a scratch file in the
directory named by `TEMP` (or `TMP`); with neither set it is an error,
so nothing is written to a disk you did not choose. The scratch file is
removed on exit. On a two-floppy system, view files by name
(`LESS B:\README.TXT`), which never writes anything.

Exit status: 0 on success, 1 for a bad option or operand (or no input),
2 for an input, memory, display or scratch-file error. Messages go to
standard error.

## Building

Everything is built and tested on a Linux host with GNU make and the
Free Pascal **i8086-msdos** cross-compiler (not the GO32v2/DPMI target,
and not a distribution `fpc` package, which lacks the i8086 target).

    make         # builds less.exe
    make test    # runs the test suite under DOSBox-X
    make clean

By default `make` runs `scripts/fetch-fpc8086`, which downloads the FPC
3.2.2 `x86_64-linux.cross.i8086-msdos` archive, checks it against the
SHA-256 written in the script before unpacking it, and unpacks it into
`build/fpc8086`. This needs `curl`, `xz` and `sha256sum`. To move to a
newer FPC, change `version` and `sha256` in the script together.

To use a copy of the same release unpacked elsewhere:

    make FPC8086_ROOT=$HOME/opt/fpc/3.2.2

The compiler's default configuration is ignored (`-n`) and the flags are
`-Tmsdos -Cp8086 -Wmcompact -O2 -Xs -XX -CX`, with only the
`8086-compact` RTL units. The package also contains 80186/80286/80386
unit trees; using them would put post-8086 instructions in the program.
FPC assembles and links internally; no NASM or Open Watcom is needed.

## Conventions

This repository follows the [hello16](https://github.com/gr-dos/hello16)
template conventions for gr-dos utilities, in a Free Pascal layout:

1. **Build and test on Linux** with GNU make, as above.
2. **`main` is protected:** it changes only by merging a pull request
   from a feature branch; the `test` check from `ci.yml` is required,
   for administrators too, with force pushes and deletion disabled (see
   hello16's README for the `gh api` command).
3. **Tests run under DOSBox-X** via `make test`. `tests/run.sh` needs
   `dosbox-x` (override with `DOSBOX=`; `KEEP=1` keeps the work
   directory) and runs it as an 8086 (`cputype=8086`, `core=normal`), so
   a later-CPU instruction fails the suite. One `steps.bat` runs every
   DOS-side step; step N records its exit status in `RN.TXT` and its
   standard output in `ON.TXT`, checked on the host. The viewer is
   tested with hidden options, not shown in `--help`:
   `--test-keys=SCRIPT` replaces the keyboard with SCRIPT (`U` `D` up
   and down, `P` `N` page up and down, `H` `E` home and end, `L` `R`
   left and right, `W` wrap, `Q` quit, `.` write the screen to standard
   output, `#NN` the key with decimal ASCII code NN, such as `#32` for
   Space) and the screen with an off-screen buffer, and
   `--test-screen=CxR` sets its size. DOSBox-X's `AUTOTYPE` also
   drives the real keyboard and video path as a smoke test.
4. **CI must pass before merging:** `.github/workflows/ci.yml` builds and
   runs `make test` on every pull request and push to `main`.
5. **`--version` and `VERSION`:** `less --version` prints
   `less (dos-less16) 0.01`, from the one line in `VERSION`. Versions
   are MS-DOS style: `0.01`, `0.02`, ... `1.00`.
6. **Releases:** `.github/workflows/release.yml` runs on every push to
   `main`. If `VERSION` has no `v<VERSION>` tag yet, it builds, tests,
   tags and publishes a release with `less.exe` attached. To release,
   bump `VERSION` in the PR.

## Files

- `less16.pas`: the program (options, start-up, event loop, cleanup)
- `input16.pas`: DOS handle input, block cache, stdin spooling
- `lines16.pas`: line ends, sparse line index, tabs, line rendering
- `view16.pas`: layout, navigation, status line
- `screen16.pas`: text-mode video and the test-mode screen
- `keys16.pas`: BIOS keyboard and the test-mode key script
- `util16.pas`: fatal errors and messages
- `Makefile`: Free Pascal build (`make`, `make test`, `make clean`)
- `scripts/fetch-fpc8086`: fetch the pinned cross-compiler
- `VERSION`: the version, compiled in and printed by `--version`
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `.github/workflows/ci.yml`: build and test on PRs and pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes
- `docs/DESIGN.md`: the design

## License

MIT. See `LICENSE`.
