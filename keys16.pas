{ keys16 - keyboard input through the BIOS (INT 16h), never standard
  input, so navigation works while stdin is redirected.  In test mode
  keys come from a script string instead. }
unit keys16;

interface

type
  TKey = (kUp, kDown, kPgUp, kPgDn, kHome, kEnd, kLeft, kRight,
          kWrap, kQuit, kDump);

{ Script is used instead of the keyboard when Test is true:
  U D up/down, P N page up/down, H E home/end, L R left/right,
  W wrap, Q quit, '.' dump the screen, and #NN the key whose ASCII
  code is decimal NN, decoded as from the keyboard (#32 is Space).
  The end of the script quits. }
procedure KeysInit(Test: Boolean; const Script: String);
function GetKey: TKey;

implementation

uses
  Dos;

var
  TestMode: Boolean;
  TestScript: String;
  TestPos: Integer;

procedure KeysInit(Test: Boolean; const Script: String);
begin
  TestMode := Test;
  TestScript := Script;
  TestPos := 0;
end;

{ Decodes an ASCII key code from the keyboard; False if unbound. }
function CharKey(C: Byte; var K: TKey): Boolean;
begin
  CharKey := True;
  case C of
    Ord('q'), Ord('Q'), 27, 3: K := kQuit;     { Esc, Ctrl+C }
    Ord('w'), Ord('W'): K := kWrap;
    32, 22: K := kPgDn;                        { Space, Ctrl+V }
    25: K := kPgUp;                            { Ctrl+Y }
  else
    CharKey := False;
  end;
end;

function ScriptKey: TKey;
var
  C: Word;
  K: TKey;
begin
  while True do
  begin
    Inc(TestPos);
    if TestPos > Length(TestScript) then
    begin
      ScriptKey := kQuit;
      Exit;
    end;
    if TestScript[TestPos] = '#' then
    begin
      C := 0;
      while (TestPos < Length(TestScript)) and
            (TestScript[TestPos + 1] in ['0'..'9']) do
      begin
        Inc(TestPos);
        C := C * 10 + Ord(TestScript[TestPos]) - Ord('0');
      end;
      if (C <= 255) and CharKey(Byte(C), K) then
      begin
        ScriptKey := K;
        Exit;
      end;
      Continue;
    end;
    case UpCase(TestScript[TestPos]) of
      'U': begin ScriptKey := kUp; Exit; end;
      'D': begin ScriptKey := kDown; Exit; end;
      'P': begin ScriptKey := kPgUp; Exit; end;
      'N': begin ScriptKey := kPgDn; Exit; end;
      'H': begin ScriptKey := kHome; Exit; end;
      'E': begin ScriptKey := kEnd; Exit; end;
      'L': begin ScriptKey := kLeft; Exit; end;
      'R': begin ScriptKey := kRight; Exit; end;
      'W': begin ScriptKey := kWrap; Exit; end;
      'Q': begin ScriptKey := kQuit; Exit; end;
      '.': begin ScriptKey := kDump; Exit; end;
    end;
  end;
end;

function GetKey: TKey;
var
  R: Registers;
  K: TKey;
begin
  if TestMode then
  begin
    GetKey := ScriptKey;
    Exit;
  end;
  while True do
  begin
    R.AX := $0000;                 { wait for a key }
    Intr($16, R);
    if R.AX = 0 then               { Ctrl+Break }
    begin
      GetKey := kQuit;
      Exit;
    end;
    if (R.AL = 0) or (R.AL = $E0) then
      case R.AH of
        $48: begin GetKey := kUp; Exit; end;
        $50: begin GetKey := kDown; Exit; end;
        $49: begin GetKey := kPgUp; Exit; end;
        $51: begin GetKey := kPgDn; Exit; end;
        $47: begin GetKey := kHome; Exit; end;
        $4F: begin GetKey := kEnd; Exit; end;
        $4B: begin GetKey := kLeft; Exit; end;
        $4D: begin GetKey := kRight; Exit; end;
      end
    else if CharKey(R.AL, K) then
    begin
      GetKey := K;
      Exit;
    end;
  end;
end;

end.
