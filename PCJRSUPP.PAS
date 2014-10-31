unit PCjrSupport;
{quick'n'dirty PCjr (and Tandy 1000) support routines}

interface

const
  SNReg=$C0;
  SNFreq=3579540;
  SNMplxr=$61; {MC14529b sound multiplexor chip in the PCjr}
  curpageaddr:pointer=ptr($b800,0000);


var
  jrPageRegs:word; {HI=CRT page register; LO=CPU page register}
  {CRT reg = which 16K or 32K chunk is currently displayed}
  {CPU reg = which 16K or 32K chunk is currently active at $b800 (and $1800)}

{video routines}
procedure jrInit160x200;     {inits 160x200x16 mode}
procedure jrInit160x100;     {inits 160x100x16 mode}
procedure jrInitPageFlip;    {inits 2nd CPU page for pageflipping}
procedure jrPageFlip;        {flips active (CPU) and visible (CRT) pages}
procedure jrClosePageFlip;   {sets active (CPU) page to visible (CRT) page}
procedure jrClearPage(color:byte);
                             {clears active page to color}
procedure jrChangeIndexColor(index,color:byte);
                             {changes color index to any color value}
procedure jrSortPaletteRGB;  {sorts palette by RGB values}
procedure jrSortPaletteComp; {sorts palette by composite color values}
procedure BIOSWriteG(x,y:byte;color:byte;s:string);
                             {writes a string in graphics mode}
Procedure jrSetPix160x100(x,y:word;color:byte);
                             {Sets a 160x100x16 pixel}


{audio routines}
Procedure jrInitAudio;       {points PCjr audio multiplexor to 3-voice chip}
Procedure jrSetAudio(chan:byte;freq:word;volume:byte); {volume is 0-15}
Procedure jrCloseAudio;      {halts channels, points to 1-voice speaker}

implementation

uses
  m6845ctl;

const
  flipping:boolean=false; {is pageflipping active?}
  pageRegsPort=$3df;
  vidGateArrayPort=$3da;
  vidAddressMode:byte=$01;
  {bits $00 = all alpha modes, $01 = lowres graphics, $11=highres graphics}

{===== Video Routines =====}

procedure jrInit160x200; assembler;
{INT 10,5 - Select Active Display Page
  AH = 05
  for PCjr only:
  AL = 80h to read CRT/CPU page registers
       81h to set CPU page register
     BL = CPU page register
       82h to set CRT page register
     BH = CRT page register
       83h to set CPU and page registers
     BH = CRT page register
     BL = CPU page register
  on return: (PCjr only)
  BH = CRT page register
  BL = CPU page register
}

asm
  mov     ax,0008h        {init 160x200x16 mode}
  int     10h
  mov     ax,0580h        {grab CRT/CPU page registers}
  int     10h
  mov     jrPageRegs,bx   {hold onto them for later}
  mov     vidAddressMode,$01 {lowres graphics}
end;

procedure jrInit160x100; assembler;
{
Okay, this is brilliant:  If you set the CRT and CPU page registers
with the WRONG video addressing mode bits 7-6, you can get double or
mismatched pixels.  PCjr tech ref states "These bits control whether
the row scan addresses are used as part of the memory address."

I believe I'm the first to discover this, a true 160x100x16 mode for
PCjr  :-D  \o/   /o/   \o\   /o/   \o\
}

asm
  mov     ax,0008h        {init 160x200x16 mode}
  int     10h
  mov     ax,0580h        {grab CRT/CPU page registers}
  int     10h
  mov     jrPageRegs,bx   {hold onto them for later}
  mov     vidAddressMode,$00 {lower! graphics}

  {We need to set CRT and CPU page registers with "wrong" video addressing
  bits to get the double-pixels to show up}
  mov     al,vidAddressMode       {load addressing mode}
  mov     cl,2
  ror     al,cl                   {addressing mode into bits 7-6}
  inc     cx
  shl     bl,cl                   {cpu page into bits 5-3}
  or      al,bl                   {vv888???}
  or      al,bh                   {vv888ccc}
  mov     dx,pageRegsPort
  out     dx,al                   {set CRT and CPU page registers}

end;

procedure jrInitPageFlip; assembler;
{this should leave the existing image visible on the screen, but further
writes to b800 will go to the hidden page}
asm
  mov     bx,jrPageRegs
  dec     bx              {pick CPU page (BL) one lower than existing to be active}
  mov     jrPageRegs,bx   {update variable}
  mov     ax,0583h        {set both CRT and CPU regs at same time}
  int     10h
  mov     flipping,1
end;

