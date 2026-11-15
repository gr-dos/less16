{ view16 - viewport position, wrap/no-wrap layout, navigation and
  drawing the content rows and status line.

  The top of the screen is a display row: a logical line and, when
  wrapping, which ViewW-column segment of it.  Without wrapping every
  line is one row, shown from column HOff. }
unit view16;

interface

uses
  keys16;

const
  HStep = 8;

var
  Wrap: Boolean;

procedure ViewInit(StartWrap: Boolean);
procedure Render;
{ Applies a navigation key; false for quit. }
function DoKey(K: TKey): Boolean;

implementation

uses
  input16, lines16, screen16, util16;

type
  TPos = record
    Line: LongInt;
    Row: LongInt;                  { segment of the line when wrapping }
  end;

var
  Top: TPos;
  HOff: LongInt;
  ViewW, ViewH: Word;
  AtEnd: Boolean;                  { the last row is on the screen }
  MaxWidth: LongInt;               { widest line on the screen }

function RowsIn(N: LongInt): LongInt;
var
  L: TLineInfo;
begin
  if not Wrap then
    RowsIn := 1
  else
  begin
    GetLine(N, L);
    if L.Width = 0 then
      RowsIn := 1
    else
      RowsIn := (L.Width + ViewW - 1) div ViewW;
  end;
end;

function NextRow(var P: TPos): Boolean;
begin
  NextRow := True;
  if P.Row + 1 < RowsIn(P.Line) then
    Inc(P.Row)
  else if LineExists(P.Line + 1) then
  begin
    Inc(P.Line);
    P.Row := 0;
  end
  else
    NextRow := False;
end;

function PrevRow(var P: TPos): Boolean;
begin
  PrevRow := True;
  if P.Row > 0 then
    Dec(P.Row)
  else if P.Line > 0 then
  begin
    Dec(P.Line);
    P.Row := RowsIn(P.Line) - 1;
  end
  else
    PrevRow := False;
end;

{ Number of rows from P onward, counting at most Limit. }
function RowsFrom(P: TPos; Limit: LongInt): LongInt;
var
  N: LongInt;
begin
  N := 0;
  if LineExists(P.Line) then
    repeat
      Inc(N);
    until (N >= Limit) or not NextRow(P);
  RowsFrom := N;
end;

{ The top position that puts the last row at the bottom of the screen. }
procedure EndTop(var P: TPos);
var
  I: Word;
begin
  P.Line := CountLines - 1;
  P.Row := 0;
  if P.Line < 0 then
  begin
    P.Line := 0;
    Exit;
  end;
  P.Row := RowsIn(P.Line) - 1;
  for I := 2 to ViewH do
    if not PrevRow(P) then
      Break;
end;

{ Keeps the screen full: no top position past EndTop. }
procedure ClampTop;
begin
  if RowsFrom(Top, ViewH) < ViewH then
    EndTop(Top);
end;

function PageRows: Word;
begin
  if ViewH > 1 then
    PageRows := ViewH - 1          { keep one row of context }
  else
    PageRows := 1;
end;

procedure ViewInit(StartWrap: Boolean);
begin
  Wrap := StartWrap;
  ViewW := ScrCols;
  ViewH := ScrRows - 1;
  Top.Line := 0;
  Top.Row := 0;
  HOff := 0;
end;

{ ---- drawing ---- }

procedure AddStr(var Buf: TRowText; var N: Word; const S: String);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if N < ScrCols then
    begin
      Buf[N] := S[I];
      Inc(N);
    end;
end;

procedure DrawStatus;
var
  Buf: TRowText;
  Info, Name: String;
  Count: LongInt;
  N: Word;
  Room: Integer;
begin
  if LinesKnown(Count) and (Count = 0) then
    Info := 'Line 0/0'
  else
  begin
    Info := 'Line ' + IntToStr(Top.Line + 1);
    if LinesKnown(Count) then
      Info := Info + '/' + IntToStr(Count);
  end;
  if Wrap then
    Info := Info + '  WRAP'
  else
  begin
    Info := Info + '  NOWRAP';
    if HOff > 0 then
      Info := Info + '  Col ' + IntToStr(HOff + 1);
  end;
  if AtEnd then
    Info := Info + '  (END)';
  if ScrCols >= 60 then
    Info := Info + '  Q quit';

  { Name first, shortened from the left to fit. }
  Name := InName;
  Room := Integer(ScrCols) - Length(Info) - 3;
  if Room < 4 then
    Name := ''
  else if Length(Name) > Room then
    Name := '<' + Copy(Name, Length(Name) - Room + 2, Room - 1);

  FillChar(Buf, SizeOf(Buf), ' ');
  N := 0;
  AddStr(Buf, N, ' ');
  if Name <> '' then
    AddStr(Buf, N, Name + '  ');
  AddStr(Buf, N, Info);
  PutRow(ScrRows - 1, Buf, AttrStatus);
end;

procedure Render;
var
  P: TPos;
  R: Word;
  Have: Boolean;
  L: TLineInfo;
  Buf: TRowText;
  Col: LongInt;
begin
  P := Top;
  Have := LineExists(P.Line);
  MaxWidth := 0;
  for R := 0 to ViewH - 1 do
  begin
    if Have then
    begin
      GetLine(P.Line, L);
      if L.Width > MaxWidth then
        MaxWidth := L.Width;
      if Wrap then
        Col := P.Row * ViewW
      else
        Col := HOff;
      RenderSlice(L, Col, ViewW, Buf);
      Have := NextRow(P);
    end
    else
      FillChar(Buf, SizeOf(Buf), ' ');
    PutRow(R, Buf, AttrText);
  end;
  AtEnd := not Have;
  DrawStatus;
end;

{ ---- keys ---- }

function DoKey(K: TKey): Boolean;
var
  I: Word;
  MaxOff: LongInt;
begin
  DoKey := True;
  case K of
    kQuit:
      DoKey := False;
    kDown:
      if RowsFrom(Top, ViewH + 1) > ViewH then
        NextRow(Top);
    kUp:
      PrevRow(Top);
    kPgDn:
      begin
        for I := 1 to PageRows do
          if not NextRow(Top) then
            Break;
        ClampTop;
      end;
    kPgUp:
      for I := 1 to PageRows do
        if not PrevRow(Top) then
          Break;
    kHome:
      begin
        Top.Line := 0;
        Top.Row := 0;
      end;
    kEnd:
      EndTop(Top);
    kLeft:
      if not Wrap then
      begin
        HOff := HOff - HStep;
        if HOff < 0 then
          HOff := 0;
      end;
    kRight:
      if not Wrap then
      begin
        MaxOff := MaxWidth - ViewW;
        if HOff + HStep <= MaxOff then
          HOff := HOff + HStep
        else if HOff < MaxOff then
          HOff := MaxOff;
      end;
    kWrap:
      begin
        { Keep the logical line; start at its first row. }
        Wrap := not Wrap;
        Top.Row := 0;
        HOff := 0;
        ClampTop;
      end;
  end;
end;

end.
