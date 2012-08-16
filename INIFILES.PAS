{$O+,F+}
unit inifiles;
{
As the name implies, a simple unit to read and write .ini files, which
are extremely simple flat-file databases used to store prorgam configuration
details.

.ini files have SECTIONS.  Sections can be empty, but typically contain
one or more KEYS with VALUES.  COMMENTS start with a ; or a /.  Sections
are separated by one or more BLANK LINES.  Values are contained on a SINGLE
LINE.

This unit was thrown together in a hurry to support a very specific
implementation, so it has the following limitations:
- File name/path limited to 80 characters
- SECTION and KEYs are limited to 32 characters
- VALUEs are limited to 255 characters

A typical .ini file looks like this:

///
/// Typical .INI file used for testing.
/// This is one style of comment.
///

[section]
;this is another style of comment
key1=value
key2=A string with spaces in it!
make=Ford
model=Mustang

[Monitors]
colors=16
resolution=640x200

}

interface

uses
  objects;

type
  sectionType=string[32];
  keyType=string[32];
  filemodetype=(newfile,appendfile,readfile);
  PINIResultType=^TINIResultType;
  TINIResultType=record
    Section:sectionType;
    Key:keyType;
    Value:string;
  end;

  pINIfile=^tINIfile;
  tINIfile=object(TObject)
    readbufsize:word;
    constructor init(filename:string;filemode:filemodetype;bufsize:word);
    destructor done; virtual;

    Procedure StartNewSection(section:sectiontype;comment:string);
    Procedure WriteComment(comment:string);
    Procedure WriteKeyValue(key:keytype;value:string);
    {GetNextItem returns the section, key, and value from a successful read.
    If there are no more items per section, key will be blank.
    If there are no more sections in the file, section will be blank.}
    Function ReadNextItem:PINIResultType;

    {Resets a file in readfile mode so that you can begin reading again}
    Procedure ReadReset;

    {TRUE if a new section is found. This pauses advancement until
    ACKSection is called.  The idea is that there are multiple sections
    in a file and the user might want to do something before processing
    a new section.}
    Function NewSection:boolean;

    {Acknowledges new section and reading can continue}
    Procedure ACKSection;

    private
    f:text;
    fmode:filemodetype;
    temps:string;
    {readBuf:array[0..readbufsize-1] of Char;}
    readBuf:pointer;
    readpaused:boolean;
    lastResult:TINIResultType;
  end;

implementation

uses
  support;

const
  separator='=';
  comstart=';';
  nl=#13#10;

Constructor tINIfile.init;
begin
  Inherited Init;

  if filemode=appendfile
    then if not fileexists(filename)
      then filemode:=newfile;

  if filemode<>newfile
    then if not fileexists(filename)
      then fail;

  fmode:=filemode;
  assign(f,filename);
  readbufsize:=bufsize;
  if readbufsize>=maxavail
    then repeat
      readbufsize:=readbufsize div 2;
    until readbufsize<maxavail;
  getmem(readbuf,readbufsize);
  SetTextBuf(f,readBuf^,readbufsize);
  {SetTextBuf(f,readBuf);}
  case fmode of
    newfile:rewrite(f);
    appendfile:append(f);
    readfile:reset(f); {crashes here if filename ends in "+" ????}
  end;

  lastResult.Section:='';
  lastResult.Key:='';
  lastResult.Value:='';
  readpaused:=false;
end;

Destructor tINIfile.done;
begin
  if fmode in [newfile,appendfile]
    then writeln(f); {put blank line at end of file}
  close(f);
  freemem(readbuf,readbufsize);
  Inherited Done;
end;

Procedure tINIfile.StartNewSection(section:sectiontype;comment:string);
begin
  writeln(f); {blank line}
  if comment<>'' then writeln(f,comstart+comment);
  writeln(f,'['+section+']');
end;

Procedure tINIfile.WriteComment(comment:string);
begin
  writeln(f,comstart+comment);
end;

Procedure tINIfile.WriteKeyValue(key:keytype;value:string);
begin
  writeln(f,key+separator+value);
end;

Function TINIFile.ReadNextItem:PINIResultType;
{GetNextItem returns the section, key, and value from a successful read.
If there are no more items per section, key and value will be blank.
If there are no more sections in the file, return NIL.}
var
  _seploc:byte;
begin
  {are we paused because we hit the end of a section and the user hasn't
  acknowledged it yet?}
  if readpaused then begin
    ReadNextItem:=@lastResult;
    exit;
  end;

  {are we at the end of the file already?  bail}
  if eof(f) then begin
    ReadNextItem:=NIL;
    exit;
  end;

  repeat
    {$i-}
    readln(f,temps);
    {$i+}
  until eof(f)
  {problem reading}
  or (ioresult <> 0)
  {has section header in it}
  or ((temps<>'') and (temps[1] in ['[','0'..'9','A'..'Z','a'..'z']))
  {has key/value in it}
  or ((temps[1]<>'[') and (pos(separator,temps) <> 0))
  ;

  if (ioresult <> 0) then begin
    {Problem reading file.  Return NIL.}
    ReadNextItem:=NIL;
    exit;
  end;

  {new section header?}
  if temps[1] = '[' then begin
    lastResult.Section:=Copy(temps,2,pos(']',temps)-2);
    lastResult.Key:='';
    lastResult.Value:='';
    readpaused:=true;
  end else begin
    {if there is a separator '=' in the line, it's a valid key/value pair}
    _seploc:=pos(separator,temps);
    if _seploc <> 0 then begin
      lastResult.Key:=Copy(temps,1,_seploc-1);
      lastResult.Value:=Copy(temps,_seploc+1,length(temps));
    end;
  end;

  ReadNextItem:=@lastResult;
end;

Procedure TINIFile.ReadReset;
begin
  if fmode=readfile then begin
    reset(f);
    readpaused:=false;
  end;
end;

Function TINIFile.NewSection:boolean;
begin
  NewSection:=readpaused;
end;

Procedure TINIFile.ACKSection;
begin
  readpaused:=false;
end;

end.