procedure jrPageFlip; assembler;
asm
  cmp     flipping,1
  jne     @done
  mov     bx,jrPageRegs
  xchg    bh,bl                   {swap CRT and CPU page regs}
  mov     jrPageRegs,bx           {update variable}
  (* too slow, waits for retrace which is not necessarily what we want
  mov     ax,0583h                {set both CRT and CPU regs at same time}
  int     10h
  *)
  mov     al,vidAddressMode       {load addressing mode}
  mov     cl,2
  ror     al,cl                   {addressing mode into bits 7-6}
  inc     cx
  shl     bl,cl                   {cpu page into bits 5-3}
  or      al,bl                   {vv888???}
  or      al,bh                   {vv888ccc}
  mov     dx,pageRegsPort
  out     dx,al                   {set CRT and CPU page registers}
@done:
end;

procedure jrClosePageFlip; assembler;
{this should leave the existing image visible on the screen and set writes
back to the same visible screen
writes to b800 will go to the hidden page}
asm
  mov     bx,jrPageRegs
  mov     bl,bh           {set CPU reg to same as CRT reg}
  mov     jrPageRegs,bx   {update variable}
  mov     ax,0583h        {set both CRT and CPU regs at same time}
  int     10h
  mov     flipping,0
end;

procedure jrChangeIndexColor(index,color:byte); assembler;
asm
  mov     dx,vidGateArrayPort
  mov     al,index
  and     al,$0f          {strip unused bits to be safe}
  or      al,$10          {turn into register number}
  out     dx,al           {set index}
  mov     al,color
  out     dx,al           {set color}
  xor     al,al           {"SET REG 0 SO DISPLAY WORKS AGAIN"}
  out     dx,al
  in      al,dx           {reset Video Gate Array to address state}
end;

procedure jrSortPaletteRGB;
var
  b:byte;
begin
  for b:=0 to 15 do jrChangeIndexColor(b,RecY709Sorted[b]);
end;

procedure jrSortPaletteCOMP;
var
  b:byte;
begin
  for b:=0 to 15 do jrChangeIndexColor(b,RecY709SortedCOMP[b]);
end;

