{
  The originial benchmark program was to demonstrate the speed difference
  between the POS() in Turbo Pascal 4 or 5 brute-force
  and the Boyer-Moore method function POSBM()
  Program author: Costas Menico

   Call: posbm(pat,buf,buflen);
   or if you are using a string buffer:
         posbm(pat,s[1],length(s));
}

program bufSearch;

uses
  dos;


{$F+}
function posbm(pat:string; var buf; buflen:word):word; EXTERNAL;
{$L BM.OBJ}
{$F-}

function bruteForce(var such:string; var buf; buflen:word):word; ASSEMBLER;
ASM
        cld
        push ds
        les        di,buf
        mov        cx,buflen
        jcxz @@30
        lds        si,such
        mov  al,[si]
        or   al,al
        je   @@30
        xor  ah,ah
        cmp  ax,cx
        ja   @@30
        mov  bx,si
        dec  cx
  @@10:
        mov  si,bx
        lodsw
        xchg al,ah          { AH=Stringl„nge, AL=Suchchar }
        repne scasb
        jne  @@30
        dec  ah
        or   ah,ah
        je   @@20

        inc  cx             { CX++ nach rep... }
        xchg cx,ax
        mov  cl,ch
        xor  ch,ch
        mov  dx,di
        repe        cmpsb
        mov  di,dx
        mov  cx,ax
        loopne @@10
  @@20:
        mov  ax,buflen
        sub  ax,cx
        dec  ax
        jmp  @@40
  @@30:
        xor  ax,ax
  @@40:
        pop  ds
end;



procedure showtime(s : string; t : registers);

begin
  writeln(s, ' Hrs:', t.ch, ' Min:', t.cl, ' Sec:', t.dh, ' Milsec:', t.dl);
end;

var
  pat    : string;
  i,
  j      : integer;
  start,
  finish : registers;
  arr    : array[1..4096] of char;

const
  longloop = 1024; {iterations to test}

begin
  randomize;
  for i := 1 to 4096 do
    arr[i] := chr(random(255)+1);

  move(arr[4090],pat[1],5); pat[0]:=#5;

  writeln('Search using Brute-Force Method <please wait>');
  start.ah := $2C;
  msdos(start);
  for j := 1 to longloop do
    i := bruteForce(pat,arr,4096);
  finish.ah := $2C;
  msdos(finish);
  showtime('Start  ', start);
  showtime('Finish ', finish);
  writeln('Pattern found at position ', i);
  writeln;
  writeln('Search using Boyer-Moore Method <please wait>');
  start.ah := $2C;
  msdos(start);
  for j := 1 to longloop do
    i := posbm(pat, arr,4096);
  finish.ah := $2C;
  msdos(finish);
  showtime('Start  ', start);
  showtime('Finish ', finish);
  writeln('Pattern found at position ', i);
  writeln;
end.
