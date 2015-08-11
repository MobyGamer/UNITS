{$F+} {required for interrupts because they use far calls!}

{
Sample keyboard handler by Jussi Lahdenniemi, 1994
rewritten into a unit by Trixter (Jim Leonard), 7/24/95
Reworked by Trixter again on 5/6/96
XT support with proper BIOS handling added by Trixter again 20080204

20080223 - if anyone knows how to write interrupt routines with OOP,
contact trixter@oldskool.org because until I figure it out I have to
call interrupt code in another unit...!
}

Unit Keyboard;

interface

type
  ScanCodeArray=Array [0..127] Of Boolean; {table for 128 scan codes}

var
  kbd:ScanCodeArray;
  old9:Procedure;

Procedure HookKeyInt;
Procedure UnHookKeyInt;
Function  kbd_keypressed:boolean;

implementation

Uses
  DOS;

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

Procedure HookKeyInt;
begin
  FillChar (kbd, 128, 0); { fill the keyboard table with false }
  GetIntVec ($09, @old9);
  SetIntVec ($09, @New9handler);
end;

Procedure UnHookKeyInt;
begin
  SetIntVec ($09, @old9);
end;

Function kbd_keypressed:boolean;
var
  loop:byte;
  keydown:boolean;

begin
  keydown:=false; {assume "no"}
  for loop:=0 to 127 do begin
    if kbd[loop] then begin
      keydown:=true;
      break; {exit out of loop}
    end;
  end;
  kbd_keypressed:=keydown;
end;

End.
