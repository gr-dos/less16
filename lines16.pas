{ lines16 - logical lines: CR, LF and CRLF line ends, a sparse index of
  line start offsets, tab expansion and rendering a slice of a line.

  Line N (0-based) starts at a file offset.  The index stores the start
  of every IndexStep'th line, discovered lazily by scanning forward;
  other lines are found by scanning from the nearest checkpoint.  A
  small cache keeps recently used lines with their display widths. }
unit lines16;

interface

const
  TabStop = 8;

type
  TLineInfo = record
    Line: LongInt;                 { line number, -1 if unused }
    Start: LongInt;                { offset of first byte }
    Stop: LongInt;                 { offset of the line end (exclusive) }
    Next: LongInt;                 { offset of the next line }
    Width: LongInt;                { display columns after tab expansion }
  end;

procedure InitLines;
function LineExists(N: LongInt): Boolean;
{ Number of lines if the whole input has been indexed. }
function LinesKnown(var Count: LongInt): Boolean;
{ Indexes the whole input; returns the number of lines. }
function CountLines: LongInt;
{ Line N, which must exist. }
procedure GetLine(N: LongInt; var Info: TLineInfo);
{ Text of display columns [Col, Col + Width) of line L into Buf, padded
  with spaces. }
procedure RenderSlice(const L: TLineInfo; Col: LongInt; Width: Word;
                      var Buf: array of Char);

implementation

uses
  input16, util16;

const
  IndexStep  = 32;
  ChunkLen   = 4096;               { checkpoints per chunk (16 KiB) }
  MaxChunks  = 256;
  CacheSize  = 32;                 { power of two }
  NumCursors = 8;

type
  TChunk = array[0..ChunkLen - 1] of LongInt;
  PChunk = ^TChunk;

  TCursor = record
    Line: LongInt;
    Ofs: LongInt;                  { a byte of the line ... }
    Col: LongInt;                  { ... and its display column }
  end;

var
  Chunks: array[0..MaxChunks - 1] of PChunk;
  NumChecks: LongInt;
  KnownLine: LongInt;              { highest line whose start is known }
  KnownOfs: LongInt;               { its start }
  KnownNext: LongInt;              { start of the line after it, or -1 }
  Complete: Boolean;               { the whole input has been indexed }
  NumLines: LongInt;               { valid when Complete }
  Cache: array[0..CacheSize - 1] of TLineInfo;
  Cursors: array[0..NumCursors - 1] of TCursor;
  NextCursor: Integer;

procedure Changed;
begin
  Fatal('read error: input file changed while viewing', ExitIO);
end;

{ ---- scanning ---- }

{$asmmode intel}

{ Index in P^ of the first CR or LF in [From, Count), or Count if none.
  The inner loop of indexing, so it is written in 8086 assembly. }
function FindEol(P: PBlock; From, Count: Word): Word; assembler;
asm
  mov cx, Count
  mov ax, From
  sub cx, ax
  jbe @none
  push ds
  lds si, P
  add si, ax
  mov dx, si
  cld
@scan:
  lodsb
  cmp al, 13
  jbe @check
@next:
  loop @scan
  pop ds
  jmp @none
@check:
  je @found
  cmp al, 10
  jne @next
@found:
  pop ds
  dec si
  mov ax, si
  sub ax, dx
  add ax, From
  jmp @done
@none:
  mov ax, Count
@done:
end;

{ Finds the end of the line starting at Start: Stop is the offset of
  its line-end bytes (or InSize), Next the start of the following line
  (InSize if none).  CRLF is one line end even across blocks. }
procedure ScanEol(Start: LongInt; var Stop, Next: LongInt);
var
  Pos, BStart: LongInt;
  P: PBlock;
  N, I, J: Word;
begin
  Pos := Start;
  while Pos < InSize do
  begin
    N := GetBlock(Pos shr BlockShift, P);
    BStart := Pos and not LongInt(BlockSize - 1);
    I := Word(Pos - BStart);
    if I >= N then
      Changed;
    J := FindEol(P, I, N);
    if J < N then
    begin
      Stop := BStart + J;
      Next := Stop + 1;
      if (P^[J] = 13) and (ByteAt(Next) = 10) then
        Inc(Next);
      Exit;
    end;
    Pos := BStart + N;
  end;
  Stop := InSize;
  Next := InSize;
end;

{ Advances Ofs (a byte at display column Col) over the bytes before
  Stop, stopping at the first byte whose columns reach past Target.

  Per block the arithmetic is 16-bit: Used is the column relative to
  Col rounded down to a tab stop (so Used mod 8 = column mod 8), and a
  block adds at most 8 * BlockSize columns. }
