{
  less16 - minimal full-screen pager for 16-bit DOS (LESS.EXE)

  Real-mode 8086 MS-DOS program built with the Free Pascal i8086-msdos
  cross-compiler.  See docs/DESIGN.md.

  This is the startup skeleton: argument parsing, --help, --version and
  input checks.  The viewer itself is not implemented yet.
}
program less16;

uses
  Dos;

{$I version.inc}

const
  ProgName = 'less';

  ExitOk    = 0;
  ExitUsage = 1;
  ExitIO    = 2;

var
  Wrap: Boolean;
  FileName: String;
  HaveFile: Boolean;

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
  WriteLn(F, 'Keys: Up/Down line, PgUp/PgDn screen, Home/End, Left/Right');
  WriteLn(F, 'scroll (no-wrap), W toggle wrap, Q or Esc quit.');
end;

{ Writes "less: WHAT 'ARG'" and the --help hint to standard error. }
procedure BadArg(const What, Arg: String);
begin
  WriteLn(StdErr, ProgName, ': ', What, ' ''', Arg, '''');
  WriteLn(StdErr, 'Try ''less --help'' for more information.');
  Halt(ExitUsage);
end;

{ True if DOS handle H refers to a character device (e.g. the console)
  rather than a file, using IOCTL "get device information". }
function IsDevice(H: Word): Boolean;
var
  R: Registers;
begin
  R.AX := $4400;
  R.BX := H;
  MsDos(R);
  IsDevice := ((R.Flags and FCarry) = 0) and ((R.DX and $80) <> 0);
end;

procedure ParseArgs;
var
  I: Integer;
  A, L: String;
begin
  Wrap := True;
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
      Wrap := True
    else if (L = '-s') or (L = '/s') then
      Wrap := False
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

begin
  ParseArgs;

  if not HaveFile and IsDevice(0) then
  begin
    WriteLn(StdErr, ProgName, ': missing filename and standard input is not redirected');
    WriteLn(StdErr, 'Try ''less --help'' for more information.');
    Halt(ExitUsage);
  end;

  { Viewer not implemented yet. }
  WriteLn(StdErr, ProgName, ': viewer not implemented yet');
  Halt(ExitIO);
end.
