{$Q-,R-,S-,G-}
Unit tfastwrite;

{
WARNING:
Do not use snow checking if calling these routines from an interrupt.
(You should not be writing strings from an interrupt anyway!)

TFASTWRITE:
Yet another "fastwrite" routine (write text directly to screen ram).

Now that 25 years have gone by and I know 8088 assembler to a decent
level, I got fed up with Borland's routines (I see snow even with
CheckSnow true!) and decided to write my own.
However, this unit is much faster than Borland's routines; in fact, it
is likely the fastest implementation possible for a 4.77MHz 8088 with
CGA that fully handles CGA hardware "snow":

- No MULs; uses a lookup table for the "y*80*2" portion of the offset calcs

- Optimal unrolled copy based on 8088 timings

- When PreventSnow is on, both horizontal and vertical retrace are used
when writing strings or doing full-screen copies

- Usual 8088 tricks:  Using SHL; JC/JNC instead of
CMP/TEST... full use of LODS/STOS/MOVS where appropriate...1-byte
opcodes when possible... etc.  I have tried to note this in the code but
ask me if something seems weird.

trixter@oldskool.org, JL20060318

Code revised JL20121013:
  + Wrung a hair more speed out of it, can now copy an 80x25 screen
  in < 50ms with snow checking on
  + added MDA support, and won't check for snow on MDAs

Code revised JL20130627:
  - Adjusted copyscreen chunksize to avoid single scanline character of snow
  + Added more MDA speedups
  + Added write/writeln functionality
}

Interface

Const
  tfPreventSnow:Boolean=False;

var
  tfMaxScrX,tfMaxScrY:byte;
  tfScrSizeInWords:word;

Procedure tfastinit(X,Y:Word);
{Must be called before using the unit; it sets up a lookup table.  This is
done automatically for 80x25; you will have to call this again if you are
using something else like 40x25, 90x30, etc.}

Procedure tfastwritexy(SPtr,destscr:Pointer;X,Y:Word;backfore:Byte);
{Take string s, stick it at scrseg:x,y using attribute byte backfore. This is
very standard stuff, just fast :-)  *This procedure honors the PreventSnow
variable.*}

(* DEPRECATED
Procedure tfastwritexyHiASCII(SPtr,destscr:Pointer;X,Y:Word;backfore:Byte);
{Identical to tFastWriteXY except it automatically highlights any ASCII
character in the range #32-#127 by setting the intensity bit in the
foreground color portion of the attribute byte.}
*)

Procedure tfastclrscr(destscr:Pointer;backfore,filler:Byte);
{Clears the screen using attribute backfore.  Call this *after* tfastinit. No
wait for retrace on this one since there's no point, it's not called often
enough.}

Procedure tfastcopyscreen(sourcescr,destscr:Pointer);
{Copies a hidden screen to visible screen ram.  *This procedure honors the
PreventSnow variable*.}

{These next few implement a "set and forget" write/writeln clone.
Once you set the params, tfastwriteln will do what you expect it to do.}

Procedure tfastsetpos(x,y:word);
Procedure tfastsetcolor(b:byte);
Procedure tfastsetdest(p:pointer);
Procedure tfastwrite_(s:string);
Procedure tfastwriteln(s:string);

Implementation

Uses
  m6845ctl,
  support;