procedure Advance(var Ofs, Col: LongInt; Stop, Target: LongInt);
var
  P: PBlock;
  N, I, Phase, Used, Last, Room: Word;
  BStart: LongInt;
begin
  while Ofs < Stop do
  begin
    N := GetBlock(Ofs shr BlockShift, P);
    BStart := Ofs and not LongInt(BlockSize - 1);
    if BStart + N > Stop then
      N := Word(Stop - BStart);
    I := Word(Ofs - BStart);
    if I >= N then
      Changed;
    Phase := Word(Col) and (TabStop - 1);
    if Target <= Col then
      Room := 0
    else if Target - Col > 60000 then
      Room := 60000
    else
      Room := Word(Target - Col);
    Room := Room + Phase;
    Used := Phase;
    while I < N do
    begin
      if P^[I] = 9 then
        Last := (Used or (TabStop - 1)) + 1
      else
        Last := Used + 1;
      if Last > Room then
      begin
        Col := Col + (Used - Phase);
        Ofs := BStart + I;
        Exit;
      end;
      Used := Last;
      Inc(I);
    end;
    Col := Col + (Used - Phase);
    Ofs := BStart + N;
  end;
end;

{ ---- sparse index ---- }

procedure AddCheck(Ofs: LongInt);
var
  C: Word;
begin
  C := Word(NumChecks div ChunkLen);
  if C >= MaxChunks then
    Fatal('too many lines', ExitIO);
  if Chunks[C] = nil then
  begin
    if MaxAvail < SizeOf(TChunk) then
      Fatal('not enough memory for the line index', ExitIO);
    New(Chunks[C]);
  end;
  Chunks[C]^[Word(NumChecks mod ChunkLen)] := Ofs;
  Inc(NumChecks);
end;

function Check(I: LongInt): LongInt;
begin
  Check := Chunks[Word(I div ChunkLen)]^[Word(I mod ChunkLen)];
end;

{ Scans forward until line N's start is known, and whether it is the
  last line, or until the input ends. }
procedure ExtendTo(N: LongInt);
var
  Stop, BStart: LongInt;
  P: PBlock;
  Len, I, J: Word;
begin
  while not Complete and (KnownLine <= N) do
  begin
    { Fast path: lines that end inside the current block with the byte
      after the line end also in it (so CRLF is decided).  That byte
      starts the next line, so these are never the last line. }
    if (KnownNext < 0) and (KnownLine < N) then
    begin
      Len := GetBlock(KnownOfs shr BlockShift, P);
      BStart := KnownOfs and not LongInt(BlockSize - 1);
      I := Word(KnownOfs - BStart);
      while KnownLine < N do
      begin
        J := FindEol(P, I, Len);
        if J + 1 >= Len then
          Break;
        if (P^[J] = 13) and (P^[J + 1] = 10) then
        begin
          if J + 2 >= Len then
            Break;
          I := J + 2;
        end
        else
          I := J + 1;
        Inc(KnownLine);
        KnownOfs := BStart + I;
        if (Word(KnownLine) and (IndexStep - 1)) = 0 then
          AddCheck(KnownOfs);
      end;
      if KnownLine >= N then
        Continue;
    end;
    if KnownNext < 0 then
      ScanEol(KnownOfs, Stop, KnownNext);
    if KnownNext >= InSize then
    begin
      Complete := True;
      NumLines := KnownLine + 1;
    end
    else if KnownLine < N then
    begin
      Inc(KnownLine);
      KnownOfs := KnownNext;
      KnownNext := -1;
      if KnownLine mod IndexStep = 0 then
        AddCheck(KnownOfs);
    end
    else
      Break;
  end;
end;

function LineExists(N: LongInt): Boolean;
begin
  if N < 0 then
    LineExists := False
  else
  begin
    ExtendTo(N);
    LineExists := N <= KnownLine;
  end;
end;

function LinesKnown(var Count: LongInt): Boolean;
begin
  Count := NumLines;
  LinesKnown := Complete;
end;

function CountLines: LongInt;
begin
  ExtendTo(MaxLongInt);
  CountLines := NumLines;
end;

function LineStart(N: LongInt): LongInt;
var
  Ofs, Stop, Next: LongInt;
  I: Integer;
begin
  ExtendTo(N);
  Ofs := Check(N div IndexStep);
  for I := 1 to Integer(N mod IndexStep) do
  begin
    ScanEol(Ofs, Stop, Next);
    Ofs := Next;
  end;
  LineStart := Ofs;
