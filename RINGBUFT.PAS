program ringbuft;
{Test harness for "slab ring buffer" code.  Please see ringbufu for details.}

uses
  ringbufu;

var
  tring:TSlabRing;
  p:pointer;
  buf:pointer;
  tf:boolean;
  foop:pointer;

begin
  tring.init(heapPtr,heapEnd);
  writeln('heap manager thinks ',maxavail,' is free.');
  writeln('we created a slab of ',tring.slabSize);
  tring.done;

  getmem(buf,1000);
  p:=buf; word(p):=word(buf)+1000;
  tring.init(buf,p);

  p:=tring.reserve(256);
  tf:=tring.commit(p,256);
  p:=tring.reserve(256);
  tf:=tring.commit(p,256);
  p:=tring.reserve(256);
  tf:=tring.commit(p,256);
  p:=tring.reserve(256);   {this fails because no big enough area on slab}
  p:=tring.retrieve;       {this should free up the first area}
  p:=tring.retrieve;       {this should free up the first area}
  p:=tring.reserve(256);   {should work}
  tf:=tring.commit(p,256); {this should work}

  p:=tring.reserve(736);
  tf:=tring.commit(p,736-32);
  inc(word(p),736-32);
  tf:=tring.commit(p,32);
  p:=tring.retrieve;
  tf:=tring.commit(p,32);
  p:=tring.retrieve;


(*  p:=tring.reserve(5000);
  p:=tring.reserve(500);
  foop:=p;
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  dec(word(foop),250);
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  p:=foop;
  while p<>NIL do begin
    p:=tring.retrieve;
  end;
  p:=tring.reserve(500);
  foop:=p;
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  dec(word(foop),250);
  tf:=tring.commit(foop);
  inc(word(foop),250);
  tf:=tring.commit(foop);
  p:=foop;
  *)
end.