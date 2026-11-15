{ util16 - fatal errors, exit codes and small helpers shared by the
  less16 units. }
unit util16;

interface

const
  ExitOk    = 0;
  ExitUsage = 1;
  ExitIO    = 2;

var
  { Set by Fatal; printed to standard error by the main program's exit
    procedure after the screen has been restored. }
  FatalMsg: String;

procedure Fatal(const Msg: String; Code: Byte);
function IntToStr(N: LongInt): String;
function DosErrorText(Code: Word): String;

implementation

procedure Fatal(const Msg: String; Code: Byte);
begin
  FatalMsg := Msg;
  Halt(Code);
end;

function IntToStr(N: LongInt): String;
var
  S: String;
begin
  Str(N, S);
  IntToStr := S;
end;

function DosErrorText(Code: Word): String;
begin
  case Code of
    2: DosErrorText := 'file not found';
    3: DosErrorText := 'path not found';
    4: DosErrorText := 'too many open files';
    5: DosErrorText := 'access denied';
    6: DosErrorText := 'invalid handle';
    8: DosErrorText := 'insufficient memory';
    15: DosErrorText := 'invalid drive';
    21: DosErrorText := 'drive not ready';
    29: DosErrorText := 'write fault';
    30: DosErrorText := 'read fault';
    83: DosErrorText := 'critical error';
  else
    DosErrorText := 'DOS error ' + IntToStr(Code);
  end;
end;

end.
