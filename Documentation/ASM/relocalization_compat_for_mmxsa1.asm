; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Relocalization Compatibility" Patch
;  Apply after: SA-1 (all nine SA-1 Plus patches)
;  Apply BEFORE: any MMX Relocalization v3.0 patch (Jake Nagare)
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off relocalization_compat_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Makes SA-1 Plus and the MMX Relocalization v3.0 patches (all five
;    v1.0 IPS files: Maverick, Irregular, Rockman, and the +Logo variants)
;    write to completely different bytes, so either set can be applied in
;    either order, or merged into one IPS, without one overwriting the
;    other. Gameplay, menus and save data are unchanged: this patch only
;    moves things around.
;
;    There were two collisions:
;
;      1. File $000F87 - the three Logo / Rockman patches change one
;         operand byte of the title-screen logo code (LDA #$0080 ->
;         #$0070). The SA-1 port had shifted that code by 10 bytes, so
;         the same file offset held the operand of an unrelated STA $3A.
;
;      2. File $037A50-$037A64 (Irregular, Irregular+Logo, Rockman) - the
;         Relocalization writes script text into the unused end of bank $86.
;         The SA-1 port keeps its 295-byte object-type flag tables there.
;
;    After this patch, SA-1 Plus (all nine patches merged) touches neither
;    $000F87 nor anything in $037A44-$037A64, and no other byte written by
;    any Relocalization IPS is written by SA-1 Plus.
;
;    Order: if this patch is applied as a separate IPS, apply it before the
;    Relocalization. It restores the original $000F87 operand and blanks
;    the old table location, which would undo the Relocalization's bytes
;    there if applied after it. The merged sa-1_plus.ips has no such
;    restriction: its net result never writes those bytes at all.
;
;    Uses free space: $80FEF6-$80FEFE (9 bytes) and $86FE52-$86FF78
;    (295 bytes). No other patch of the set uses either.
; ============================================================================

lorom

; ############################################################################
; # PART 1 - Title-screen logo routine (bank $80, state $08 handler)
; ############################################################################
;
; The title / intro screen is a state machine on DP $3A. The dispatcher at
; $80:8CBB does JSR ($8CD1,X) with X = $3A, so the handlers are reached through
; a pointer table: $8F49 (state $06), $8F84 (state $08), $8F9B (state $0A),
; $8FB6 (state $0C), ... Only the first instruction of a handler is ever an
; entry point.
;
; The state $08 handler, as the SA-1 port left it (bank $80, 8-bit A on entry):
;
;         LDA #$0A       : STA $3A          ; 808F84: A9 0A 85 3A  (next state)
;         REP #$20                          ; 808F88: C2 20
;         LDA #$00A0     : STA $6BAC        ; 808F8A: A9 A0 00 8D AC 6B
;         LDA #$0080     : STA $6BAF        ; 808F90: A9 80 00 8D AF 6B
;         SEP #$20                          ; 808F96: E2 20
;         JMP $9485                         ; 808F98: 4C 85 94
;
; The Relocalization Logo patches change the $0080 immediate of the second
; load (to $0070). In the original ROM it sat at file $000F87; the SA-1
; port moved it to $000F91, leaving $000F87 as the "$3A" operand of the
; first STA.
;
; Fix: put "LDA #$0080 : STA $6BAF" back at its original address, $808F86,
; so file $000F87 is the $0080 immediate again (vanilla value). The three
; instructions that used to sit in front of it ($3A write and REP) move to
; a short stub in free space, reached with a BRA / JMP pair; all jumps are
; 16-bit (JMP abs, no JML) so the program bank is never changed. The two
; independent LDA/STA pairs trade places. They write different words, so the
; result is identical:
;
;     $3A = $0A,  $6BAC = $00A0,  $6BAF = $0080,  A 8-bit,  JMP $9485
;
; The next handler, $808F9B (state $0A), is untouched, and none of the old
; interior addresses of this routine is referenced by anything.
;
; SRAM: $6BAC / $6BAF are BW-RAM, and this routine already wrote both with
; the same STA instructions. They are written exactly as before; no new
; BW-RAM writes, no change to write-enable ($2226) or the block map ($2224).
; ----------------------------------------------------------------------------

org $808F84
TitleLogo_State08:
        BRA TitleLogo_State08_Entry         ; 808F84: 80 11   (to $808F97)
TitleLogo_State08_Scroll:
        LDA.w #$0080                        ; 808F86: A9 80 00   (Logo patches: -> #$0070)
        STA $6BAF                           ; 808F89: 8D AF 6B
        LDA.w #$00A0                        ; 808F8C: A9 A0 00
        STA $6BAC                           ; 808F8F: 8D AC 6B
        SEP #$20                            ; 808F92: E2 20
        JMP $9485                           ; 808F94: 4C 85 94
TitleLogo_State08_Entry:
        JMP.w TitleLogo_State08_Prologue    ; 808F97: 4C F6 FE
        NOP                                 ; 808F9A: EA

; ----------------------------------------------------------------------------
; Prologue (bank $80, free space) - the first half of the old routine
; ----------------------------------------------------------------------------
org $80FEF6
TitleLogo_State08_Prologue:
        LDA.b #$0A                          ; 80FEF6: A9 0A
        STA $3A                             ; 80FEF8: 85 3A
        REP #$20                            ; 80FEFA: C2 20
        JMP.w TitleLogo_State08_Scroll      ; 80FEFC: 4C 86 8F

; ############################################################################
; # PART 2 - SA-1 object-type flag tables (bank $86)
; ############################################################################
;
; The SA-1 port runs each object's per-frame code on either CPU. For every
; object list there is a dispatch stub in bank $80 (at $80FE0A, $FE1F, $FE34,
; $FE49, $FE79, $FE8E, $FEA3, reached by JSR/JMP from the object update loops
; at $80D3xx-$80D5xx). Each stub does:
;
;         LDA $80xxxx,X     ; routine address for object type X
;         STA $3180
;         LDX $0A           ; object type
;         LDA tableN,X      ; flag: 0 = run natively on the SNES CPU
;         BEQ native        ;       non-zero = run on the SA-1 (STA $2200)
;
; The flag tables are read with the data bank register = $86 (set once at
; boot, $80:801B: LDA #$86 : PHA : PLB), so they live at $86:FA50-$FB76.
; The seven lists are contiguous, 295 bytes in all:
;
;         list  address   entries    stub operand at
;          0    $86FA50    109       $80FE18
;          1    $86FABD     31       $80FE2D
;          2    $86FADC     52       $80FE42
;          3    $86FB10     24       $80FE57
;          4    $86FB28     71       $80FE87
;          5    $86FB6F      5       $80FE9C
;          6    $86FB74      3       $80FEB1
;
; This is where the Relocalization's script text overlaps, so the whole block
; moves, byte-for-byte and keeping the same order and spacing, to the unused
; area $86FE52-$86FF78 (still in bank $86 so the stubs' DB-relative LDA abs,X
; keeps working; a single delta of +$0402 applies to every operand). All seven
; stub operands are repointed. The old location is blanked back to $FF so
; the merged IPS never writes there.
;
; The table is ROM only: nothing writes it, and no SRAM is involved.
; Reads past a list's end behave as before: into the next list (same
; layout), and past the last list into $FF ("run on SA-1"), which is
; what the SA-1 base patch had before Extra Options placed its strings
; there.
; ----------------------------------------------------------------------------

!OLD_TABLE    = $86FA50
!OLD_SIZE     = 295
!NEW_TABLE    = $86FE52

; ----------------------------------------------------------------------------
; Stub operands (bank $80, LDA abs,X; the operand is the address inside bank $86)
; ----------------------------------------------------------------------------
org $80FE18
        LDA.w ObjFlags_List0&$FFFF,X        ; 80FE18: BD 52 FE
org $80FE2D
        LDA.w ObjFlags_List1&$FFFF,X        ; 80FE2D: BD BF FE
org $80FE42
        LDA.w ObjFlags_List2&$FFFF,X        ; 80FE42: BD DE FE
org $80FE57
        LDA.w ObjFlags_List3&$FFFF,X        ; 80FE57: BD 12 FF
org $80FE87
        LDA.w ObjFlags_List4&$FFFF,X        ; 80FE87: BD 2A FF
org $80FE9C
        LDA.w ObjFlags_List5&$FFFF,X        ; 80FE9C: BD 71 FF
org $80FEB1
        LDA.w ObjFlags_List6&$FFFF,X        ; 80FEB1: BD 76 FF

; ----------------------------------------------------------------------------
; Old location - blanked
; ----------------------------------------------------------------------------
org !OLD_TABLE
        fillbyte $FF
        fill !OLD_SIZE

; ----------------------------------------------------------------------------
; New location
; ----------------------------------------------------------------------------
org !NEW_TABLE
ObjFlags_List0:                                    ; $86FE52  (109 entries, was $86FA50)
        db $01, $01, $00, $00, $01, $00, $01, $00, $01, $01, $00, $01, $00, $01, $01, $01
        db $01, $01, $01, $01, $00, $01, $01, $01, $01, $01, $00, $01, $01, $01, $01, $01
        db $01, $00, $01, $01, $01, $01, $00, $01, $00, $01, $01, $01, $01, $01, $01, $01
        db $00, $00, $00, $00, $01, $01, $01, $00, $01, $01, $01, $01, $00, $01, $01, $01
        db $01, $01, $01, $01, $01, $01, $01, $01, $00, $01, $01, $01, $01, $00, $01, $01
        db $01, $01, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $01, $01
        db $01, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00
ObjFlags_List1:                                    ; $86FEBF  (31 entries, was $86FABD)
        db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $01, $01
        db $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
ObjFlags_List2:                                    ; $86FEDE  (52 entries, was $86FADC)
        db $01, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
        db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
        db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
        db $01, $01, $01, $01
ObjFlags_List3:                                    ; $86FF12  (24 entries, was $86FB10)
        db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $01, $01, $01
        db $01, $01, $00, $01, $01, $01, $01, $01
ObjFlags_List4:                                    ; $86FF2A  (71 entries, was $86FB28)
        db $01, $01, $00, $01, $01, $01, $01, $01, $01, $00, $01, $00, $01, $00, $01, $01
        db $00, $01, $01, $01, $01, $01, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01
        db $01, $00, $01, $01, $01, $01, $01, $00, $01, $01, $00, $01, $01, $01, $00, $00
        db $01, $00, $01, $00, $01, $01, $01, $00, $01, $01, $00, $01, $01, $01, $01, $01
        db $01, $01, $01, $00, $00, $00, $01
ObjFlags_List5:                                    ; $86FF71  (5 entries, was $86FB6F)
        db $00, $01, $01, $01, $01
ObjFlags_List6:                                    ; $86FF76  (3 entries, was $86FB74)
        db $00, $01, $01

; ############################################################################
; # PART 3 - Save data / SRAM check
; ############################################################################
;
; Nothing here changes how, where or when save data is read or written:
;
;   - BW-RAM ($40:0000-$40:1FFF window at $6000) is never written by this
;     patch's own code or data; it only keeps the two STA $6BAC / $6BAF
;     that were already there.
;   - The control-scheme / password area ($40:0100, $6110+) and the Extra
;     Options save area ($40:FF00-$FF1F) are not touched.
;   - The header SRAM-size / chipset bytes ($FFD6-$FFD8) are unchanged.
;   - The boot code at $80:85DF compares the 32 header bytes ($80:FFC0-FFDF,
;     including the title and checksum) with a copy in WRAM ($7EFFA0) only
;     to decide whether to reload the control scheme from BW-RAM on the
;     first intro after power-on. The Rockman patch's title change and this
;     patch's new checksum simply change that WRAM copy; no saved data
;     depends on them.
;
; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $74, $7D, $8B, $82                                                 ; 80FFDC

; ============================================================================
; End of patch
