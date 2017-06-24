; filename: BM.ASM
; fast search routine to search strings in ARRAYS OF CHARS
; function in Turbo Pascal >= 4. Based on the Boyer-Moore algorithm.
; program author: Costas Menico.
; Very small modifications for using an ARRAY OF CHAR buffer instead of
; a string made by Jochen Magnus in May 93.
; declare as follows:
; {$F+}
; {$L BM.OBJ}
; function posbm(pat:string; var buffer; buflen:word):WORD; external;
; call as follows from Turbo 4..7:
; location := posbm(pat, buf, buflen);
; call for a search in a string typed buffer:
; location := posbm(pat, str[1], length(str));


skiparrlength        equ        256

; function work stack

dstk                struc
patlen                dw        ?
strlen                dw        ?
skiparr                db        skiparrlength dup(?)
pattxt                dd        0
strtxt                dd        0
dstk                ends

; total stack (callers plus work stack)

cstk                struc
ourdata                db        size dstk dup(?)
bpsave                dw        0
retaddr                dd        0
paramlen       dw   0                                                           ; JO
straddr                dd        0
pataddr                dd        0
cstk                ends

paramsize        equ        size pataddr+size straddr +size paramlen           ; +2  JO

code                segment        para public
                assume cs:code

; entry point to posbm function

posbm                proc        far
                public        posbm

                push        bp
                         sub        sp, size dstk
                         mov        bp, sp
                         push    ds
                         xor        ah, ah
                         cld

; get and save the length and address of the pattern

                lds        si, [bp.pataddr]
                         mov        word ptr [bp.pattxt][2], ds
                         lodsb
                         or        al, al
                         jne        notnullp
                         jmp        nomatch

notnullp:
                mov        cx, ax
                         mov        [bp.patlen], ax
                         mov        word ptr [bp.pattxt], si

; get and save the length and address of the string text

                lds        si, [bp.straddr]
                         mov        word ptr [bp.strtxt][2], ds
                         mov ax,[bp.paramlen]                                          ; JO
                         or  ax,ax                                                              ; JO
                         jne        notnulls
                         jmp        nomatch

notnulls:
                mov        [bp.strlen], ax
                         mov        word ptr [bp.strtxt], si
                         cmp        cx, 1
                         jne        do_boyer_moore
                         lds        si, [bp.pattxt]
                         lodsb
                         les        di, [bp.strtxt]
                         mov        cx, [bp.strlen]
                         repne        scasb
                         jz        match1
                         jmp        nomatch

match1:
                mov        si, di
                         sub        si, 2
                         jmp        exactmatch

do_boyer_moore:

; fill the ASCII character skiparray with the
; length of the pattern

                lea        di, [bp.skiparr]
                         mov        dx, ss
                         mov        es, dx
                         mov        al, byte ptr [bp.patlen]
                         mov        ah, al
                         mov        cx, skiparrlength/2
                         rep        stosw

; replace in the ASCII skiparray the corresponding
; character offset from the end of the pattern minus 1

                lds        si, [bp.pattxt]
                         lea        bx, [bp.skiparr]
                         mov        cx, [bp.patlen]
                         dec        cx
                         mov        bx, bp
                         lea        bp, [bp.skiparr]
                         xor        ah, ah

fill_skiparray:
                lodsb
                         mov        di, ax
                         mov        [bp+di], cl
                         loop        fill_skiparray
                         lodsb
                         mov        di, ax
                         mov        [bp+di], cl
                         mov        bp, bx

; now initialize our pattern and string text pointers to
; start searching

                lds        si, [bp.strtxt]
                         lea        di, [bp.skiparr]
                         mov        dx, [bp.strlen]
                         dec        dx
                         mov        ax, [bp.patlen]
                         dec        ax
                         xor        bh, bh
                         std

; get character from text. use the character as an index
; into the skiparray, looking for a skip value of 0.
; if found, execute a brute-force search on the pattern

searchlast:
                sub        dx, ax
                         jc        nomatch
                         add        si, ax
                         mov        bl, [si]
                         mov        al, ss:[di+bx]
                         or        al, al
                         jne        searchlast

; we have a possible match, therefore
; do the reverse brute-force compare

                mov        bx, si
                         mov        cx, [bp.patlen]
                         les        di, [bp.pattxt]
                         dec        di
                         add        di, cx
                         repe        cmpsb
                         je        exactmatch
                         mov        ax, 1
                         lea        di, [bp.skiparr]
                         mov        si, bx
                         xor        bh, bh
                         jmp        short searchlast

exactmatch:
                mov        ax, si
                         lds        si, [bp.strtxt]
                         sub        ax, si
                         add        ax, 2
                         jmp        short endsearch

nomatch:
                xor        ax, ax

endsearch:
                cld
                         pop        ds
                         mov        sp, bp
                         add        sp, size dstk
                         pop        bp
                         ret        paramsize
posbm                endp

code                ends
                end
