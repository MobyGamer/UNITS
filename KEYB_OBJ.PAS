unit keyb_obj;

{
OOP keyboard unit.  Uses the BIOS whenever possible for maximum
compatibility (this may be a factor in supporting Tandy 1000 and PCjr
properly).  Targeted towards the lowest-common denominator (83-key
keyboard) for maximum audience.
}

{{DEFINE TRUEIBM} {if you don't care about clones, define this for max speed}

interface

uses
  objects;

type
  ScanCodeArray=Array [0..127] Of Boolean; {table for 128 scan codes}

  LabelString=string[32];
  KeyType=record
    scancode,flags,ASCII:byte;
    keylabel:labelstring;
  end;

  PKeyboard=^TKeyboard;
  TKeyboard=object(TObject)
    LastKeyPressed:KeyType;
    ScanCodes:^scancodearray;
    Constructor Init;
    Destructor Done; virtual;
    Procedure HookInterrupt;
    Procedure UnhookInterrupt;
    Function Keypressed:boolean;
    Function HumanReadable(scancode,flags:byte):labelstring; {turns scancode+flags into human-readble string}
    private
    Hooked:boolean; {whether or not we're intercepting the BIOS keyboard interrupt}
  end;

implementation

uses
  dos,
  strings;

var
  kbd:ScanCodeArray;
  old9:Procedure;

const
  maxLabel=132;
  {
  KeyLabels is a human-readable label of the key pressed, indexed by
  scancode.  It is neither perfect nor complete because not all BIOSes
  will produce codes for every combination.  For example, the IBM PC/XT
  5160 BIOS will not produce Control-Insert or Control-=; catching those
  particular combinations requires hooking the keyboard interrupt and
  processing them on your own.

  The following table was determined through empirical evidence (ie. I
  pressed every single key combo and recorded the result) on an IBM PC/XT
  keyboard and IBM PC/XT 5160 BIOS.  While not complete (AT BIOSes and
  keyboards produce more combinations), it is an adequate baseline
  for all computers claiming "IBM PC compatibility" including the Compaq,
  AT&T PC 6300, Amstrad, and other "xt clones".
  }
  KeyLabels:array[0..maxLabel] of PChar=(
  '(undefined)', {we should never see 0 unless user is screwing around with alt-keypad}
  'Esc','1','2','3','4','5','6','7','8','9','0','-','=','BackSpace',
  'Tab','Q','W','E','R','T','Y','U','I','O','P','[',']','Enter','',
  'A','S','D','F','G','H','J','K','L',';','''','`','',
  '\','Z','X','C','V','B','N','M',',','.','/','',
  '*','',
  'SpaceBar','CapsLock',
  'F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','NumLock','ScrollLock',
  'Home','Up','PgUp','kMinus',
  'Left','k5','Right','kPlus',
  'End','Down','PgDn',
  'Ins','Del',
  {what follows are the result of key combos for non-ascii-producing keys}
  'F1','F2','F3','F4','F5','F6','F7','F8','F9','F10',
  'F1','F2','F3','F4','F5','F6','F7','F8','F9','F10',
  'F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','PrtSc',
  'Left','Right','End','PgDn','Home',
  '1','2','3','4','5','6','7','8','9','0','-','=',
  'PgUp'
  );

  RSHPressed=1; LSHPressed=2; CTLPressed=4; ALTPressed=8;

Procedure New9handler; interrupt;
var
  port60h:byte;
begin
  port60h:=port[$60];
  kbd[port60h and $7f] := (port60h < 128);     { record current status }
  asm pushf; end;                              { must precede call to old int }
  old9;                                        { call old interrupt }
  asm cli; end;                                { disable hardware interrupts }
  memw[$0040:$001a] := memw[$0040:$001c];      { clear the keyboard buffer }
  asm sti; end;                                { enable hardware interrupts }
end;

Constructor TKeyboard.Init;
begin
  Hooked:=false;
  ScanCodes:=@kbd; {pointer to interrupt-routine scancode array from KEYBOARD unit}
  with LastKeyPressed do begin
    scancode:=0;
    flags:=0;
    ASCII:=0;
    keylabel:='';
  end;
end;

Destructor TKeyboard.Done;
begin
  if hooked then UnHookInterrupt;
end;

Procedure TKeyboard.HookInterrupt;
begin
  FillChar (kbd, 128, 0); { fill the keyboard table with false }
  GetIntVec ($09, @old9);
  SetIntVec ($09, @New9handler);
  Hooked:=true;
end;

Procedure TKeyboard.UnhookInterrupt;
begin
  SetIntVec ($09, @old9);
  Hooked:=false;
end;

Function TKeyboard.HumanReadable;
var
  foo:labelstring;
begin
  foo:=StrPas(KeyLabels[scancode]);
  if (flags and RSHPressed)=RSHPressed then foo:='RShift+'+foo;
  if (flags and LSHPressed)=LSHPressed then foo:='LShift+'+foo;
  if (flags and CTLPressed)=CTLPressed then foo:='Ctrl+'+foo;
  if (flags and ALTPressed)=ALTPressed then foo:='Alt+'+foo;
  HumanReadable:=foo;
end;

Function TKeyboard.Keypressed:boolean;

  Function kbd_keypressed:boolean;
  var
    loop:byte;
  begin
    kbd_keypressed:=false; {assume "no"}
    for loop:=0 to 127 do begin
      if kbd[loop] then begin
        kbd_keypressed:=true;
        break; {exit out of loop}
      end;
    end;
  end;

var
  localpress:boolean;
  loop,
  lkps,lkpa,lkpf:byte; {this is necessary because I don't understand how
  to deal with the Self pointer + OOP + BASM.  All suggestions appreciated!}
begin
  if Hooked {if keyboard int hooked, call custom hook; otherwise, call BIOS}
    then begin
      localpress:=false;
      for loop:=0 to 127 do
        if kbd[loop] then begin
          localpress:=true;
          break; {exit out of loop}
        end;
    end
    else begin
      {procedure to get keyboard status from BIOS and stick in lastkey}
      asm
        mov localpress,0     {assume false}
        mov ah,01h           {get keyboard status}
        int 16h
        jz  @done            {if zf set, no key was pressed}
        inc localpress       {1=true}
        mov lkps,ah          {store scancode}
        mov lkpa,al          {store ascii value}
        mov ah,2
        int 16h              {Read Keyboard Flags}
        and al,00001111b;    {we don't care about caps/num/etc. status}
        mov lkpf,al          {store flags}
        xor ax,ax
        {$IFDEF TRUEIBM}
        mov es,ax
        mov bx,0417h
        mov es:[bx],al       {manipulates queue size}
        {$ELSE}
        int 16h              {read key to get it out of BIOS/buffer and discard}
        {$ENDIF}
@done:
      end;
      if localpress then begin
        with LastKeyPressed do begin
          flags:=lkpf;
          ascii:=lkpa;
          scancode:=lkps; {now that we've got our scancode, lkps becomes label index}
          if lkps>maxLabel then lkps:=maxLabel;
          keylabel:=HumanReadable(lkps,lkpf);
        end;
      end;
    end;
  Keypressed:=localpress;
end;

end.
