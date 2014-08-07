unit ringbufu;
{
This code implements a ring buffer in a slightly unconventional way, by way of
a heap manager rather than an actual buffer with a copy in/out mechanism.
User workflow to use the ring is as follows:

1. User provides an area of memory for the ring code to manage.  This large
memory area is referred to as the "slab".

2. User reserves of an area of the slab to write data to (can be any size).
Ring responds with a pointer to the area if there is room, or NIL if the
reservation couldn't be serviced (ie. ring is full).

3. User writes to the area provided by the ring and then "commits" the write
via a supplied pointer and length.  User can commit multiple sub-areas if
desired, ie. if they have allocated 8k of data and put datums at 2k, 3k, 1k,
and 2k, they can commit each datum individually.

4. When user needs to retrieve what they commited, they issue retrieve() and
get back either a pointer to what they committed in FIFO order, or NIL if
retrieval failed (ie. ring is empty).

Internal details:

All pointers are assumed to be paragraph-aligned (ie. aligned to the nearest
16-byte boundary) and normalized (ie. offset is 0).  If any input to
the ring code doesn't follow these conventions, it will be adjusted on entry.
(ie. Ring code will normalize commits, but will truncate a commit if the
commit offset is still non-zero after normalization.)  Ring code will
pad reserve amounts to next paragraph boundary.

Internal management of pointers is segments only.  This means, by design, ring
code will always return normalized pointers.

2048-word array will handle commit locations, and have its own head and tail
index pointers.  This should be enough for most purposes if the average commit
size is over 300 bytes; if this is not granular enough, increase qSize.

FIFO management:  tail=head means queue is empty.  Tail can shrink right onto
the head.  Head must NOT grow right onto the tail, but stop just short of it
to prevent false isEmpty condition.  All head and tail operations advance the
head/tail index after all store/read ops have finished.  (ie. store seg, then
advance head.  Read seg, then advance tail.)

The location and size of the reserved area (resSeg) is used to determine where
new slab allocations land.  Code exists to ensure resSeg wraps around the end
of the slab, checks commits to ensure they are inside the reserved area, and
shrinks the reserved area as commits occur.

Code should be interrupt-safe, because:
- Commit never references or alters the tail data
- Retrieve never references or alters the head or reservation data
  (other than resetting isFull, which is an atomic operation)
- Reservations never happen while a commit or retrieve is in progress

Miscellaneous:

The user can reserve a new area before completely filling up the old
reservation with commits.  This allows the user to do things like reserve an
area, do some calcs, and then reserve again with a larger requested amount.
The same pointer will be returned as the first reservation; only the internal
counter amountP will have changed.

Future Enhancements:

- Create numSegments as a variable that tracks how many segments are
currently "in use".  This will require adding a size record to the FIFO
array, and some logic.
}

interface

uses
  objects;

const
  qSize=1 SHL 11;     {size of FIFO queue; must be power of 2} {2048}

type
  PSlabRing=^TSlabRing;
  TSlabRing=object(TObject)
    slabStart:word;   {segment that indicates first available byte of slab}
    slabEnd:word;     {segment that indicates first NON-available byte of slab}
    slabSizeP:word;   {size of slab in 16-byte paragraphs}
    slabSize:longint; {size of slab in bytes}
    head:word;        {index into FIFO queue; insertion point of new commits}
    tail:word;        {index into FIFO queue; indicates first FIFO data out}
    resSeg:word;      {last successful reserved segment returned}
    resAmtP:word;     {last successful reserved amount in parapgraphs}
    isFull:boolean;   {indicates "full" by holding status of last reserve}
    numElements:word; {indicates number of queue elements in use}
    FIFO:array[0..qSize-1] of word; {FIFO queue of segments on the slab}
    constructor init(_start,_end:pointer);
    destructor done; virtual;
    function reserve(amountb:word):pointer;
    {Reserves a slab area and returns pointer if successful or NIL if not.
    Internally, checks to see if head+amount exists on the slab and returns
    pointer if successful.  If head+amount would go past end of slab, moves
    head to beginning of slab and tries again, making sure to not run into
    the tail.}
    function commit(datum:pointer;amountb:word):boolean;
    {commits a section (or all) of the reserved area to the queue in FIFO order.
    Returns TRUE if successful or FALSE if error (ie. outside reserved area).
    Internally, records the segment in the FIFO queue, then grows the head.}
    function retrieve:pointer;
    {retrieves a queue item in FIFO order.
    Internally, returns tail segment in FIFO queue, then shrinks the tail.}
    function isEmpty:boolean;
    {returns head=tail}
  end;

implementation

{assembler functions will be inlined via inline() when time permits!}

