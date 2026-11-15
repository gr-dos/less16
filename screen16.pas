{ screen16 - text-mode screen: geometry, direct video-memory rendering,
  cursor save/restore and the off-screen buffer used by the test mode.

  Nothing is written through standard output, so the display works when
  stdout is redirected.  The video mode, palette and screen size are
  never changed. }
unit screen16;

interface

const
  MaxCols = 255;
  MaxTestRows = 100;
  AttrText   = $07;
  AttrStatus = $70;

type
  TRowText = array[0..MaxCols - 1] of Char;

var
  ScrCols, ScrRows: Word;

{ Checks for a usable text mode (or sets up a Cols x Rows test screen
  when Test is true); a fatal error otherwise. }
procedure ScreenDetect(Test: Boolean; Cols, Rows: Word);
procedure ScreenStart;
procedure ScreenDone;
procedure PutRow(Row: Word; const Text: TRowText; Attr: Byte);
{ Test mode: writes the screen text to standard output. }
procedure DumpScreen;

implementation

uses
  Dos, util16;

type
  TVirt = array[0..MaxCols * MaxTestRows - 1] of Char;
  PVirt = ^TVirt;

var
  TestMode, Active: Boolean;
  VidSeg, VidOfs: Word;
  Page: Byte;
  SavedShape: Word;
  Virt: PVirt;

procedure ScreenDetect(Test: Boolean; Cols, Rows: Word);
var
  R: Registers;
  Mode: Byte;
begin
  TestMode := Test;
  if Test then
  begin
    ScrCols := Cols;
    ScrRows := Rows;
    New(Virt);
    Exit;
  end;

  R.AX := $0F00;                   { get video mode }
  Intr($10, R);
  Mode := R.AL and $7F;
  ScrCols := R.AH;
  Page := R.BH;
  case Mode of
    7: VidSeg := $B000;
    0..3: VidSeg := $B800;
  else
    Fatal('unsupported video mode ' + IntToStr(Mode) +
          ' (a text mode is required)', ExitIO);
  end;

  { EGA and later keep the row count in the BIOS data area; MDA and
    CGA always have 25 rows. }
  R.AX := $1200;
  R.BX := $0010;
  Intr($10, R);
  if R.BL <> $10 then
    ScrRows := Mem[$40:$84] + 1
  else
    ScrRows := 25;
  VidOfs := MemW[$40:$4E];

  if (ScrCols < 20) or (ScrRows < 2) then
    Fatal('unsupported screen size', ExitIO);
end;

procedure ScreenStart;
var
  R: Registers;
begin
  if not TestMode then
  begin
    R.AX := $0300;                 { read cursor shape and position }
    R.BX := Word(Page) shl 8;
    Intr($10, R);
    SavedShape := R.CX;
    R.AX := $0100;                 { hide the cursor }
    R.CX := $2000;
    Intr($10, R);
  end;
  Active := True;
end;

procedure ScreenDone;
var
  R: Registers;
  Blank: TRowText;
  I: Word;
begin
  if not Active then
    Exit;
  Active := False;
  if TestMode then
    Exit;
  FillChar(Blank, SizeOf(Blank), ' ');
  for I := 0 to ScrRows - 1 do
    PutRow(I, Blank, AttrText);
  R.AX := $0200;                   { cursor to the top left }
  R.BX := Word(Page) shl 8;
  R.DX := 0;
  Intr($10, R);
  R.AX := $0100;                   { restore its shape }
  R.CX := SavedShape;
  Intr($10, R);
end;

procedure PutRow(Row: Word; const Text: TRowText; Attr: Byte);
var
  Cells: array[0..MaxCols - 1] of Word;
  I: Word;
  P: Pointer;
begin
  if TestMode then
  begin
    Move(Text, Virt^[Row * ScrCols], ScrCols);
    Exit;
  end;
  for I := 0 to ScrCols - 1 do
    Cells[I] := (Word(Attr) shl 8) or Ord(Text[I]);
  P := Ptr(VidSeg, VidOfs + Row * ScrCols * 2);
  Move(Cells, P^, ScrCols * 2);
end;

procedure DumpScreen;
var
  R, I, N: Word;
  S: String;
begin
  for R := 0 to ScrRows - 1 do
  begin
    N := ScrCols;
    while (N > 0) and (Virt^[R * ScrCols + N - 1] = ' ') do
      Dec(N);
    S := '';
    for I := 1 to N do
      S := S + Virt^[R * ScrCols + I - 1];
    WriteLn(S);
  end;
  WriteLn('--');
end;

begin
  Active := False;
  TestMode := False;
end.
