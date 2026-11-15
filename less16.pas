{
  less16 - minimal full-screen pager for 16-bit DOS (LESS.EXE)

  Real-mode 8086 MS-DOS program built with the Free Pascal i8086-msdos
  cross-compiler.  See docs/DESIGN.md.

  Units: input16 (DOS handles, spooling), lines16 (line index, tabs),
  view16 (layout, navigation), screen16 (video), keys16 (keyboard),
  util16 (errors).

  Hidden test options (not in --help): --test-keys=SCRIPT replaces the
  keyboard with SCRIPT (see keys16) and the screen with an off-screen
  buffer that the '.' key writes to standard output; --test-screen=CxR
  sets its size (default 80x25).
}
program less16;

uses
  Dos, util16, input16, lines16, screen16, keys16, view16;

{$I version.inc}

const
  ProgName = 'less';

var
  StartWrap: Boolean;
  FileName: String;
  HaveFile: Boolean;
  TestMode: Boolean;
  TestKeys: String;
  TestCols, TestRows: Word;
  OldBreak: Byte;
  K: TKey;
  BreakSaved: Boolean;

function Lower(const S: String): String;
var
  I: Integer;
begin
  Lower := S;
  for I := 1 to Length(S) do
    if (S[I] >= 'A') and (S[I] <= 'Z') then
      Lower[I] := Chr(Ord(S[I]) + 32);
end;

procedure Usage(var F: Text);
begin
  WriteLn(F, 'Usage: less [OPTION]... [FILE]');
  WriteLn(F, 'View FILE, or redirected standard input, one screen at a time.');
  WriteLn(F);
  WriteLn(F, '  -w, /W         wrap long lines (default)');
  WriteLn(F, '  -S, /S         do not wrap long lines; scroll horizontally');
  WriteLn(F, '  -h, -?, /?,');
  WriteLn(F, '      --help     display this help and exit');
  WriteLn(F, '      --version  output version information and exit');
  WriteLn(F);
  WriteLn(F, 'Keys: Up/Down line, PgUp/PgDn (or Ctrl+Y, Space/Ctrl+V) screen,');
  WriteLn(F, 'Home/End, Left/Right scroll (no-wrap), W toggle wrap, Q or Esc quit.');
end;

{ Writes "less: WHAT 'ARG'" and the --help hint to standard error. }
procedure BadArg(const What, Arg: String);
begin
  WriteLn(StdErr, ProgName, ': ', What, ' ''', Arg, '''');
  WriteLn(StdErr, 'Try ''less --help'' for more information.');
  Halt(ExitUsage);
end;

{ "--test-screen=CxR" value. }
procedure ParseSize(const A, V: String);
var
  X, Code: Integer;
  C, R: LongInt;
begin
  X := Pos('x', V);
  if X = 0 then
    BadArg('bad screen size', A);
  Val(Copy(V, 1, X - 1), C, Code);
  if Code <> 0 then
    BadArg('bad screen size', A);
  Val(Copy(V, X + 1, 255), R, Code);
  if (Code <> 0) or (C < 20) or (C > MaxCols) or (R < 2) or
     (R > MaxTestRows) then
    BadArg('bad screen size', A);
  TestCols := Word(C);
  TestRows := Word(R);
end;

procedure ParseArgs;
var
  I: Integer;
  A, L: String;
begin
  StartWrap := True;
  TestMode := False;
  TestKeys := '';
  TestCols := 80;
  TestRows := 25;
  HaveFile := False;
  FileName := '';
  for I := 1 to ParamCount do
  begin
    A := ParamStr(I);
    L := Lower(A);
    if (L = '--help') or (L = '-h') or (L = '-?') or (L = '/?') then
    begin
      Usage(Output);
      Halt(ExitOk);
    end
    else if L = '--version' then
    begin
      WriteLn(ProgName, ' (dos-less16) ', Version);
      Halt(ExitOk);
    end
    else if (L = '-w') or (L = '/w') then
      StartWrap := True
    else if (L = '-s') or (L = '/s') then
      StartWrap := False
    else if Copy(L, 1, 12) = '--test-keys=' then
    begin
      TestMode := True;
      TestKeys := Copy(A, 13, 255);
    end
    else if Copy(L, 1, 14) = '--test-screen=' then
      ParseSize(A, Copy(L, 15, 255))
    else if (Length(A) > 1) and ((A[1] = '-') or (A[1] = '/')) then
      BadArg('unrecognized option', A)
    else if HaveFile then
      BadArg('extra operand', A)
    else
    begin
      FileName := A;
      HaveFile := True;
    end;
  end;
end;

{ Ctrl+C / Ctrl+Break: ignored (IRET), so DOS never aborts the program
  past its cleanup.  The viewer reads Ctrl+C and Ctrl+Break from the
  BIOS as quit keys. }
procedure BreakHandler; assembler; nostackframe;
asm
  iret
end;

{ Critical error (e.g. drive not ready): fail the DOS call (AL=3) so the
  program reports it instead of DOS prompting Abort, Retry, Fail over
  the viewer. }
procedure CritHandler; assembler; nostackframe;
asm
  mov al, 3
  iret
end;

procedure InstallHandlers;
var
  R: Registers;
begin
  SetIntVec($23, Ptr(CSeg, Ofs(BreakHandler)));
  SetIntVec($24, Ptr(CSeg, Ofs(CritHandler)));
  { BREAK OFF while running: DOS then checks only console I/O. }
  R.AX := $3300;
  MsDos(R);
  OldBreak := R.DL;
  BreakSaved := True;
  R.AX := $3301;
  R.DX := 0;
  MsDos(R);
end;

{ Exit procedure: runs on every exit, including Fatal and run-time
  errors.  DOS restores the INT 23h/24h vectors itself. }
procedure Cleanup;
var
  R: Registers;
begin
  ScreenDone;
  CloseInput;
  if BreakSaved then
  begin
    R.AX := $3301;
    R.DX := OldBreak;
    MsDos(R);
    BreakSaved := False;
  end;
  if FatalMsg <> '' then
  begin
    WriteLn(StdErr, ProgName, ': ', FatalMsg);
    FatalMsg := '';
  end;
end;

begin
  FatalMsg := '';
  BreakSaved := False;
  ParseArgs;

  if not HaveFile and StdinIsConsole then
  begin
    WriteLn(StdErr, ProgName, ': missing filename and standard input is not redirected');
    WriteLn(StdErr, 'Try ''less --help'' for more information.');
    Halt(ExitUsage);
  end;

  AddExitProc(@Cleanup);
  InstallHandlers;

  if HaveFile then
    OpenNamed(FileName)
  else
    OpenStdin;
  InitLines;

  ScreenDetect(TestMode, TestCols, TestRows);
  KeysInit(TestMode, TestKeys);
  ViewInit(StartWrap);
  ScreenStart;
  repeat
    Render;
    K := GetKey;
    if K = kDump then
      DumpScreen;
  until not DoKey(K);
  Halt(ExitOk);
end.