end;

procedure GetLine(N: LongInt; var Info: TLineInfo);
var
  Slot, Prev: Integer;
  Ofs, W: LongInt;
  E: TLineInfo;
begin
  Slot := Integer(N and (CacheSize - 1));
  if Cache[Slot].Line <> N then
  begin
    Prev := Integer((N - 1) and (CacheSize - 1));
    if (N > 0) and (Cache[Prev].Line = N - 1) then
      E.Start := Cache[Prev].Next
    else
      E.Start := LineStart(N);
    ScanEol(E.Start, E.Stop, E.Next);
    Ofs := E.Start;
    W := 0;
    Advance(Ofs, W, E.Stop, MaxLongInt);
    E.Width := W;
    E.Line := N;
    Cache[Slot] := E;
  end;
  Info := Cache[Slot];
end;

{ ---- rendering ---- }

procedure RenderSlice(const L: TLineInfo; Col: LongInt; Width: Word;
                      var Buf: array of Char);
var
  Ofs, C, W, Best, BStart: LongInt;
  BestI: Integer;
  Out, N, I, Phase: Word;
  B: Byte;
  P: PBlock;
begin
  { Resume from the cursor on this line nearest before Col, so that
    rows of a long wrapped line do not each rescan it from the start. }
  Ofs := L.Start;
  C := 0;
  Best := -1;
  BestI := -1;
  for I := 0 to NumCursors - 1 do
    if (Cursors[I].Line = L.Line) and (Cursors[I].Col <= Col) and
       (Cursors[I].Col > Best) then
    begin
      Best := Cursors[I].Col;
      BestI := Integer(I);
    end;
  if BestI >= 0 then
  begin
    Ofs := Cursors[BestI].Ofs;
    C := Cursors[BestI].Col;
  end;

  Advance(Ofs, C, L.Stop, Col);

  if (BestI < 0) or (Best <> C) then
  begin
    Cursors[NextCursor].Line := L.Line;
    Cursors[NextCursor].Ofs := Ofs;
    Cursors[NextCursor].Col := C;
    NextCursor := (NextCursor + 1) mod NumCursors;
  end;

  { Emit columns Col .. Col + Width - 1.  Only a tab can start before
    Col here: show just its columns from Col on. }
  Out := 0;
  if (Ofs < L.Stop) and (C < Col) then
  begin
    W := C - (C mod TabStop) + TabStop - Col;
    while (W > 0) and (Out < Width) do
    begin
      Buf[Out] := ' ';
      Inc(Out);
      Dec(W);
    end;
    Inc(Ofs);
    Phase := 0;
  end
  else
    Phase := Word(C) and (TabStop - 1);

  while (Out < Width) and (Ofs < L.Stop) do
  begin
    N := GetBlock(Ofs shr BlockShift, P);
    BStart := Ofs and not LongInt(BlockSize - 1);
    if BStart + N > L.Stop then
      N := Word(L.Stop - BStart);
    I := Word(Ofs - BStart);
    if I >= N then
      Changed;
    while (I < N) and (Out < Width) do
    begin
      B := P^[I];
      if B = 9 then
      begin
        repeat
          Buf[Out] := ' ';
          Inc(Out);
          Phase := (Phase + 1) and (TabStop - 1);
        until (Phase = 0) or (Out >= Width);
      end
      else
      begin
        if B < 32 then
          Buf[Out] := '.'
        else
          Buf[Out] := Chr(B);
        Inc(Out);
        Phase := (Phase + 1) and (TabStop - 1);
      end;
      Inc(I);
    end;
    Ofs := BStart + I;
  end;
  while Out < Width do
  begin
    Buf[Out] := ' ';
    Inc(Out);
  end;
end;

procedure InitLines;
var
  I: Integer;
begin
  for I := 0 to MaxChunks - 1 do
    Chunks[I] := nil;
  for I := 0 to CacheSize - 1 do
    Cache[I].Line := -1;
  for I := 0 to NumCursors - 1 do
    Cursors[I].Line := -1;
  NextCursor := 0;
  NumChecks := 0;
  NumLines := 0;
  KnownNext := -1;
  if InSize = 0 then
  begin
    KnownLine := -1;
    KnownOfs := 0;
    Complete := True;
  end
  else
  begin
    KnownLine := 0;
    KnownOfs := 0;
    Complete := False;
    AddCheck(0);
  end;
end;

end.
