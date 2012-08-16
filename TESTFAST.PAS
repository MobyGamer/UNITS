program testfastwrite;
{
Tests the fastwrite unit and records execution times.
}

{{$DEFINE COMPLETE}

uses
  tfastwrite,
  m6845ctl,
  ztimer,
  support;

const
  topexp=5;
  botexp=22;

var
  b:byte;
  foo,bar:byte;
  s:string;
  hidden:pointer;
  scrp:pointer;
  ch:char;
  counter:byte;
  totalticks:word;

begin
  if test8086>=2 then begin
    writeln('The purpose of this program is to time how long the routines');
    writeln('take to run, but this platform is a 386 or higher.  If your');
    writeln('platform is TOO fast, it will error out.  Sure you want to continue?');
    if upcase(readkeychar)<>'Y' then fatalerror(1,'Not worried about speed on a fast machine');
  end;
  ch:=#0;
  scrp:=ptr($b800,0);
  getmem(hidden,80*25*2);
  tfastinit(80,25);
  PreventSnow:=false;
  tfastclrscr(scrp,$07,250); {250 = "ú", blue back, b=lightcyan fore}
  tfastclrscr(hidden,$1b,250); {250 = "ú", blue back, b=lightcyan fore}
  repeat
    if keypressed then begin
      while keypressed do ch:=readkeychar;
      preventsnow:=not preventsnow;
    end;

    s:='The sample string used in all tests is:';
    b:=(tfmaxscrx shr 1)-(length(s) shr 1);
    tfastwritexy(@s,hidden,b,4,$70);
    s:='This is a test of the tfastwrite routine.'; b:=(tfmaxscrx shr 1)-(length(s) shr 1);
    for foo:=topexp to botexp do tfastwritexy(@s,hidden,b,foo,(foo+bar) AND 127);
    inc(bar);

    _LZtimerOn;
    tfastwritexy(@s,hidden,b,5,bar and 127); {1 background, 7 foreground}
    _LZtimerOff;
    s:='tfastwritexy execution time (hidden buffer): '
       +inttostr(_LZtimerCount)+' æsec ('
       +inttostr(_LZtimerCount div 1000)+' ms)  ';
    tfastwritexy(@s,hidden,0,0,$17);

    s:='This is a test of the tfastwrite routine.'; b:=(tfmaxscrx shr 1)-(length(s) shr 1);
    _LZTimerOn;
    tfastwritexy(@s,scrp,b,5,bar and 127); {1 background, 7 foreground}
    _LZTimerOff;
    s:='tfastwritexy execution time (visible buffer): '
       +inttostr(_LZTimerCount)+' æsec ('
       +inttostr(_LZTimerCount div 1000)+' ms)  ';
    tfastwritexy(@s,hidden,0,1,$17);
    tfastwritexy(@s,scrp,0,1,$17);

    {this is actually the most useful benchmark here - tests time it takes
    for all length strings}
    {$IFDEF COMPLETE}
    totalticks:=0;
    for counter:=tfmaxscrx downto 0 do begin
      byte(s[0]):=counter;
      _LZTimerOn;
      tfastwritexy(@s,hidden,0,3,$1f);
      _LZTimerOff;
      inc(totalticks,_LZTimerCount);
    end;
    totalticks:=totalticks div (tfmaxscrx+1);
    s:='Average write time for all length strings: '
       +inttostr(totalticks)+' æsec ('
       +inttostr(totalticks div 1000)+' ms)  ';
    tfastwritexy(@s,hidden,0,3,$17);
    {$ENDIF}

    _LZTimerOn;
    tfastcopyscreen(hidden,scrp);
    _LZTimerOff;
    s:='tfastcopyscreen execution time: '
       +inttostr(_LZTimerCount)+' æsec ('
       +inttostr(_LZTimerCount div 1000)+' ms), or about '
       +inttostr(1000000 div _LZTimerCount)+'fps  ';
    tfastwritexy(@s,scrp,0,2,$17);
    tfastwritexy(@s,hidden,0,2,$17);

    s:='Press ESC to exit or any other key to toggle the PreventSnow variable.';
    tfastwritexy(@s,hidden,0,23,$1f);
    s:='(Numbers vary due to where the display cycle is, and interrupt noise.)';
    tfastwritexy(@s,hidden,0,24,$1f);
    if not PreventSnow
      then s:='PreventSnow: Off'
      else s:='PreventSnow: On ';
    tfastwritexy(@s,hidden,0,5,$1a);

    s:='Alignment and'; tfastwritexy(@s,hidden,0,9,$1a);
    s:='sanity checking:'; tfastwritexy(@s,hidden,0,10,$1a);
    s:='1'; tfastwritexy(@s,hidden,0,11,$1a);
    s:='22'; tfastwritexy(@s,hidden,0,12,$1a);
    s:='333'; tfastwritexy(@s,hidden,0,13,$1a);
    s:='4444'; tfastwritexy(@s,hidden,0,14,$1a);
    s:='55555'; tfastwritexy(@s,hidden,0,15,$1a);
    s:='666666'; tfastwritexy(@s,hidden,0,16,$1a);
    s:='7777777'; tfastwritexy(@s,hidden,0,17,$1a);
    s:='88888888'; tfastwritexy(@s,hidden,0,18,$1a);
    s:='999999999'; tfastwritexy(@s,hidden,0,19,$1a);
  until ch=#27;
  freemem(hidden,80*25*2);
end.