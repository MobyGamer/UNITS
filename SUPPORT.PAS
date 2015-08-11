{$O+,F+}
{$R-,S-,G-,Q-}
{
Boring generic support routines, JL20041013.  My old generalfunctions unit
of 17+ years was starting to creep me out (I code a lot better now than I
did as a teenager) so I decided to start over.
Last updated: 20121028
}

unit support;

interface

const
  HexNybble:array[0..15] of char='0123456789ABCDEF';
  vidp:pointer=ptr($b800,0);
  maxbufsize=$FFFF+1-16;

var
  TicksSinceMidnight:longint ABSOLUTE $0040:$006C;
  DriveMotorStatus:Byte ABSOLUTE $0040:$003F;

type
  s79=string[79];
  s12=string[12];
  str2=string[2];

Function FileExists(filename:String):Boolean;
Function SizeOfFile(filename:string):longint;
Function IntToStr(I:LongInt):s12;
Function StrToInt(s:s12):LongInt;
Function RealToStr(r:real):string;
Function StrToReal(s:s79):real;
Function NumToExt(w:word):s12;
Function ReadKeyChar:Char;
Function KeyPressed:Boolean;
Function upstring(s:string):string;
Function upchar(c:char):char;
Function EXEsize(fname:string):longint;
Function DiskReady(Drive:char):boolean;
Function hex(l:longint):s12;
Function hexword(w:word):s12;
Procedure moveword(src,dst:pointer;size:word); {Built for speed, DOES NOT HANDLE OVERLAPPING BLOCKS AT ALL!}
Procedure fillword(dst:pointer;size:word;filler:byte);
Procedure FatalError(errnum:byte;s:string);
Function BuffersEqual(p1,p2:pointer;size:word):word; {compares two buffers; reports 0 if equal, or offset where not}
Function p2l(p:pointer):longint; {converts an x86 16-bit seg:ofs pointer to a 20-bit linear offset}
function l2p(l:longint):pointer; {converts a 20-bit linear offset to an x86 16-bit seg:ofs pointer}
Function SubPtr(p:Pointer;d:LongInt):Pointer;
Function AddPtr(p:Pointer;d:LongInt):Pointer;
Function NormPtr(p:pointer):pointer; {Normalizes an x86 16-bit seg:ofs pointer}
Function split(line:string;delimiter:char;position:byte):string;
Function GetTimer:word;
Procedure PreserveDOSScreen;
Procedure RestoreDOSScreen;
Procedure CursorON;
Procedure CursorOFF(page:byte);
Procedure CursorMoveTo(x,y,page:byte);
procedure SlamString80x25(x,y:integer;s:string;attr:byte);
{extremely fast and compact way to put text onto an 80x25 screen at page 0}
function root(x,y:real):real; {find xth root of y}
function gcd(a,b:longint):longint; {greatest common divisor (recursive)}
function gcd_i(a,b:longint):longint; {greatest common divisor (iterative)}
function lcm(i,j:longint):longint; {least common multiple}
function ticks2micro(l:longint):longint;
function ticks2ms(l:longint):longint;
(*Function HexNybble(b:byte):char; {converts nybble to ascii hex equivalent}*)
Function ByteToHex(b:byte):str2; {converts byte to ascii hex equivalent}
Function HexCharToByte(c:char):byte;
Function HexStrToLong(s:string):longint;
Function IntPadded(l:longint;num:byte;padc:char):s12; {returns value padded with num padchars}
Procedure WaitFloppySpindown;
procedure doswrite(s:string);
procedure doswriteln(s:string);
Procedure FileToSTDOUT(filename:string);
function SearchString(var s:string; var buf; buflen:word):word; {returns position found in buffer, or $FFFF if not found}
Function SimpleMenu(title,m:string):byte;
{Simple menu.
If EXIT or anything above it is chosen, 0 is returned, signifying an exit.}
Function InV86:boolean; {returns TRUE if we are already in protected mode}
Function DosVer:word; {returns DOS version lo(major) hi(minor) number}
Function curdate:s12;
Function basename(ins:string):string; {returns filename without extension}
Procedure tSeek(Var f : Text; n : LongInt);