Const
  tftableready:Boolean=False;
  maxscrlines=16384 div (80*2);
  maxscrcols=132;  {for vesa, although I've gotten 90x30 to work on stock CGA}

  {these are for supporting tfastwriteln}
  tfwx:byte=0;
  tfwy:word=0;
  tfwc:byte=0;
  tfwp:pointer=ptr($b800,0); {dummy default value}

Var
  tfOFStable:Array[0..maxscrlines-1] Of Word;
  {bytes would work too as the four lower bits of
  all offsets are 0, but then you'd have to SHL num,4 and that eats
  up the time you're trying to save in the first place}

Procedure tfastinit(X,Y: Word);
{This sets up a lookup table used so that the MULs can be turned into a table.
Yes, I know that you can calc *80 using *64+*16 -- this is still faster.}
Var
  ycount:Byte;

Begin
  If X > maxscrcols Then X := maxscrcols;
  If Y > maxscrlines Then Y := maxscrlines;
  For ycount := 0 To Y Do tfOFStable [ycount] := (ycount * X * 2);
  tfmaxscrx := X; tfmaxscry := Y;
  tfscrsizeinwords := X * Y;
  tftableready := True;
End;

Procedure tfastwritexy(SPtr,destscr: Pointer; X,Y: Word; backfore: Byte); Assembler;
{
CGA "snow" handling OFF notes:  Unless I'm missing something obvious, this
is the fastest routine of its kind for 8088.  If you can optimize it to be
faster on 8088, you win a prize from trixter@oldskool.org.

CGA "snow" handling ON notes:  Eliminates snow by waiting for horizontal
retrace and utilizing vertical retrace if possible.  The tradeoff for using
vertical retrace is that sometimes there is snow *barely visible* in the
*first scanline only* of the visible display, but it is annoying, so you can
undefine PERFECTNOSNOW if you want to speed up the routine 30%-60%.
}

{$DEFINE PERFECTNOSNOW}

Asm
  cmp  tftableready,0      {0 = byte(boolean(false))}
  je   @alldone            {Don't write into an unknown void without the lookup table}

  les  di,destscr          {set up es:di to point to base of destination}
  mov  dx,es               {need this for later comparison}
  mov  si,Y
  shl  si,1                {si=Y * 2 because si is an index into a table of words}
  add  di,[offset tfOFStable+si] {advance es:di to correct row using precalc table}
  mov  ax,X                {grab x,}
  shl  ax,1                {multiply by 2,}
  add  di,ax               {now di = (y*numcols) + (x*2), so es:di points to where we'll start writing}
  mov  ah,backfore         {get attribute byte ready for our STOSW}
  mov  bl,tfPreventSnow    {when we change DS, we lose our vars, so save this}
  push ds
  lds  si,SPtr             {ds:si = string with first byte as length}
  cld
  lodsb                    {grab length of string}
  xor  ch,ch
  mov  cl,al               {use it as our counter}
  jcxz @alldone            {0 length?  get out of here before we write FFFF bytes by mistake}
  {at this point, we have everything we need:}
  {ds:si=source string; cx=length of string; es:di=destination}
  shr  bl,1                {is preventsnow false? (bl=01=true}
  jnc  @writeloopfast      {if so, jump to the fast screen update loop}
  cmp  dh,$b0              {are we writing to the MDA? (dx=$b000)}
  je   @writeloopfast      {if so, jump to the fast screen update loop}
  cmp  dh,$b8              {are we writing to the CGA? (dx=$b800)}
  jne  @writeloopfast      {if not, jump to the fast screen update loop}

  mov  dx,m6845_status
@writeloopslow:
  lodsb                    {grab our character to al}
  xchg bx,ax               {now hide it in bl - xchg bx,ax is 1-byte opcode}
  cli                      {start of critical time}
@WDN:                      {wait until we're out of some random retrace we may have started in}
  in   al,dx               {grab status bits}
  {$IFNDEF PERFECTNOSNOW}
  test al,c_vertical_sync  {are we in vertical retrace?}
  jnz  @blastit            {if so, we've got time to write a word, let's do it!}
  {$ENDIF}
  shr  al,1                {are we in some random horiz retrace?  If so, wait}
  jc   @WDN                {until we're out of it so we can sync properly}
@WDR:                      {wait until we're in either vert or horiz retrace}
  in   al,dx               {grab status bits}
  shr  al,1                {were we in horizontal retrace?}
  jnc  @WDR                {if not, keep waiting}
@blastit:
  xchg bx,ax               {get char back - 1-byte opcode}
  stosw                    {write it out - another 1-byte opcode - we need speed because otherwise we will see snow!}
  sti                      {end of critical time}
  loop @writeloopslow      {keep looping to put the string out}
  jmp  @alldone

@writeloopfast:
  {we unroll this so we can exploit our tiny 4-byte prefetch queue on 8088}
  mov  dx,cx               {preserve original count for later}
  shr  cx,1
  shr  cx,1
  shr  cx,1
  jcxz @handlestragglers   {jump if string length < size that unrolled loop handles}
@copyloopunrolled:
  lodsb                    {load character}
  stosw                    {store attrib+char}
  lodsb                    {in case it wasn't obvious, lodsb and stosw are}
  stosw                    {1 bytes, so we keep the 4-byte prefetch queue}
  lodsb                    {full by doing this.  In case this seems like}
  stosw                    {a waste, go ahead and do your own tests and}
  lodsb                    {you'll see this is the fastest mix of unrolling.}
  stosw                    {I tried multiple combinations and this was the}
  lodsb                    {best result.}
  stosw
  lodsb
  stosw
  lodsb
  stosw
  lodsb
  stosw
  loop @copyloopunrolled
@handlestragglers:
  mov  cx,dx        {cx:=number of times we'll have to do this after the unrolled loop}
  and  cx,00000111b
  jcxz @alldone     {Length was a multiple of the size of the unroll loop (no remainder) so bail}
@copyloopsingle:
  lodsb
  stosw
  loop @copyloopsingle
@alldone:
  pop  ds
End;

(* DEPRECATED
Procedure tfastwritexyHiASCII(SPtr,destscr: Pointer; X,Y: Word; backfore: Byte); Assembler;
{
This isn't as optimized as tfastwritexy as it checks each character for whether
or not it is in the ASCII range 32-127 (a printable character) and, if so,
"highlights" it by setting the intensity bit in the foreground color portion
of the attribute byte.

See tfastwritexy notes for how snow is handled.
}

Asm
  cmp  tftableready,0      {0 = byte(boolean(false))}
  je   @alldone            {Don't write into an unknown void without the lookup table}

  les  DI,destscr          {set up es:di to point to base of destination}
  mov  dx,es               {need this for later comparison}
  mov  si,Y
  shl  si,1
  add  di,word ptr tfOFStable[si]
  mov  AX,X                {grab x,}
  shl  AX,1                {multiply by 2,}
  add  DI,AX               {now di = (y*numcols) + (x*2), so es:di points to screen}
  mov  AH,backfore         {get attribute byte ready for our STOSW}
  mov  BL,tfPreventSnow      {when we change DS, we lose our vars, so save this}
  push DS
  lds  SI,SPtr             {ds:si = string with first byte as length}
  cld
  lodsb                    {grab length of string}
  xor  ch,ch
  mov  CL,AL               {use it as our counter}
  jcxz @alldone            {0 length?  then get out of here before we write FFFF bytes by mistake}
  {at this point, we have everything we need:
  ds:si=source string; cx=length of string; es:di=destination}
  cmp  BL,0                {is preventsnow false?}
  je   @writeloopfast      {if so, jump to the fast screen update loop}
  cmp  dx,ScreenSeg        {are we writing to the traditional segment for screen ram?}
  jne  @writeloopfast      {if not, let's assume there's no need to wait for retrace}

  MOV  DX,m6845_status
  cli                      {necessary evil to ensure no snow}
@writeloopslow:
  and  ah,11110111b        {turn off any highlight we may have set previously}
  lodsb                    {grab our character to al}
  sub  al,32               {subtract our char so that it now ranges from 0 to 127-32}
  cmp  al,127-32           {compare to upper bound of our range}
  ja   @hideit             {if above, don't highlight it}
  or   ah,00001000b        {highlight foreground color}
@hideit:
  add  al,32               {fix our value back to before range comparison}
  xchg bx,ax               {now hide it in bh}
@WDN:                      {wait until we're out of some random retrace we may have started in}
  In   AL,DX               {grab status bits}
  {$IFNDEF PERFECTNOSNOW}
  Test AL,c_vertical_sync  {are we in vertical retrace?}
  jnz  @blastit            {if so, we've got time to write a word, let's do it!}
  shr  al,1                {are we in some random horiz retrace?  If so, wait
  jc   @WDN                {until we're out of it so we can sync properly}
  {$ELSE}
  test al,c_display_enable {are we in some random horizontal sync cycle?}
  jnz  @WDN                {if so, keep waiting}
  {$ENDIF}
@WDR:                      {wait until we're in either vert or horiz retrace}
  In   AL,DX               {grab status bits}
  shr  al,1                {shift bit into carry -- were we in horizontal retrace?}
  jnc  @WDR                {if not, keep waiting}
@blastit:
  xchg bx,ax               {get char back - xchg accum,reg16 is 1-byte opcode and we need that speed (on 8088, size is money!)}
  stosw                    {write it out - stosw is another 1-byte opcode - we need speed because otherwise we will see snow!}
  loop @writeloopslow      {keep looping to put the string out}
  sti                      {restore prior interrupt state}
  jmp  @alldone

@writeloopfast:
  and  ah,11110111b        {turn off any highlight we may have set}
  lodsb                    {load character}
  sub  al,32               {we don't care about values under 32}
  cmp  al,127-32           {compare to range}
  ja   @slamit             {if above, outside of range so don't highlight it}
  or   ah,00001000b        {if printable ASCII,highlight foreground color}
@slamit:
  add  al,32               {fix value back to before range comparison}
  stosw                    {store attrib+char}
  loop @writeloopfast
@alldone:
  pop  DS
End;
*)

Procedure tfastclrscr(destscr:Pointer;backfore,filler:Byte); Assembler;
Asm
  cmp  tftableready,0      {we need this to get sizeinwords}
  je   @cleardone          {Need lookup table for vars to be initialized}
  les  DI,destscr
  cld
  mov  AH,backfore
  mov  AL,filler
  mov  CX,tfscrsizeinwords
  rep  stosw
@cleardone:
End;

Procedure tfastcopyscreen(sourcescr,destscr:Pointer); Assembler;
{
If prevent snow is on, screen ram is updated during vertical and horizontal
retraces only.  This means a full-screen snow-free update can happen about 12
times a second (fast!), thanks to taking advantage of horizontal retrace too.
Much thanks to Richard Wilton for the idea and example code.
}

Const
  horiz_timeout=6;
  vb_chunksize=478; {empirically discovered on a stock IBM 5160}

Asm
  cmp     tftableready,0   {we need this to get sizeinwords}
  je      @finalend        {Don't write into an unknown void without the lookup table}
  mov     CX, tfscrsizeinwords
  mov     AL, tfPreventSnow
  les     DI, destscr
  push    DS
  lds     SI, sourcescr
  mov     dx,es
  cmp     dx,$b000         {are we writing to the MDA?}
  je      @slamit          {if so, jump to the fast screen update loop}
  cmp     AL, 0            {is preventsnow true?}
  ja      @doitnicely      {if so, jump to our screen update loop}

@slamit:
  cld
  rep     movsw            {if not, slam it!!}
  jmp     @donecopy        {...and then exit the routine}

@doitnicely:
  MOV     DX, m6845_status

{write during remaining vertical blanking interval}
@L01:
  mov     bx,cx            {preserve buffer length in BX}
  mov     cx,horiz_timeout {CX := horizontal timeout}
  cli                      {disable interrupts during loop}
@L02:
  in      al,dx            {AL := video status}
  test    al,c_display_enable
  loopnz  @L02             {loop while Display Enable inactive}
  jz      @L03             {jump if loop did not time out}
  movsw                    {copy one word}
  sti
  mov     cx,bx            {CX := buffer length}
  loop    @L01
  jmp     @donecopy        {exit (entire string copied)}

{write during horizontal blanking intervals}
@L03:
  sti                      {enable previous interrupt state}
  mov     cx,bx            {restore CX}
@L04:
  lodsw                    {AL := character code, AH := attribute}
  mov     bx,ax            {BX := character and attribute}
  push    cx               {preserve word loop counter}
  mov     cx,horiz_timeout {CX := timeout loop limit}
  cli                      {clear interrupts during one scan line}
@L05:
  in      al,dx
  test    al,c_display_enable
  loopnz  @L05             {loop during horizontal blanking until timeout occurs}
  jnz     @L07             {jump if timed out (vertical blanking has started)}
@L06:
  in      al,dx
  test    al,c_display_enable
  jz      @L06             {loop while Display Enable is active}
  xchg    bx,ax            {AX := character & attribute}
  stosw                    {copy 2 bytes to display buffer}
  sti                      {restore interrupts}
  pop     cx               {CX := word loop counter}
  loop    @L04
  jmp     @donecopy        {exit (entire string copied)}

{write during entire vertical blanking interval}
@L07:
  pop     bx               {BX := word loop counter}
  dec     si
  dec     si               {DS:SI -> word to copy from buffer}
  mov     cx,vb_chunksize  {CX := # of words to copy}
  cmp     bx,cx
  jnb     @L08             {jump if more than vb_chunksize words remain in buffer}
  mov     cx,bx            {CX := # of remaining words in buffer}
  xor     bx,bx            {BX := 0}
  jmp     @L09
@L08:
  sub     bx,cx            {BX := (# of remaining words) - vb_chunksize}
@L09:
  cld
  rep     movsw            {copy to video buffer}
  mov     cx,bx            {CX := # of remaining words}
  test    cx,cx
  jnz     @L01             {loop until buffer is displayed}

@donecopy:
  pop  DS
@finalend:
End;

Procedure tfastsetpos(x,y:word); begin tfwx:=x; tfwy:=y; end;

Procedure tfastsetcolor(b:byte); begin tfwc:=b; end;

Procedure tfastsetdest(p:pointer); begin tfwp:=p; end;

Procedure tfastwrite_(s:string);
begin
  tfastwritexy(@s,tfwp, tfwx, tfwy, tfwc);
  inc(tfwx,length(s));
end;

Procedure tfastwriteln(s:string);
begin
  tfastwritexy(@s,tfwp, tfwx, tfwy, tfwc);
  tfwx:=0;
  inc(tfwy);
end;

begin
end.