procedure BIOSWriteG(x,y:byte;color:byte;s:string);
{writes a string in graphics mode}
begin
  asm
    {position "cursor"}
    mov     ah,02
    mov     bh,0
    mov     dh,y
    mov     dl,x
    int     10h

    {write string in teletype mode}
    mov     bh,0
    mov     bl,color
    lea     si,s      {ss:si points to string}
    cld
    segss   lodsb
    xor     cx,cx
    mov     cl,al {# chars to print}
  @loopit:
    segss   lodsb
    mov     ah,0eh    {running int 10,e changes ah on pcjr! not supposed to!}
    int     10h
    loop    @loopit
  end;
end;

procedure jrClearPage(color:byte); assembler;
asm
  mov     ax,$b800
  mov     es,ax
  xor     di,di
  mov     al,color
  and     al,$0f          {al=4-bit color low nybble (in case bad value)}
  mov     ah,al
  mov     cl,4
  shl     ah,cl           {ah=color, high nybble}
  or      al,ah           {al=both pixels}
  mov     ah,al           {ax=4 pixels of color}
  mov     cx,$2000
  cld
  rep     stosw
end;

Procedure jrPixelAddr160x100;assembler;
{
Determines buffer address of pixel in 160x100 16-color mode
Caller:
  AX = y-coordinate (0-99)
  BX = x-coordinate (0-159)

Returns:
  AH = bit mask
  BX = byte offset in buffer
  CL = number of bits to shift left
  ES = video buffer segment
}
asm
  mov     cl,bl           {CL := low-order byte of x}
  mov     dx,ax
  xchg    ah,al           {AX := 100h * y}
  shr     ax,1            {AX := 80h * y}
  shr     ax,1            {AX := 40h * y}
  shl     dx,1            {DX := 02h * y}
  shl     dx,1            {DX := 04h * y}
  shl     dx,1            {DX := 08h * y}
  shl     dx,1            {DX := 10h * y}
  add     dx,ax           {DX := ($10*y) + ($40*y) = $50*y}
  shr     bx,1            {BX := x/2}
  add     bx,dx           {BX := (($10+$40) * y) + x/2}
  les     dx,curpageaddr  {ES:DX = start of video buffer }
  add     bx,dx           {BX := byte offset in video buffer}
                          {ES:BX := byte address of pixel}
  and     cl,1            {CL := x & 1}
  xor     cl,1            {CL := 1 - (x & 1)}
  shl     cl,1
  shl     cl,1            {CL := cl * 4}
  mov     ah,$f           {AH := unshifted bit mask}
end;

Procedure jrSetPix160x100(x,y:word;color:byte);assembler;
{not the most optimal thing in the world, but it will do for now}
asm
  mov     ax,y
  mov     bx,x

  {call    jrPixelAddr160x100}
  {returns AH = bit mask, ES:BX -> buffer, CL = #bits to shift left}
  mov     cl,bl           {CL := low-order byte of x}
  mov     dx,ax
  xchg    ah,al           {AX := 100h * y}
  shr     ax,1            {AX := 80h * y}
  shr     ax,1            {AX := 40h * y}
  shl     dx,1            {DX := 02h * y}
  shl     dx,1            {DX := 04h * y}
  shl     dx,1            {DX := 08h * y}
  shl     dx,1            {DX := 10h * y}
  add     dx,ax           {DX := ($10*y) + ($40*y) = $50*y}
  shr     bx,1            {BX := x/2}
  add     bx,dx           {BX := (($10+$40) * y) + x/2}
  les     dx,curpageaddr  {ES:DX = start of video buffer }
  add     bx,dx           {BX := byte offset in video buffer}
                          {ES:BX := byte address of pixel}
  and     cl,1            {CL := x & 1}
  xor     cl,1            {CL := 1 - (x & 1)}
  shl     cl,1
  shl     cl,1            {CL := cl * 4}
  mov     ah,$f           {AH := unshifted bit mask}

  mov     al,color        {AH = bitmask, AL = color}
  shl     ax,cl           {AH = bit mask in proper position, AL = pixel value in proper position}
  not     ah              {AH = inverse bit mask}
  and     es:[bx],ah      {zero the pixel value}
  or      es:[bx],al      {set the pixel value}
end;


{===== Audio Routines =====}

Procedure jrInitAudio;
begin
  asm
    in      al,SNMplxr
    or      al,01100000b {set bits 6 and 5 to route SN audio through multiplexor}
    out     SNMplxr,al
  end;
end;

Procedure jrSetAudio(chan:byte;freq:word;volume:byte); {volume is 0-15}
{Sets an SN voice with volume and a desired frequency}
var
  period:integer;
begin
  period:=SNFreq div (32*freq);
  {clamp period so that it doesn't exceed invalid ranges.  This also
  removes the need to strip out bits that would interfere with the
  OR'd command bits sent to the register}
  if period < 0 then period:=0;
  period:=(period AND $3ff); {if period > 1023 then period:=1023;}

{
  To set a channel, we first send frequency, then volume.
  Frequency:
  76543210 76543210
  1                 - set bit to tell chip we are selecting a register
   xx0              - set channel.  4, 2, and 0 are valid values.
      xxxx          - low 4 bits of period
           0        - clear bit to tell chip more freq. coming
            x       - unused
             xxxxxx - least sig. 6 bits of period

  Sending a word value will not work on PCjr, so send bytes individally.
  (It does work on Tandy, but we want to play nice.)

  Set attenuation (volume):

  76543210
  1                 - set bit to tell chip we are selecting a register
   xx1              - register number (valid values are 1, 3, 5, 7)
      xxxx          - 4-bit volume where 0 is full volume and 15 is silent)
}

  asm
    {this procedure could be optimized to be either smaller OR faster
    but I just want to get it working right now}
    {build MSB}
    mov     al,chan
    add     al,al            {voice doubled = register #}
    mov     cl,4
    shl     al,cl            {get voice reg in place}
    or      al,10000000b     {tell chip we are selecting a reg}
    mov     dx,period        {save period val for later}
    mov     bx,dx
    and     bl,00001111b     {grab least sig 4 bits of period...}
    or      al,bl            {and put them in MSB}
    out     SNreg,al         {output MSB}
    {build LSB}
    mov     bx,dx            {restore original period val}
    shr     bx,cl            {isolate upper 6 bits}
    and     bl,01111111b     {clear bit 7 to indicate rest of freq}
    mov     al,bl
    out     SNreg,al         {send LSB}

    {set the volume}
    mov     al,chan
    shl     al,1
    or      al,1             {set voice 3 bits to 1, 3, 5, or 7}
    shl     al,cl            {get voice value into place}
    or      al,10000000b     {tell chip we're selecting a reg}
    mov     bl,volume
    not     bl               {adjust to attenuation; register expects 0 = full, 15 = quiet}
    and     bl,00001111b     {mask off junk bits}
    or      al,bl            {merge the volume into the reg select bits}
    out     SNreg,al         {send volume}
  end;
end;

Procedure jrCloseAudio;
var
  chan:byte;
begin
  for chan:=0 to 3 do jrSetAudio(chan,440,0);
  {Reset the multiplexor}
  asm
    in      al,SNMplxr
    and     al,10011100b {clear 6 and 5 to route PC speaker through multiplexor; 1 and 0 turn off timer signal}
    out     SNMplxr,al
  end;
end;

end.