Function NormPtr(p: Pointer): Pointer; Assembler;
{Normalizes an x86 16-bit seg:ofs pointer.}
Asm
  mov dx,word ptr [p+2] {seg}
  mov ax,word ptr [p]   {ofs}
  mov bx,ax             {bx=ofs}
  and ax,0Fh            {ax=offset remainder}
  mov cl,4
  shr bx,cl             {bx=ofs div 16=num paragraphs}
  add dx,bx             {increase seg by # of paragraphs}
End;

Function SegToPtr(_seg:word):Pointer; Assembler;
{Returns pointer in DX:AX}
Asm
  mov dx,_seg
  xor ax,ax
End;

constructor TSlabRing.init;
begin
  inherited Init;
  {Pad start to nearest paragraph; truncate end to nearest paragraph.
  Better safe than sorry.}
  word(_start):=(word(_start) + 16-1) AND NOT (16-1);
  _start:=NormPtr(_start);
  _end:=NormPtr(_end);
  word(_end):=0;
  asm
    les di,self                         {we are altering object method data}
    mov ax,word ptr [_start+2]
    mov word ptr es:[di].slabStart,ax
    mov ax,word ptr [_end+2]
    mov word ptr es:[di].slabend,ax
  end;
  slabSizeP:=slabEnd-slabStart;
  slabSize:=slabSizeP; slabSize:=slabSize*16;
  {the above idiocy prevents TP arith overflow bug due to wrong longint casting}
  resSeg:=slabStart;
end;

destructor TSlabRing.done;
begin
  inherited Done;
end;

function TSlabRing.reserve;
{head and tail FIFO indexes are NOT manipulated here.  This only tells the
caller if they can have a segment [amount] bytes free or not.}
var
  amountp:word;
  p:pointer;

  function reserveArea(_seg,amtp:word):pointer;
  begin
    resSeg:=_seg;
    resAmtP:=amtp;
    reserveArea:=segToPtr(resSeg);
    isFull:=false;
  end;

begin
  {pad amount to nearest paragraph, then divide by 16 to convert to paragraphs}
  asm
    mov ax,amountb
    add ax,(16-1)
    {and amount,not (16-1)} {unnecessary}
    mov cl,4
    shr ax,cl
    mov amountp,ax
  end;
  {different logic if insertion point is ahead or behind tail}
  if resSeg>=FIFO[tail] then begin
    {would reservation go beyond end of slab?}
    if resSeg+amountp<slabend
      then p:=reserveArea(resSeg,amountp)
      else begin
        {can we wraparound to beginning of slab without hitting tail?}
        if (slabStart+amountp<FIFO[tail])
        or isEmpty
          then p:=reserveArea(slabStart,amountp)
          else p:=NIL;
      end;
  end else begin
    {head is already behind tail; only check for running into tail}
    if resSeg+amountp<FIFO[tail]
      then p:=reserveArea(resSeg,amountp)
      else p:=NIL;
  end;
  if p=NIL then isFull:=true;
  reserve:=p;
end;

Function TSlabRing.commit;
{Records the datum into the FIFO queue, then advances the head.
Checks to see if we are trying to commit past the reserved area.
A successful commit shrinks the reserved area.}
var
  datumSeg:word;
  amountp:word;
begin
  datum:=NormPtr(datum); {in case user forgot to}
  asm
    {no @Self because source/target are not object's public/private fields}
    mov ax,word ptr [datum+2]
    mov datumSeg,ax
  end;
  amountp:=amountb SHR 4;
  {check if user is trying to commit outside of the reserved area}
  if (datumSeg<resSeg) or (datumSeg>=resSeg+resAmtP) then begin
    commit:=false;
    exit;
  end;
  {check if user is trying to commit something that has already been commited}
  {this check fails to catch 1 out of every [qSize] iterations, but since
  a user doing that would be a rare occurance anyway, I'm taking those odds}
  if head<>0
    then if datumSeg=FIFO[head-1] then begin
      commit:=false;
      exit;
    end;

  {commit segment to the FIFO queue and advance index with wraparound}
  FIFO[head]:=datumSeg;
  inc(numElements);
  head:=(head+1) AND (qsize-1);
  {adjust reserved area by how much was committed}
  inc(resSeg,amountP);
  dec(resAmtP,amountP);
  {exit indicating success}
  commit:=true;
end;

function TSlabRing.retrieve;
begin
  if not isEmpty then begin
    {retrieve segment from the FIFO queue and advance index with wraparound}
    retrieve:=segToPtr(FIFO[tail]);
    dec(numElements);
    tail:=(tail+1) AND (qsize-1);
    {if we pull even ONE item, we really can't consider ourselves "full"}
    isFull:=false;
  end else retrieve:=NIL;
end;

function TSlabRing.isEmpty;
begin
  isEmpty:=(head=tail);
end;

end.
