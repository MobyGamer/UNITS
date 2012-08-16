program inibench;
{reading .ini files is really slow -- this is a test harness for profiling
to see if I can speed things up.}

uses
  inifiles;

var
  ini:PINIfile;
  iniresult:PINIResultType;

begin
  ini:=new(PINIFile,init('database.ini',readfile,4096));

  INIResult:=ini^.ReadNextItem;
  {acknowledge that we've begun a new section and can continue}
  if ini^.newSection then ini^.ACKSection;
  {read loop:}
  while (INIResult<>nil) do begin
    INIResult:=ini^.ReadNextItem;

    {end of INI file reached?  Invalid return?}
    if INIResult=nil then break;
    {new section? Commit what we have, then set up for next object}
    if ini^.newSection then begin
      {Acknowledge to the INI reader that we have processed the new section}
      ini^.ACKSection;
      writeln('Found new section header: '+INIResult^.section);
    end;
    {process all key/value pairs we're interested in}
    if INIResult^.key<>'' then begin
      with INIResult^ do begin
        writeln('Found new key/value pair: '+key+':'+value);
      end;
    end;
  end;

  dispose(ini,done);
end.