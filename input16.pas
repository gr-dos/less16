{ input16 - DOS handle input with 32-bit offsets, a small block cache,
  and spooling of non-seekable standard input to a scratch file.

  All file data is read through DOS handle calls (INT 21h), never
  through the Pascal Input text file, so a redirected standard input is
  only ever data and keys come from the BIOS (keys16). }
unit input16;

interface

const
  BlockShift = 12;
  BlockSize  = 4096;               { 1 shl BlockShift }
  NumBlocks  = 4;

type
  TBlock = array[0..BlockSize - 1] of Byte;
  PBlock = ^TBlock;

var
  InSize: LongInt;                 { viewable bytes of input }
  InName: String;                  { name for the status line }

{ True if standard input is the console, i.e. not redirected. }
function StdinIsConsole: Boolean;
procedure OpenNamed(const Name: String);
procedure OpenStdin;
procedure CloseInput;

{ Block number BlockNo (offset BlockNo shl BlockShift) in P; returns
  the number of valid bytes, clamped to InSize. }
function GetBlock(BlockNo: LongInt; var P: PBlock): Word;
{ Byte at Ofs, or -1 at or beyond the end of input. }
function ByteAt(Ofs: LongInt): Integer;

implementation

uses
  Dos, util16;

var
  InHandle: Word;
  InOpen: Boolean;
  Base: LongInt;                   { offset of byte 0 in the handle }
  TempOpen: Boolean;
  TempName: array[0..127] of Char; { ASCIIZ scratch file path }

  Blk: array[0..NumBlocks - 1] of PBlock;
  BlkNo: array[0..NumBlocks - 1] of LongInt;
  BlkLen: array[0..NumBlocks - 1] of Word;
  BlkUse: array[0..NumBlocks - 1] of Word;
  Clock: Word;
  LastI: Integer;                  { most recently used slot }

{ ---- DOS calls ---- }

function Failed(var R: Registers): Boolean;
begin
  Failed := (R.Flags and FCarry) <> 0;
end;

function DeviceInfo(H: Word; var Info: Word): Boolean;
var
  R: Registers;
begin
  R.AX := $4400;
  R.BX := H;
  MsDos(R);
  Info := R.DX;
  DeviceInfo := not Failed(R);
end;

function DosSeek(H: Word; Ofs: LongInt; Method: Byte; var NewPos: LongInt): Word;
var
  R: Registers;
begin
  R.AX := $4200 + Method;
  R.BX := H;
  R.CX := Word(Ofs shr 16);
  R.DX := Word(Ofs);
  MsDos(R);
  if Failed(R) then
    DosSeek := R.AX
  else
  begin
    NewPos := (LongInt(R.DX) shl 16) or R.AX;
    DosSeek := 0;
  end;
end;

function DosRead(H: Word; Buf: Pointer; Count: Word; var Got: Word): Word;
var
  R: Registers;
begin
  R.AX := $3F00;
  R.BX := H;
  R.CX := Count;
  R.DS := Seg(Buf^);
  R.DX := Ofs(Buf^);
  MsDos(R);
  if Failed(R) then
    DosRead := R.AX
  else
  begin
    Got := R.AX;
    DosRead := 0;
  end;
end;

function DosWrite(H: Word; Buf: Pointer; Count: Word; var Put: Word): Word;
var
  R: Registers;
begin
  R.AX := $4000;
  R.BX := H;
  R.CX := Count;
  R.DS := Seg(Buf^);
  R.DX := Ofs(Buf^);
  MsDos(R);
  if Failed(R) then
    DosWrite := R.AX
  else
  begin
    Put := R.AX;
    DosWrite := 0;
  end;
end;

procedure DosClose(H: Word);
var
  R: Registers;
begin
  R.AX := $3E00;
  R.BX := H;
  MsDos(R);
end;

procedure DosDelete(var Path: array of Char);
var
  R: Registers;
begin
  R.AX := $4100;
  R.DS := Seg(Path[0]);
  R.DX := Ofs(Path[0]);
  MsDos(R);
end;

procedure ToAsciiz(const S: String; var Z: array of Char);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    Z[I - 1] := S[I];
  Z[Length(S)] := #0;
end;

{ ---- keyboard break while spooling ---- }

{ True if Ctrl+C or Ctrl+Break is waiting in the BIOS keyboard buffer;
  other keys are left for the viewer. }
function BreakPending: Boolean;
var
  R: Registers;
begin
  BreakPending := False;
  R.AX := $0100;
  Intr($16, R);
  if (R.Flags and FZero) = 0 then
    if (R.AX = 0) or (R.AL = 3) then
    begin
      R.AX := $0000;
      Intr($16, R);
      BreakPending := True;
    end;
end;

{ ---- block cache ---- }

procedure AllocBlocks;
var
  I: Integer;
begin
  for I := 0 to NumBlocks - 1 do
  begin
    if MaxAvail < SizeOf(TBlock) then
      Fatal('not enough memory', ExitIO);
    New(Blk[I]);
    BlkNo[I] := -1;
    BlkLen[I] := 0;
    BlkUse[I] := 0;
  end;
  Clock := 0;
  LastI := 0;
end;

function GetBlock(BlockNo: LongInt; var P: PBlock): Word;
var
  I, Victim: Integer;
  Pos, Avail: LongInt;
  Err, Got: Word;
