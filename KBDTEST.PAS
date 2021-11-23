{$G-,R-,S-}

Uses
  support,
  tfastwrite,
  keyb_obj;

Var
  X,Y:Byte;
  calx,caly:word;
  foo:string;
  mykeyb:PKeyboard;

Begin
  new(mykeyb,init);

  writeln('Press ENTER to hook keyboard int or any other key to print info');
  repeat
    with mykeyb^ do begin
      if keypressed then begin
        write(#13,'scancode: ',hex(lastkeypressed.scancode),'h',
                  ' ASCII: ',lastkeypressed.ascii,
                  ' flags: ',lastkeypressed.flags,
                  '(',lastkeypressed.keylabel,')',#32:8);
      end else write(#13,char(random(4)+32));
    end;
  until mykeyb^.lastkeypressed.ASCII=13;

  asm
    mov ax,0001
    int 10h
  end;
  tfastinit(40,25);
  tfPreventSnow:=false;
  mykeyb^.HookInterrupt;

  While Not mykeyb^.ScanCodes^[1{kbd_escape}] Do Begin
    For X:=0 To 125-1 Do
      If mykeyb^.ScanCodes^[X]=True
        then begin
          if x<10 then foo:='0' else foo:=''; {start decimal with leading 0}
          foo:=foo+inttostr(x)+':'; {add decimal value+:}
          if x<16 then foo:=foo+'0'; {if hex single digit, add another 0}
          foo:=foo+hex(x)+'h';
          calx:=((x-1) mod 6) * 6; caly:=(x-1) div 6;
          tfastwritexy(@foo,ptr($b800,0),calx,caly,$1b);
        end
        Else begin
          foo:='תתתתתת';
          calx:=((x) mod 6) * 6;
          caly:=(x) div 6;
          tfastwritexy(@foo,ptr($b800,0),calx,caly,$07);
        end;
  End; { scancode 1 is esc; loop until esc pressed }

  mykeyb^.UnhookInterrupt;
  Dispose(mykeyb,done);
  RestoreDOSScreen;
End.