implementation

uses
  DOS;

{preserve DOS screen stuff}
var
  oldcursorsize,oldcursorpos:word;
  oldvideomode,oldvideopage:byte;
  screenp:pointer;

{end DOS screen preserve}

Function DiskReady(Drive:char):boolean;
var
  ChkDrvBuf : array[0..512] of byte;  {for drive checking routine}

begin
  {original code by Brian Pape with mods by G. Davis}
  asm
    cmp  drive,'a'
    jb   @isupcase
    sub  drive,20H  { make it UPPER case }
    @isupcase:
    cmp  drive,'Z'
    jb   @driveok
    mov  drive,'A'  { if drive isn't between 'A' and 'Z', make it A) }
    @driveok:
    mov  ax, seg ChkDrvBuf
    mov  es, ax
    mov  bx, offset ChkDrvBuf

    mov  ah, 02  { read disk sectors }
    mov  al, 1   { number of sectors to transfer }
    mov  ch, 1   { track number }
    mov  cl, 1   { sector number }
    mov  dh, 1   { head number }

    mov  dl, drive
    sub  dl, 'A'     { subtract ORD of 'A' }

    int  13h

    mov  bl,true { assume drive is ready }
    and  ah,$80
    jz   @done   { error was something other than disk not ready }
    mov  bl,false{ disk wasn't ready. store result }
    @done:

    mov  ax,$0000  { reset drive }
    INT  13H

    xor  ax,ax   { shut off disk drive quickly }
    mov  es,ax
    mov  ax,440h
    mov  di,ax
    mov  byte ptr es:[di],01h

    mov  al,bl   { retrieve result }
  end;
end;  { diskready }

Function EXEsize(fname:string):longint;
Type
  t_size = Record
    mz:Array [1..2] of Char;
    remainder,
    pages:Word;
  end;

Var
  f:File of t_size;
  sz:t_size;

begin
  assign(f,fname);
  {$i-}
  reset(f);
  {$i+}   { io checking should be off }
  if (ioresult <> 0)
    then exesize:= 0
    else begin
      read(f,sz);
      close(f);
      With sz do exesize := remainder + (pred(pages) * 512);
    end;
end;

Function upstring(s:string):string; assembler;
asm
  push  ds
  cld
  lds   si,s
  les   di,@result
  lodsb
  stosb
  xor   ah,ah
  xchg  ax,cx
  jcxz  @done

@upstringloop:
  lodsb
  cmp   al,'a'
  jb    @noconvert
  cmp   al,'z'
  ja    @noconvert
  sub   al,20h
@noconvert:
  stosb
  loop  @upstringloop

@done:
  pop   ds
end;

Function upchar; assembler;
asm
  mov   al,c
  cmp   al,'a'
  jb    @noconvert
  cmp   al,'z'
  ja    @noconvert
  sub   al,20h
@noconvert:
end;

(*Function upstring(name:string):string;
var
  loop:byte;
begin
  for loop := 1 to Length(name) do
    upstring[loop] := UpCase(name[loop]);
  upstring[0]:=name[0];
end;*)

Function FileExists(filename:String):Boolean;
Var
  f:File;
Begin
  Assign(f,filename);
  {$I-}
  Reset(f);
  Close(f); {need this or you run out of file handles calling me repeatedly!}
  {$I+}
  FileExists:=(IOResult = 0);
End;

Function SizeOfFile(filename:string):longint;
Var
  f:File;
  foo:LongInt;
Begin
  If fileexists(filename) Then Begin
    Assign(f,filename);
    Reset(f,1);
    foo:=FileSize(f);
    Close(f);
    sizeoffile:=foo;
  End Else SizeOfFile:=-1;
End;

Function IntToStr;
Var
  S:s12;
Begin
  Str(I,S);
  IntToStr:=S;
End;

Function StrToInt;
var
  i:LongInt;
  foo:Integer;
Begin
  Val(S,i,foo);
  strtoint:=i;
End;

Function RealToStr;

Var
  s:String;

begin
  {if exponent is bigger than 1E7 or smaller than 1E-7, perform unformatted conversion}
  if ((r>1E-7) and (r<1E7))
    then Str(r:12:12, s)
    else Str(r, s);
  {delete trailing zeros, periods and leading spaces}
  While s[ord(s[0])]='0' do Delete(s, ord(s[0]), 1);
  While (s[1]=' ') do Delete(s, 1, 1);
  if s[ord(s[0])]='.'
    then Delete(s, ord(s[0]), 1);

  RealToStr:=s;
end;

Function StrToReal;
var
  r:real;
  error:integer;
Begin
  Val(s,r,error);
  if error=0
    then StrToReal:=r
    else StrToReal:=0;
End;

Function NumToExt;
var
  s:s12;
begin
  s:=IntToStr(w);
  if w < 100 then s:='0'+s;
  if w < 10 then s:='0'+s;
  NumToExt:=s;
end;

Function KeyPressed:Boolean; Assembler;
Asm
  mov ah, 01h
  int 16h
  mov ax, 00h
  jz @1
  inc ax
  @1:
end;

Function ReadKeyChar:Char; Assembler;
Asm
  mov ah, 00h
  int 16h
  cmp al,0
  jne @endit
  mov al,ah
@endit:
end;

Function hex;
Var
  s:s12;
Begin
  s:='';
  If l=0
    Then s:='0'
    Else While l<>0 Do Begin
      s:=hexNybble[(l And $f)]+s;
      l:=l ShR 4;
    End;
  hex:=s;
End;

Function hexword;
Var
  s:S12;
Begin
  s:='';
  If w=0
    Then s:='0'
    Else While w<>0 Do Begin
      s:=hexNybble[(w And $f)]+s;
      w:=w ShR 4;
    End;
  while byte(s[0])<4 do s:='0'+s; {pad to 4 characters}
  hexword:=s;
End;

procedure moveword(src,dst:pointer;size:word); assembler;
{DOES NOT HANDLE OVERLAPPING BLOCKS AT ALL!}
asm
  push ds
  les  di,dst
  cld  {put cld here so it can be prefetched during the slow LES opcode}
  lds  si,src
  mov  cx,size
  shr  cx,1    {if number is odd, bit will be shifted off into carry flag}
  rep  movsw
  adc  cx,cx   {if carry set cx=1 else cx=0}
  rep  movsb   {if cx=0 nothing happens. Why we do this? To avoid costly JMP!}
  pop  ds
end;

procedure fillword;assembler;
asm
  les  di,dst
  cld  {put cld here so it can be prefetched during the slow LES opcode}
  mov  al,filler
  mov  ah,al {fill AX with filler byte}
  mov  cx,size
  shr  cx,1 {adjust for words; if number is odd, bit will be shifted off into carry flag}
  rep  stosw {fill}
(*
  jnc  @end {if no carry, we're done}
  stosb {otherwise, number was odd so we had another byte to do}
@end:
*)
  adc  cx,cx {if carry set, cx=1 else cx=0}
  rep  stosb {if cx=0, nothing happens}
end;

function BuffersEqual;assembler;
asm
  push ds
  lds si,p1
  les di,p2
  mov cx,size
  xor ax,ax {assume test will be successful}
  cld
  repe cmpsb
  cmp cx,0
  je @done
  mov ax,size {if cx<>0 then buffers are not equal}
  sub ax,cx
  dec ax {to report offset instead of absolute location}
@done:
  pop ds
end;

procedure fatalerror;
begin
  asm
    {clrscr}
    mov ax,0600h
    mov bh,07
    xor cx,cx
    mov dx,184fh {mov dh,24; mov dl,79}
    int 10h
    {re-home cursor}
    mov ah,2
    xor bh,bh {page 0}
    xor dx,dx
    int 10h
  end;
  writeln('Fatal #',errnum,': ',s);
  halt(errnum);
end;

Function P2L(p: Pointer): LongInt; Assembler;
{Converts an x86 16-bit seg:ofs pointer to a linear address}
Asm
   mov ax,word ptr [p+2] {seg}
   mov dx,ax
   mov cl,12             {ssssssssssssssss:ssssssssssssssss}
   shr dx,cl             {000000000000ssss:ssssssssssssssss}
   mov cl,4
   shl ax,cl             {000000000000ssss:ssssssssssss0000}
   add ax,word ptr [p]   {000000000000ssss:oooooooooooooooo}
   adc ax,0              {000000000000sssS:oooooooooooooooo}
End;

Function L2P(l: LongInt): Pointer; Assembler;
{converts 20-bit linear offset into seg:ofs pointer}
Asm
   mov dx,word ptr [l+2]
   mov ax,word ptr [l]
   mov bx,ax
   and ax,0Fh              {so that :AX returns only remainder}
   mov cl,4
   shr bx,cl               {divide ofs by 16 to get quotient}
   mov cl,12
   shl dx,cl
   add dx,bx
End;

Function NormPtr(p: Pointer): Pointer; Assembler;
{Normalizes an x86 16-bit seg:ofs pointer.}
{  NormPtr:=l2p(p2l(p));}

Asm
   mov dx,word ptr [p+2] {seg}
   mov ax,word ptr [p]   {ofs}
   mov bx,ax             {bx=ofs}
   and ax,0Fh            {ax=offset remainder}
   mov cl,4
   shr bx,cl             {bx=ofs div 16=num paragraphs}
   add dx,bx             {increase seg by # of paragraphs}
End;

Function SubPtr(p:Pointer;d:LongInt):Pointer;
Begin
  SubPtr:=L2P(P2L(p)-d)
End;

Function AddPtr(p:Pointer;d:LongInt):Pointer;
Begin
  AddPtr:=L2P(P2L(p)+d);
End;

Function split(line:string;delimiter:char;position:byte):string;
const
  maxoffset:byte=0;
  maxsplitsperline=40;

var
  loop:byte;
  offsets:array[0..maxsplitsperline] of byte;
  tempstr:string;
begin
  maxoffset:=0;
  fillchar(offsets,0,sizeof(offsets));
  (* Get list of offsets first *)
  (* first entry is always 0 *)
  offsets[maxoffset]:=0;
  maxoffset:=1;
  for loop:=1 to length(line) do begin
    if line[loop]=delimiter
      then begin
        offsets[maxoffset]:=loop;
        inc(maxoffset);
      end;
  end;
  (* Last entry is always maximum end of string *)
  offsets[maxoffset]:=length(line)+1;
  (* Now that we have a list of offsets, use them *)
  if position<=maxoffset
  (* if the user is asking for a split part that will exist *)
    then begin
      tempstr:=copy(line,offsets[position-1]+1,offsets[position]-offsets[position-1]-1);
    end else begin
    (* else, supply bogus value as error *)
      tempstr:=#0;
    end;
  split:=tempstr;
end;

Function GetTimer:word;assembler;
{gets low word of timer and returns it in AX}
{If using this for timing, remember that it is always counting DOWN}
asm
  MOV  AL,00000110b  {Channel 0, Latch Counter, Square Wave, Binary}
  OUT  43h,AL        {Tell timer about it}
  IN   AL,40h        {Get LSB of timer counter}
  MOV  AH,AL         {Save it in AH for a second}
  IN   AL,40h        {Get MSB of timer counter}
  XCHG AH,AL         {Put things in the right order; return in AX}
end;

Procedure CursorOFF;assembler;
asm
  {first get existing cursor, then set it to disappear}
  mov ah,3
  mov bh,page
  int 10h
  mov oldcursorsize,cx
  mov ah,1
  mov cx,2000h
  int 10h
end;

Procedure CursorON;assembler;
{this is meant to be called after a CursorOFF, otherwise results unpredictable!}
asm
  mov ah,1
  mov cx,oldcursorsize
  int 10h
end;

Procedure CursorMoveTo;assembler;
asm
  mov dh,y {row}
  mov dl,x {col}
  mov ah,2
  mov bh,page
  int 10h
end;

Procedure PreserveDOSScreen;
begin
  getmem(screenp,80*25*2);
  moveword(vidp,screenp,80*25*2);
  {first get existing cursor, then set it to disappear}
  asm
    {get old video mode and page}
    mov ah,0fh
    int 10h
    mov oldvideomode,al
    mov oldvideopage,bh
    {get cursor size and position}
    mov ah,3
    int 10h
    mov oldcursorsize,cx
    mov oldcursorpos,dx
  end;
end;

Procedure RestoreDOSScreen;
begin
  asm
    {restore old video mode}
    mov ah,00
    mov al,oldvideomode
    int 10h
    {put cursor back to old location}
    mov ah,2
    mov bh,oldvideopage
    mov dx,oldcursorpos
    int 10h
    {put cursor back to old size}
    mov ah,1
    mov cx,oldcursorsize
    int 10h
  end;
  {restore screen data}
  moveword(screenp,vidp,80*25*2);
  freemem(screenp,80*25*2);
end;

procedure SlamString80x25(x,y:integer;s:string;attr:byte);assembler;
{extremely fast and compact way to put text onto an 80x25 screen at page 0}
asm
  mov bx,y
  shl bx,1
  mov ax,bx
  shl bx,1
  shl bx,1
  add ax,bx
  add ax,$b800
  mov es,ax     { es:=$B800 + (Yx$80 + Yx$20) shr 4 or $B800+Y*$A }
  mov di,x
  shl di,1      { di:=x shl 1 }

  mov ah,attr
  push ds
  lds si,s
  lodsb
  mov cl,al
  xor ch,ch
@1:
  lodsb
  stosw
  loop @1

  pop ds
end;

function root(x,y:real):real;
{find the xth root of y}
begin
  root:=exp(ln(y)/x);
end;

function gcd(a,b:longint):longint;
begin
  if b = 0
    then gcd:=a
    else gcd:=gcd(b,a mod b)
end;

{!! should probably convert this to http://en.wikipedia.org/wiki/Binary_GCD_algorithm at some point}

function gcd_i(a,b:longint):longint;
var
  t:longint;
begin
  while b<>0 do begin
    t := b;
    b := a mod b;
    a := t;
  end;
  gcd_i:=a;
end;

function lcm(i,j:longint):longint;
begin
  lcm:=abs((i*j) div gcd_i(i,j));
end;

function ticks2micro(l:longint):longint;
{converts number of ticks to microseconds}
const
  ticktime=0.8381;
begin
  ticks2micro:=trunc(l / ticktime);
end;

function ticks2ms(l:longint):longint;
{converts number of ticks to milliseconds}
const
  ticktime=0.8381;
begin
  ticks2ms:=round((l/ticktime) / 1000);
end;

(*
Function HexNybble(b:byte):char; assembler;
{thanks to Norbert Juffa}
asm
  mov al,b
  cmp al,10       {if x<10, set CF=1}
  sbb al,69h      {0-9: 96h..9Fh, A-F: A1h..A6h}
  das             {0-9: subtr. 66h -> 30h-39h;
                   A-F: subtr. 60h -> 41h-46h}
end;
*)

(* if you want more speed, copy this into your module that uses it:
Function HexNybble(w:word):char;
inline(
  $58/               {pop    ax}
  $3C/$0A/           {cmp    al,0A}
  $1C/$69/           {sbb    al,69}
  $2F                {das}
); *)

Function ByteToHex(b:byte):str2; assembler;
asm
  les di,@result          {note our destination}
  mov al,2                {choose our length}
  stosb                   {write it}
  mov al,b                {grab and prepare input}
  mov ah,al               {copy to ah}
  shr ah,1                {shift ah to be a nybble}
  shr ah,1                {shift ah to be a nybble}
  shr ah,1                {shift ah to be a nybble}
  shr ah,1                {shift ah to be a nybble}
  and al,00001111b        {mask out unwanted bits}
  mov bx,offset HexNybble {point to our translation table}

  {these next four lines cannot change order:}
  xlat                    {translate al}
  xchg ah,al              {swap with ah}
  xlat                    {translate "ah"}
  stosw                   {store result to destination string}
end;

Function HexCharToByte(c:char):byte;
{ranges (ascii): 48-57, 65-70}
begin
  c:=upcase(c);
  if c in [#65..#70]
    then HexCharToByte:=byte(c)-(65-10)
    else HexCharToByte:=byte(c)-48;
end;

Function HexStrToLong(s:string):longint;
{returns hexadecimal string as decimal value - very unoptimized routine!}
VAR
  Len   : byte absolute S;
  Loop  : byte;
  Li    : longint;
  Num   : longint;

BEGIN
  {treat any leading characters in the string}
  if S [1] = '$' then delete (S, 1, 1);
  if upcase (S [Len]) = 'H' then dec (S [0]);
  Num := 0;
  for Loop := 1 to Len do begin
    Li := 0;
    while (HexNybble[Li] <> S [Loop]) and (Li < 16) do inc (Li);                            { inc counter }
    if Li = 16 then begin
      Num := -1;                           { -1 if invalid }
      exit;
    end;
    Num := Num + Li shl ((Len - Loop) * 4);   { add to Num }
  end;
  HexStrToLong := Num;                          { return value }
END;

Function IntPadded; {returns value padded with num 0's}
Var
  s:s12;
Begin
  str(l,s);
  while byte(s[0])<num do s:=padc+s; {pad to num characters}
  IntPadded:=s;
End;

Procedure WaitFloppySpindown;
{Waits for all floppy drives to spin down, or 5 seconds, whichever comes
first.  This is desirable because many 486 and lower computers slow down to
8MHz while the floppy drive is operational (for compatibility with old copy
protection schemes, amongst other reasons).}
const
  maxWaitSecs=5; {wait up to five secs for the disk drive motors to shut off}
  threshold=trunc(maxWaitSecs*18.2);
var
  l:longint;
begin
  l:=TicksSinceMidnight;
  repeat
    asm
      hlt {do nothing; wait for something interesting}
    end;
  until (DriveMotorStatus and $0F=0) or (TicksSinceMidnight-l > threshold);
  {wait an additional second, as some machines need more safety margin}
  l:=TicksSinceMidnight;
  repeat
    asm
      hlt {do nothing; wait for something interesting}
    end;
  until (TicksSinceMidnight-l > 18);
end;

Procedure FileToSTDOUT(filename:string);
var
  f:text;
  s:string[79];
begin
  assign(f,filename);
  reset(f);
  while not eof(f) do begin
    readln(f,s);
    doswriteln(s);
  end;
  close(f);
end;

procedure doswrite(s:string); assembler;
asm
  push    ds
  cld
  lds     si,s
  lodsb
  xor     ah,ah
  xchg    cx,ax           {cx=#0 of string which contains length}
  jcxz    @exit           {if string is length 0 then bail}
  mov     ah,2            {get ready for DOS func. INT 21,2 - Standard Output}
@L1:
  lodsb
  mov     dl,al           {ah=02, dl=character to output}
  int     21h             {do it}
  loop @L1
@exit:
  pop     ds
end;

procedure doswriteln(s:string);
begin
  doswrite(s+#13#10);
end;

function SearchString(var s:string; var buf; buflen:word):word; assembler;
{returns position found in buffer, or $FFFF if not found}
ASM
  push    ds                {preserve DS (pascal requirement)}
  les     di,buf            {es:di=buffer search space}
  mov     cx,buflen         {cx=length of buffer}
  jcxz    @fail             {if buffer length 0, don't bother searching}
  lds     si,s              {ds:si=string to match}
  mov     al,[si]           {load string length}
  or      al,al             {if 0, zf=1}
  je      @fail             {if string length 0, don't bother searching}
  xor     ah,ah             {ax=string length}
  cmp     ax,cx             {compare string length to buffer size}
  ja      @fail             {if string length > buffer size, don't bother}
  mov     bx,si             {bx=string index}
  dec     cx                {}
  cld                       {search FORWARD please}
@L1:
  mov     si,bx             {reset string index pos}
  lodsw                     {load lengthbyte and firstbyte of string}
  xchg    al,ah             {ah=string length, al=search character}
  repne   scasb             {search for the character}
  jne     @fail             {didn't find it at all?  Then it's not present}
  dec     ah                {decrement string length}
  or      ah,ah             {}
  je      @finished         {if length=0, we're done searching}

  inc     cx                {}
  xchg    cx,ax             {}
  mov     cl,ch             {}
  xor     ch,ch             {cx=string length}
  mov     dx,di             {dx=buffer pos}
  repe    cmpsb             {compare string to buffer}
  mov     di,dx             {di=buffer pos}
  mov     cx,ax             {}
  loopne  @L1               {}
@finished:
  mov     ax,buflen         {}
  sub     ax,cx             {}
  dec     ax                {ax=position the string was found}
  jmp     @done             {}
@fail:
  mov     ax,0ffffh         {FFFF means failure}
@done:
  pop     ds                {restore DS (pascal requirement)}
end;

Function SimpleMenu(title,m:string):byte;
{Simple menu.
If EXIT or anything above it is chosen, 0 is returned, signifying an exit.}
var
  b:byte; curmax:byte;
begin
  write(#13#10,title,#13#10); for b:=1 to length(title) do write('-'); writeln;
  curmax:=1; write(curmax,'. ');
  for b:=1 to length(m) do begin
    case m[b] of
    '~':begin inc(curmax); write(#13#10,curmax,'. '); end;
    else write(m[b]);
    end;
  end;
  inc(curmax); write(#13#10,curmax,'. Exit');
  writeln;
  b:=strToInt(readkeychar);
  if b>=curmax then b:=0;
  SimpleMenu:=b;
end;

function InV86:boolean;assembler;
asm
  xor  ax,ax
  cmp  System.Test8086,2
  jl   @done
  db   $0f,$20,$c0 {mov eax,cr0} {get status of protected mode}
  and  al,1                      {bit 1 is protected mode flag}
(*
  test ax,1                      {test if protmode flag is up}
  mov  al,0
  jz   @done                     {if not, we're done}
  mov  al,1                      {otherwise, continue and put up a flag}
*)

@done:
end;

function DOSVer:word;assembler;
asm
  mov     ah,30h
  int     21h     {al=maj, ah=min}
end;

function curdate:s12;
var
  h, m, s, hund : Word;

  function LeadingZero(w : Word) : String;
  var
    s : String;
  begin
    Str(w:0,s);
    if Length(s) = 1 then
      s := '0' + s;
    LeadingZero := s;
  end;

begin
  GetTime(h,m,s,hund);
  curdate:=LeadingZero(h)+':'+LeadingZero(m)+':'+LeadingZero(s)+'.'+LeadingZero(hund);
end;

Function basename(ins:string):string;
{chops extension off of a filename}
var
  b:byte;
begin
  for b:=0 to 3 do if ins[length(ins)-b]='.'
    then delete(ins,length(ins)-b,b+1);
  basename:=ins;
end;

Procedure tSeek(Var f : Text; n : LongInt); Assembler;
{MARCO MILTENBURG's procedure for seeking in a text file}
Asm
  push  DS
  push  BP

  lds   SI, f
  lodsw                                 { handle }
  mov   BX, AX

  mov   CX, Word ptr [BP+8]
  mov   DX, Word ptr [BP+6]

  mov   AX, 4200h                       {AL = 2, AH = 42}
  int   21h

  les   DI, f
  mov   AX, DI
  add   AX, 8
  mov   DI, AX

  lodsw                                 { mode }
  lodsw                                 { bufsize }
  mov   CX, AX                          { CX = number of Bytes to read }
  lodsw                                 { private }
  lodsw                                 { bufpos  }
  lodsw                                 { bufend  }
  lodsw                                 { offset of Pointer to Textbuf }
  mov   DX, AX                          { DX = offset of Textbuf }
  lodsw
  mov   DS, AX                          { DS = segment of Textbuf }
  mov   AH, 3Fh
  int   21h
  push  AX                              { Save AX on stack }

  les   DI, f                           { ES:DI points to f }
  mov   AX, DI                          { Move Pointer to position 8 }
  add   AX, 8
  mov   DI, AX

  mov   AX, 0                           { Bufpos = 0 }
  stosw
  pop   AX                              { Bufend = number of Bytes read }
  stosw

  pop   BP
  pop   DS
end; { tSeek }


begin
  If Mem[$0000:$0449]=7
    then vidp:=ptr($b000,0)
    else vidp:=ptr($b800,0);
end.
