unit RTEH; {run-time error handler}

interface

implementation

uses
  support;

var
  OldExit:pointer;

Procedure RunTimeExitProc; Far;

var
  Message:string;

begin
  if ErrorAddr<>Nil then begin
    case ExitCode of
        1:message:='Invalid function number';
        2:message:='File not found';
        3:message:='Path not found';
        4:message:='Too many open files';
        5:message:='File access denied';
        6:message:='Invalid file handle';
       12:message:='Invalid file access code';
       15:message:='Invalid drive number';
       16:message:='Cannot remove current directory';
       17:message:='Cannot rename across drives';
       18:message:='No more files';
      100:message:='Disk read error';
      101:message:='Disk write error';
      102:message:='File not assigned';
      103:message:='File not open';
      104:message:='File not open for input';
      105:message:='File not open for output';
      106:message:='Invalid numeric format';
      150:message:='Disk is write-protected';
      151:message:='Bad drive request struct length';
      152:message:='Drive not ready';
      154:message:='CRC error in data';
      156:message:='Disk seek error';
      157:message:='Unknown media type';
      158:message:='Sector Not Found';
      159:message:='Printer out of paper';
      160:message:='Device write fault';
      161:message:='Device read fault';
      162:message:='Hardware failure';
      200:message:='Division by zero';
      201:message:='Range check error';
      202:message:='Stack overflow error';
      203:message:='Heap overflow error';
      204:message:='Invalid pointer operation';
      205:message:='Floating point overflow';
      206:message:='Floating point underflow';
      207:message:='Invalid floating point operation';
      208:message:='Overlay manager not installed';
      209:message:='Overlay file read error';
      210:message:='Object not initialized';
      211:message:='Call to abstract method';
      212:message:='Stream registration error';
      213:message:='Collection index out of range';
      214:message:='Collection overflow error';
      215:message:='Arithmetic overflow error';
      216:message:='General Protection fault';
    else
      message:='Unknown';
    end;
    {force text mode so we can see the error!}
    asm
      mov ax,0003
      int 10h
    end;
    writeln('Fatal runtime error ',ExitCode,
            ' at ',hexword(seg(ErrorAddr^)),
            ':',hexword(ofs(ErrorAddr^)),
            ' "',Message,'"');
    ErrorAddr:=nil;
    ExitCode:=1;
  end;
  ExitProc:=OldExit;
end;
{====================================================================}
begin
  OldExit:=ExitProc;
  ExitProc:=@RunTimeExitProc;
end.
