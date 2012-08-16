{$R-,S-}
{{$DEFINE EVILINT} {define this if you want your handler to be evil}

Uses
  support,
  TInterrupts;

var
  mycounter,oldcounter:word;

{$F+}
procedure MyHandler; Interrupt;
{
Ok, here's our actual handler. This particular handler just increments
a counter. Then it checks to see if the BIOS handler should be called.
If so, it calls it; if not, it acknowledges the interrupt itself.

Do not do any LONGINT stuff in an interrupt handler with Turbo Pascal 7
because the 32-bit-away routines do not preserve the upper bits of
ax/bx/cx/dx. If you must, and your code will run on 386s or higher,
make sure you PUSH EAX/EBX/ECX/EDX before starting and POP when done.
}

begin
  {DO WHATEVER WE WANT TO DO IN HERE}
  inc(mycounter);
  {END DOING WHATEVER WE WANT}

  {$IFNDEF EVILINT} {We want to be nice, and will maintain the BIOS interrupt}

  inc(PITCycles,Chan0Counter); {Keep track of how many PIT cycles have gone by}
  if longrec(PITCycles).hi <> 0 then begin {Did we roll over?  Is it time to call the 18.2Hz BIOS handler?}
    longrec(PITCycles).hi:=0; {Update our PIT cycles counter}
    asm pushf end; {simulate an interrupt by pushing flags, then CALLing handler}
    BIOSTimerHandler; {this will acknowledge the interrupt}
  end
  else
    Port[$20] := $20; {send EndOfInterrupt to the PIC to ackn. the interrupt}

  {$ELSE}

  Port[$20] := $20; {Just acknowledge the interrupt, oldint8 be damned}

  {$ENDIF}
end;
{$F-}

begin
  SetTimer(@MyHandler, 6000); {set our interrupt handler to fire at 6KHz
  BTW, 6KHz is about the practical limit for a 4.77MHz 8088 PC.  Special-case
  handlers and situations can go higher, but if you want the rest of the
  system to function normally without any special handling, stay below 6KHz.
  Note: PCjr is slower than this so 6000 may well crash a PCjr.}
  writeln;
  repeat
    {test to see if a HLT gets to US or the interrupt handler on an int.}
    oldcounter:=mycounter;
    asm
      HLT {wait until maskable or non-maskable interrupt fires}
      CLI {clear (disable) interrupts}
    end;
    {if the counter is exactly the same, then WE got execution instead of the
    interrupt which is not normal and not what I am expecting to happen}
    if oldcounter=mycounter
      then write(#13,'User prog first after HLT ')
      else write(#13,'Int. hand first after HLT ');
    asm
      STI {set (enable) interrupts}
    end;
    write(mycounter,' ');
    write(mycounter,' ');
    write(mycounter,' ');
    write(mycounter,' ');
    write(mycounter,' ');
  until keypressed;
  repeat readkeychar until not keypressed;
  CleanUpTimer;
end.