begin
  if BlkNo[LastI] = BlockNo then
    I := LastI
  else
  begin
    Inc(Clock);
    Victim := 0;
    for I := 0 to NumBlocks - 1 do
    begin
      if BlkNo[I] = BlockNo then
      begin
        Victim := I;
        Break;
      end;
      if BlkUse[I] < BlkUse[Victim] then
        Victim := I;
    end;
    I := Victim;
    if BlkNo[I] <> BlockNo then
    begin
      BlkNo[I] := -1;
      Err := DosSeek(InHandle, Base + (BlockNo shl BlockShift), 0, Pos);
      if Err = 0 then
        Err := DosRead(InHandle, Blk[I], BlockSize, Got);
      if Err <> 0 then
        Fatal('read error: ' + DosErrorText(Err), ExitIO);
      BlkNo[I] := BlockNo;
      BlkLen[I] := Got;
    end;
    BlkUse[I] := Clock;
    LastI := I;
  end;
  P := Blk[I];
  Avail := InSize - (BlockNo shl BlockShift);
  if Avail < 0 then
    Avail := 0;
  if Avail < BlkLen[I] then
    GetBlock := Word(Avail)
  else
    GetBlock := BlkLen[I];
end;

function ByteAt(Ofs: LongInt): Integer;
var
  P: PBlock;
  N, I: Word;
begin
  ByteAt := -1;
  if (Ofs < 0) or (Ofs >= InSize) then
    Exit;
  N := GetBlock(Ofs shr BlockShift, P);
  I := Word(Ofs and (BlockSize - 1));
  if I < N then
    ByteAt := P^[I]
  else
    Fatal('read error: input file changed while viewing', ExitIO);
end;

{ ---- opening ---- }

{ Copies the stream on handle H to a new uniquely named scratch file in
  TEMP or TMP and makes that the input. }
procedure Spool(H: Word);
var
  Dir: String;
  R: Registers;
  Err, Got, Put: Word;
  Total, Pos: LongInt;
begin
  Dir := GetEnv('TEMP');
  if Dir = '' then
    Dir := GetEnv('TMP');
  if Dir = '' then
    Fatal('input is not seekable and needs a scratch file;' +
          ' set TEMP or TMP to a writable directory', ExitIO);
  if Length(Dir) > 100 then
    Fatal('TEMP/TMP path is too long', ExitIO);
  if not (Dir[Length(Dir)] in ['\', ':']) then
    Dir := Dir + '\';

  { Create unique file (DOS 3.0+): never overwrites an existing file. }
  ToAsciiz(Dir, TempName);
  R.AX := $5A00;
  R.CX := 0;
  R.DS := Seg(TempName[0]);
  R.DX := Ofs(TempName[0]);
  MsDos(R);
  if Failed(R) then
    Fatal('cannot create scratch file in ' + Dir + ': ' +
          DosErrorText(R.AX), ExitIO);
  InHandle := R.AX;
  InOpen := True;
  TempOpen := True;

  Total := 0;
  repeat
    Err := DosRead(H, Blk[0], BlockSize, Got);
    if Err <> 0 then
      Fatal('read error on input: ' + DosErrorText(Err), ExitIO);
    if Got > 0 then
    begin
      Err := DosWrite(InHandle, Blk[0], Got, Put);
      if (Err <> 0) or (Put <> Got) then
        Fatal('cannot write scratch file in ' + Dir + ' (disk full?)',
              ExitIO);
      Total := Total + Got;
    end;
    if BreakPending then
      Fatal('interrupted', ExitIO);
  until Got = 0;

  if H <> 0 then
    DosClose(H);
  Base := 0;
  InSize := Total;
  Err := DosSeek(InHandle, 0, 0, Pos);
  if Err <> 0 then
    Fatal('seek error on scratch file: ' + DosErrorText(Err), ExitIO);
end;

{ Uses handle H directly if it is a seekable file, else spools it. }
procedure Prepare(H: Word);
var
  Info: Word;
  EndPos, Pos: LongInt;
  Seekable: Boolean;
begin
  AllocBlocks;
  Seekable := DeviceInfo(H, Info) and ((Info and $80) = 0);
  if Seekable then
    Seekable := (DosSeek(H, 0, 1, Base) = 0) and
                (DosSeek(H, 0, 2, EndPos) = 0) and
                (DosSeek(H, Base, 0, Pos) = 0) and (Pos = Base);
  if Seekable then
  begin
    InHandle := H;
    InOpen := H <> 0;
    InSize := EndPos - Base;
    if InSize < 0 then
      InSize := 0;
  end
  else
    Spool(H);
  { A final Ctrl+Z is the traditional DOS end-of-text marker. }
  if (InSize > 0) and (ByteAt(InSize - 1) = 26) then
    Dec(InSize);
end;

function StdinIsConsole: Boolean;
var
  Info: Word;
begin
  { Device with the "console input" bit set. }
  StdinIsConsole := DeviceInfo(0, Info) and ((Info and $81) = $81);
end;

procedure OpenNamed(const Name: String);
var
  Z: array[0..255] of Char;
  R: Registers;
begin
  ToAsciiz(Name, Z);
  R.AX := $3D00;                   { open, read-only }
  R.DS := Seg(Z[0]);
  R.DX := Ofs(Z[0]);
  MsDos(R);
  if Failed(R) then
    Fatal('cannot open ' + Name + ': ' + DosErrorText(R.AX), ExitIO);
  InName := Name;
  InHandle := R.AX;
  InOpen := True;
  Prepare(R.AX);
end;

procedure OpenStdin;
begin
  InName := '[stdin]';
  Prepare(0);
end;

procedure CloseInput;
begin
  if InOpen then
  begin
    DosClose(InHandle);
    InOpen := False;
  end;
  if TempOpen then
  begin
    DosDelete(TempName);
    TempOpen := False;
  end;
end;

begin
  InOpen := False;
  TempOpen := False;
  InSize := 0;
  InName := '';
end.
