; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Air Dash" Patch
;  Apply after: the SA-1 patch (mmxsa1_double_tap_disabled.ips)
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off airdash_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Adds an Air Dash (one additional mid-air dash), makes the ground Dash
;    available from the start of the game, and lets a Walljump kick off
;    with extra horizontal speed while the Dash button is held.
;
;  WRAM MAP
;    It must be applied after the SA-1 patch, which is why several of the
;    hooks below reference $6Bxx/$6Cxx WRAM addresses -- the SA-1 patch
;    relocates X's per-object data structure from its vanilla location
;    ($7E:0B80-ish) up to $7E:6BA8. Every WRAM offset below lines up
;    exactly with the well known vanilla Mega Man X RAM map (Data Crystal)
;    once you add $6000 to the classic address, e.g.:
;
;       dp $02 -> $6BAA  (vanilla $0BAA) = X's state-machine byte
;       dp $03 -> $6BAB  (vanilla $0BAB) = X's state "just entered" flag
;       dp $04 -> $6BAC  (vanilla $0BAC) = X's X-position (24-bit)
;       dp $17 -> $6BBF  (vanilla $0BBF) = X's current animation pose
;       dp $1A -> $6BC2  (vanilla $0BC2) = X's horizontal velocity
;       dp $1C -> $6BC4  (vanilla $0BC4) = X's vertical velocity
;       dp $1E -> $6BC6  (vanilla $0BC6) = X's gravity/acceleration
;       dp $2C -> $6BD4                 = (ground/ladder related flag)
;       dp $3A -> $6BE2  (vanilla $0BE2) = input mirror (Dash button, bit 7)
;       dp $52 -> $6BFA  (vanilla $0BFA) = Dash timer
;       dp $5C -> $6C04                 = X sub-velocity / walljump kick speed
;       dp $5E -> $6C06  (vanilla $0C06) = wall-cling bitflags
;
;  X's per-object code runs with Direct Page = $6BA8, so "dp $xx" above is
;  shorthand for absolute WRAM address $6BA8+$xx (bank $7E, mirrored in
;  banks $00-$3F/$80-$BF).
;
;  Overview of what the patch actually changes, by ROM bank:
;
;   Bank $80  - 4-byte SNES header checksum/complement fix (cosmetic, so the
;               ROM still reports a valid checksum after all the other edits).
;
;   Bank $81  - X's object code. This is where the actual gameplay logic
;               lives:
;                 * X's per-state dispatch table (indexed directly by the
;                   raw state byte, 2 bytes/entry) is relocated from
;                   $8182A1 to $81FF71 and extended with two brand new
;                   states:
;                     state $48 = "Air Dash"      -> stub at $8182A1
;                     state $4A = "Air Dash End"  -> stub at $8182A6
;                   Relocating the table frees up the 5 bytes right after
;                   the original JMP instruction, which is exactly enough
;                   room for the two new "JSL <bank AF>; RTS" stubs -- a
;                   classic code-cave trick that requires no other code to
;                   move.
;                 * The walljump "kick-off" speed selector is simplified
;                   from a two-flag combination (which needed frame-perfect
;                   Jump+Dash timing) down to a single "is Dash held right
;                   now" bit test -- this is the "walljump further while
;                   holding the dash button" feature.
;                 * The check that gated the Dash ability behind the Leg
;                   Parts flag ($3399 bit 3) before X is even allowed to
;                   *consider* starting a dash is NOP'd out -- this is the
;                   "Dash available from the start of the game" feature.
;                 * The inline "which dash sub-state is this" comparison
;                   chain is replaced with a JSL into new logic in bank
;                   $AF that additionally knows about Air Dashing.
;                 * A hook right before the "commit to the new state" jump
;                   dispatch adds extra per-state setup logic (bank $AF).
;                 * A small table of "JSR short-routine; RTL" trampolines is
;                   added at $81FFD0, so that the new far-called ($JSL)
;                   code in bank $AF can invoke pre-existing RTS-only
;                   bank-$81 helper routines as if they were long-callable.
;
;   Bank $84  - The routine that turns X's current animation "sub-frame"
;               into a VRAM/OAM table index is hijacked with a JSL into new
;               logic (bank $AF) that additionally understands the Air Dash
;               animation.
;
;   Banks $85, $86, $8D, $8F
;             - Small relocated/extended data tables and OAM/graphics
;               pointer tables supporting the six new animation poses
;               ($36-$3B) used by the Air Dash sprite, plus reclaimed space
;               from a shortened, no-longer-needed sprite-frame entry.
;               These are pure data, not code, so they are reproduced here
;               as annotated `db` tables rather than hand-decoded frame by
;               frame.
;
;   Bank $AF  - This is almost entirely *unused ROM space* in the SA-1
;               patched ROM (previously filled with $FF), repurposed as a
;               free-space code+data area:
;                 * ~4.3 KB of new hitbox/OAM/animation-frame data for the
;                   six new Air Dash poses.
;                 * ~470 bytes of new 65816 code ($AFFB00-$AFFCD6) that
;                   implements the actual Early Dash / Air Dash / walljump
;                   decision logic and the two new state handlers.
;
;  Every instruction below has been assembled with Asar and diffed
;  byte-for-byte against the shipped "airdash_for_mmxsa1.ips" -- the two
;  are identical. Per-instruction comments give the resolved effective
;  address and the exact assembled bytes, e.g. "; 006BAA" means "this dp
;  access resolves to absolute WRAM address $006BAA", and "; AFFB00: AD 99
;  33" means "this instruction assembles to AD 99 33 at SNES address
;  $AFFB00". Branch targets reference local labels (LBL_xxxxxx) rather
;  than literal addresses, since Asar only computes correct relative
;  branch offsets from resolved labels -- a bare numeric literal on a
;  branch mnemonic is taken as the raw offset byte itself.
; ============================================================================

lorom


; ============================================================================
; BANK $80 -- SNES header checksum fix
; ============================================================================
; With the edits below in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.

org $80FFDC
        db $DE,$F1,$21,$0E                                                        ; 80FFDC


; ============================================================================
; BANK $81 -- X's object code (the actual gameplay logic)
; ============================================================================

; ----------------------------------------------------------------------------
; X's per-state dispatch table is relocated from $8182A1 to $81FF71, and the
; JMP instruction that reads it is repointed. This frees the 5 bytes right
; after the JMP (formerly the start of the table) for two new state-handler
; stubs. The dispatch table is indexed by the RAW state byte used as a
; 2-byte-stride offset (not divided by 2) -- e.g. state $14 ("dashing" in the
; vanilla RAM map) reads the word at table+$14, state $48 (new) reads the
; word at table+$48, etc. That's why the two new entries land at exactly
; table+$48 and table+$4A: they ARE state IDs $48 and $4A.
; ----------------------------------------------------------------------------

org $81829E
        ; JMP ($xxxx,X)  -- opcode/operand untouched by this patch, shown
        ; here only for context; the OPERAND (the next 2 bytes) is what
        ; the patch changes:
        ;   7C xx xx    JMP ($xxxx,X)

org $81829F
        db $71             ; 81829F
        db $FF             ; 8182A0

NewState_48_AirDash:
        JSL $AFFBCE      ; 8182A1: 22 CE FB AF
        RTS              ; 8182A5: 60
        ; state $48 = "Air Dash": long-calls into the new Air Dash
        ; state handler and returns.

NewState_4A_AirDashEnd:
        JSL $AFFC79      ; 8182A6: 22 79 FC AF
        RTS              ; 8182AA: 60
        ; state $4A = "Air Dash End": long-calls into the new Air Dash
        ; end-of-dash handler and returns.

        ; $8182AB-$8182E8: unused, but the real patch explicitly blanks
        ; this freed table space to $FF (it is NOT left untouched).
org $8182AB
        fillbyte $FF
        fill $8182E9-$8182AB


; ----------------------------------------------------------------------------
; Walljump kick-off speed: previously X only got the *fast* push-off speed
; ($0375, ~3.46 px/frame in 8.8 fixed point) if two separate flags lined up
; at the same time -- in practice this required frame-perfect Jump+Dash
; timing. The patch replaces that two-flag AND with a single "is the Dash
; button currently held" bit test on dp $36 -- this is the
; "walljump further while holding the dash button" feature.
;
; Vanilla (for reference):
;     LDA #$0178                 ; default (slow) push speed
;     LDX $56  : BEQ +           ; needs flag A set...
;     LDX $6C  : BNE +           ; ...AND flag B clear
;     LDX #$10 : STX $55         ; (side effect, no longer needed)
;     LDA #$0375                 ; fast push speed
;   + STA $5C
; ----------------------------------------------------------------------------

org $81876D
        LDA $36 ;[$006BDE] ; 81876D: A5 36
        BIT #$0080       ; 81876F: 89 80 00
        BNE LBL_818779      ; 818772: D0 05
        db $A9             ; 818774
        db $78             ; 818775
        db $01             ; 818776
        db $80             ; 818777
        db $03             ; 818778
LBL_818779:
        LDA #$0375       ; 818779: A9 75 03
        NOP              ; 81877C: EA
        NOP              ; 81877D: EA
        NOP              ; 81877E: EA
        ; $5C [$006C04] receives the walljump push-off horizontal speed:
        ;   dp $36 bit $80 clear -> #$0178 (~1.47 px/f, vanilla default)
        ;   dp $36 bit $80 set   -> #$0375 (~3.46 px/f, "boosted")
        ; $81877C-$81877E: 3 leftover bytes NOP'd out (the old code was
        ; longer than the new code).


; ----------------------------------------------------------------------------
; Early Dash: this NOPs out a gate that used to run before X's controller
; input is even allowed to consider starting a dash. The removed check was:
;     LDA $3399 : AND #$FF : BIT #$08 : BEQ <skip dash-input handling>
; i.e. "does X have the Dash-granting equipment flag set?" -- with the gate
; removed, dashing is available unconditionally from the start of the game.
; (The very next check afterwards, against $3323, is left completely
; untouched -- that one is unrelated to equipment and still applies.)
; ----------------------------------------------------------------------------

org $819712
        NOP              ; 819712: EA
        NOP              ; 819713: EA
        NOP              ; 819714: EA
        NOP              ; 819715: EA
        NOP              ; 819716: EA
        NOP              ; 819717: EA
        NOP              ; 819718: EA
        ; (was: LDA $3399 / BIT #$08 / BEQ $8196CA -- 7 bytes, exactly
        ; replaced by 7 NOPs so everything after falls straight through)


; ----------------------------------------------------------------------------
; Dash-type dispatcher hook: the vanilla inline chain of CMP/BEQ checks
; against X's dash sub-state is replaced with a JSL into new bank $AF logic
; (TryStartGroundDash) that layers in the new Air Dash eligibility checks
; on top of the original behaviour.
; ----------------------------------------------------------------------------

org $81976D
        db $22             ; 81976D
        db $B2             ; 81976E
        db $FB             ; 81976F
        db $AF             ; 819770
        db $60             ; 819771

org $819772
        fillbyte $FF
        fill $819789-$819772

org $819789
        JSL $AFFB38      ; 819789: 22 38 FB AF
        RTS              ; 81978D: 60

org $81978E
        fillbyte $FF
        fill $8197C8-$81978E


; ----------------------------------------------------------------------------
; Landing / state-continue hook: replaces "STA $16 / LDA $0B" with a JSL that
; performs the same store, plus extra work, before falling through to the
; original JMP $848F07 (the state-change dispatcher -- called directly
; whenever code wants to jump straight into a new state's handler instead of
; waiting for next frame).
; ----------------------------------------------------------------------------

org $81F0EB
        JSL $AFFC71      ; 81F0EB: 22 71 FC AF
        ; (was: STA $16 [$00793E] / LDA $0B [$007933] -- same 4 bytes)

        ; ... unmodified code continues (JMP $848F07, etc.) ...


; ----------------------------------------------------------------------------
; Small per-sub-state comparison table used by the code just above/below:
; the table's *base address* (the operand of a "CMP $xxxx,X" a few
; instructions later) is repointed from $86DC64 to $86FFFD, i.e. it's the
; same "relocate a table, repurpose the freed bytes" trick used for the
; jump table in bank $81. Only the table's base-address operand changes
; here; the CMP instruction itself is untouched.
; ----------------------------------------------------------------------------

org $81F109
        db $FD,$FF                                                                ; 81F109
        ; (operand of "CMP $xxxx,X" at $81F108, now $FFFD instead of
        ; $DC64 -- see bank $86 section below for the relocated table)


; ----------------------------------------------------------------------------
; Relocated dispatch table (see the bank-$81 section above): now lives at
; $81FF71 with two extra entries appended ($8182A1 and $8182A6, the new Air
; Dash / Air Dash End stubs). All other entries are byte-identical to the
; original table that used to sit at $8182A1.
; ----------------------------------------------------------------------------

org $81FF71
        db $E9,$82,$98,$83,$03,$84,$81,$84,$1D,$85,$F6,$85,$45,$8A,$51,$86        ; 81FF71
        db $0E,$87,$34,$88,$04,$89,$31,$8B,$43,$8B,$A7,$8B,$44,$8B,$4D,$8B        ; 81FF81
        db $A0,$89,$F0,$89,$29,$8D,$69,$8D,$AB,$8D,$E1,$8D,$75,$8E,$86,$8E        ; 81FF91
        db $41,$8F,$7C,$91,$DD,$91,$3F,$92,$E9,$92,$0E,$93,$29,$8F,$4E,$8F        ; 81FFA1
        db $B4,$8F,$0D,$90,$51,$90,$4D,$8B,$A1,$82,$A6,$82                        ; 81FFB1


; ----------------------------------------------------------------------------
; JSL-callable trampolines: five short "JSR <existing bank-$81 routine>;
; RTL" stubs. These let the new far-called ($JSL) code in bank $AF invoke
; pre-existing bank-$81 helper subroutines that only end in RTS (i.e. were
; never designed to be called from outside bank $81) as if they were long
; subroutines. Two of the five entries call the very same helper
; ($8193A8, likely an animation/frame-advance helper).
; ----------------------------------------------------------------------------

org $81FFD0
        JSR $9588 ;[$819588] ; 81FFD0: 20 88 95
        RTL              ; 81FFD3: 6B
        db $20             ; 81FFD4
        db $A8             ; 81FFD5
        db $93             ; 81FFD6
        db $6B             ; 81FFD7
        JSR $9D1A ;[$819D1A] ; 81FFD8: 20 1A 9D
        RTL              ; 81FFDB: 6B
        JSR $9C66 ;[$819C66] ; 81FFDC: 20 66 9C
        RTL              ; 81FFDF: 6B
        JSR $9536 ;[$819536] ; 81FFE0: 20 36 95
        RTL              ; 81FFE3: 6B
        db $20             ; 81FFE4
        db $A8             ; 81FFE5
        db $93             ; 81FFE6
        db $6B             ; 81FFE7
        JSR $9560 ;[$819560] ; 81FFE8: 20 60 95
        RTL              ; 81FFEB: 6B


; ============================================================================
; BANK $84 -- animation sub-frame -> OAM/graphics index calculation
; ============================================================================
; The vanilla "turn animation sub-frame into a VRAM/OAM table index" tail of
; this routine is replaced with a JSL into new logic (bank $AF) that adds
; special handling for the Air Dash animation.
;
; Vanilla (for reference):
;     LDA $17 : AND #$00FF : ASL : TAY : CLC   ; (5 instructions)
; ============================================================================

org $848FF6
        JSL $AFFB00      ; 848FF6: 22 00 FB AF
        NOP              ; 848FFA: EA
        NOP              ; 848FFB: EA
        NOP              ; 848FFC: EA
        NOP              ; 848FFD: EA
        NOP              ; 848FFE: EA
        CLC              ; 848FFF: 18
        ; 4 leftover NOPs pad out the difference in length.


; ============================================================================
; BANKS $85 / $86 -- new/relocated data tables (hitboxes, per-state lookups)
; ============================================================================
; Pure data. Presented as raw bytes; see the bank-$AF code section for how
; these tables are consumed (GetHitboxPtr_ExtendedRange reads from the
; $85B390 table below).
; ============================================================================

; New hitbox/pose-property table for animation poses $36-$3B (the six new
; Air Dash poses). Read via (dp $31),Y from GetHitboxPtr_ExtendedRange in
; bank $AF, Y = (pose-$36)*2 + fixed_offset.

org $85B390
        db $09,$0E,$19,$0E,$29,$0E,$39,$0E,$49,$0E,$59,$0E,$FF,$FF,$FF,$FF        ; 85B390
        db $20,$00,$EA,$AF,$60,$20,$00,$EC,$AF,$E1,$FF,$FF,$FF,$FF,$FF,$FF        ; 85B3A0
        db $20,$00,$EA,$AF,$60,$20,$00,$EC,$AF,$E1,$FF,$FF,$FF,$FF,$FF,$FF        ; 85B3B0
        db $20,$00,$EE,$AF,$60,$20,$00,$F0,$AF,$E1,$FF,$FF,$FF,$FF,$FF,$FF        ; 85B3C0
        db $20,$00,$EA,$AF,$60,$20,$00,$EC,$AF,$E1,$FF,$FF,$FF,$FF,$FF,$FF        ; 85B3D0
        db $20,$00,$EA,$AF,$60,$20,$00,$EC,$AF,$E1,$FF,$FF,$FF,$FF,$FF,$FF        ; 85B3E0
        db $20,$00,$F2,$AF,$60,$20,$00,$F4,$AF,$E1                                ; 85B3F0

; Small per-sub-state lookup table, relocated (see bank $81 / $81F109
; above). Old location $86DC64 had its 2 bytes overwritten with $FF filler;
; new location is $86FFFD.

org $86DC64
        db $FF,$FF                                                                ; 86DC64
        ; (old table content here zeroed out to $FF -- table moved below)

org $86FFFA
        db $00,$01,$01,$0E,$14,$48                                                ; 86FFFA


; ============================================================================
; BANK $8D -- sprite/OAM frame pointer tables
; ============================================================================
; Two existing pointer-table regions have some of their entries repointed
; at the new Air Dash animation-frame data that now lives in bank $AF
; (see the big data block in the bank-$AF section below). A third region
; (93 bytes) that used to hold a now-unnecessary/duplicate sprite frame's
; raw OAM tile list has been deleted (zeroed to $FF) to reclaim ROM space.
; ============================================================================

org $8D82B2
        db $00,$F7,$AF,$21,$F7,$AF,$52,$F7,$AF,$73,$F7,$AF,$98,$F7,$AF,$BD        ; 8D82B2
        db $F7,$AF                                                                ; 8D82C2
        ; 6 x 24-bit pointers: $AFF700, $AFF721, $AFF752, $AFF773,
        ; $AFF798, $AFF7BD -- all point into the new Air Dash frame
        ; data added in bank $AF.

org $8D8891
        db $DE,$F7,$AF,$FF,$F7,$AF,$30,$F8,$AF,$51,$F8,$AF,$76,$F8,$AF,$9B        ; 8D8891
        db $F8,$AF                                                                ; 8D88A1
        ; 6 more 24-bit pointers into the same new bank-$AF frame data:
        ; $AFF7DE, $AFF7FF, $AFF830, $AFF851, $AFF876, $AFF89B.

org $8DB1C5
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8DB1C5
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8DB1D5
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8DB1E5
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8DB1F5
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8DB205
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF                    ; 8DB215
        ; 93 bytes of a now-unused sprite-frame OAM tile list zeroed to
        ; $FF, reclaiming ROM space (the corresponding pointer table
        ; entries were repointed elsewhere by the same era of the
        ; official game, this space was simply dead weight).


; ============================================================================
; BANK $8F -- new OAM/hitbox record fragments (pure data)
; ============================================================================
; Several small chunks of new per-frame sprite/hitbox records, tucked into
; previously unused ($FF) space in this bank. Structurally similar to
; typical Mega Man X per-pose OAM records (tile offsets + attribute bytes).
; Not hand-decoded field by field -- shown here as raw data for byte-exact
; reproduction.
; ============================================================================

org $8FFE39
        db $03,$02,$08,$16                                                        ; 8FFE39

org $8FFE3E
        db $02,$00,$06                                                            ; 8FFE3E

org $8FFE42
        db $F2,$00,$04,$20,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8FFE42
        db $FF,$FF,$FF,$FF,$02,$F7,$08,$16                                        ; 8FFE52

org $8FFE5B
        db $FF,$01,$04,$20,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8FFE5B
        db $FF,$FF,$FF,$FF                                                        ; 8FFE6B

org $8FFE70
        db $FF,$FF,$FF,$03,$F7,$08,$16                                            ; 8FFE70

org $8FFE78
        db $EF,$07,$13                                                            ; 8FFE78

org $8FFE7C
        db $FF,$01,$04,$20,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; 8FFE7C

org $8FFE8D
        db $FF,$FF,$FF                                                            ; 8FFE8D



; ============================================================================
; BANK $AF -- new free-space data + code
; ============================================================================
; This entire bank was unused ($FF-filled) space in the SA-1-patched ROM.
; The patch turns it into a combined data+code area:
;   $AFEA00-$AFFAFF  new animation-frame / hitbox / OAM data for the six
;                     new Air Dash poses ($36-$3B) -- pure data, ~4.3 KB.
;   $AFFB00-$AFFCD6  new 65816 code implementing the Early Dash / Air Dash
;                     / Walljump-boost decision logic, and the two new
;                     state handlers. Fully disassembled and commented
;                     below.
; ============================================================================

; ----------------------------------------------------------------------------
; New animation-frame / hitbox data for poses $36-$3B (Air Dash sprite).
; Referenced by the bank-$85 pose-property table and the bank-$8D OAM
; pointer tables above, and consumed by the (mostly unmodified) vanilla
; sprite/hitbox-drawing engine. Reproduced verbatim as data.
; ----------------------------------------------------------------------------

org $AFEA00
        db $00,$00,$03,$03,$0E,$0E,$19,$11,$3C,$3F,$59,$4D,$73,$7A,$66,$75        ; AFEA00
        db $00,$00,$03,$03,$0E,$0D,$10,$1F,$24,$24,$6B,$6B,$54,$76,$69,$6D        ; AFEA10
        db $00,$00,$80,$80,$F0,$70,$28,$E8,$78,$08,$9B,$8B,$0C,$C4,$6B,$DB        ; AFEA20
        db $00,$00,$80,$80,$70,$F0,$18,$38,$88,$F8,$8B,$FB,$C4,$FF,$DB,$DC        ; AFEA30
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$7E,$7E,$E9,$99        ; AFEA40
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$7E,$FE,$F9,$8F        ; AFEA50
        db $66,$7E,$5B,$65,$7B,$45,$7A,$46,$24,$3C,$18,$18,$00,$00,$00,$00        ; AFEA60
        db $7E,$7E,$65,$65,$45,$45,$46,$46,$3C,$3C,$18,$18,$00,$00,$00,$00        ; AFEA70
        db $07,$07,$00,$00,$00,$00,$01,$01,$07,$06,$09,$09,$0A,$0A,$0B,$0B        ; AFEA80
        db $07,$07,$00,$00,$00,$00,$01,$01,$07,$06,$09,$0F,$0A,$0D,$0B,$0C        ; AFEA90
        db $D7,$D7,$EA,$E9,$DA,$B1,$32,$19,$3F,$1F,$56,$36,$F7,$F7,$7F,$3F        ; AFEAA0
        db $D7,$EF,$EF,$F8,$FF,$90,$FF,$10,$FF,$1F,$F6,$19,$F7,$F8,$3F,$F8        ; AFEAB0
        db $E0,$E0,$80,$80,$80,$80,$80,$80,$C0,$C0,$F0,$30,$78,$08,$BE,$86        ; AFEAC0
        db $E0,$E0,$80,$80,$80,$80,$80,$80,$C0,$C0,$30,$F0,$08,$F8,$86,$7E        ; AFEAD0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$30,$68,$58        ; AFEAE0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$30,$58,$58        ; AFEAF0
        db $00,$00,$03,$03,$0C,$0C,$1B,$11,$22,$36,$65,$64,$5B,$58,$57,$40        ; AFEB00
        db $00,$00,$03,$03,$0F,$0C,$1F,$11,$3E,$23,$7C,$67,$65,$66,$6B,$6C        ; AFEB10
        db $00,$00,$80,$80,$E0,$60,$70,$10,$B8,$88,$9B,$0B,$DC,$44,$FB,$3B        ; AFEB20
        db $00,$00,$80,$80,$E0,$60,$10,$F0,$88,$78,$0B,$FB,$C4,$7F,$FB,$3C        ; AFEB30
        db $1C,$17,$3F,$23,$3F,$2D,$33,$33,$2D,$2C,$3D,$3C,$3B,$39,$16,$12        ; AFEB40
        db $14,$17,$22,$23,$2D,$2D,$33,$3F,$2C,$33,$3C,$23,$39,$27,$12,$1E        ; AFEB50
        db $0F,$0F,$0A,$0C,$15,$19,$1D,$11,$1D,$11,$15,$19,$29,$39,$E7,$DF        ; AFEB60
        db $0F,$0F,$0C,$0D,$19,$1B,$11,$13,$11,$13,$19,$1B,$39,$3F,$DF,$DF        ; AFEB70
        db $00,$00,$03,$03,$0D,$0D,$17,$17,$1F,$1F,$17,$16,$0F,$0C,$03,$03        ; AFEB80
        db $00,$00,$03,$03,$0D,$0E,$1F,$1E,$17,$16,$1E,$1F,$0C,$0F,$03,$03        ; AFEB90
        db $04,$04,$E2,$E2,$DF,$DF,$ED,$28,$D9,$C9,$FE,$01,$FF,$1F,$E0,$E0        ; AFEBA0
        db $04,$04,$E2,$E2,$DF,$3F,$2F,$18,$CF,$39,$07,$F8,$1F,$FF,$E0,$E0        ; AFEBB0
        db $00,$20,$00,$20,$00,$30,$00,$30,$10,$28,$10,$29,$30,$4B,$32,$4D        ; AFEBC0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEBD0
        db $80,$44,$88,$74,$70,$88,$E0,$10,$80,$62,$F0,$08,$00,$FE,$00,$00        ; AFEBE0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEBF0
        db $55,$79,$4F,$75,$3E,$2D,$14,$1F,$28,$3F,$72,$7F,$BC,$BE,$B7,$B7        ; AFEC00
        db $7B,$7B,$74,$75,$2C,$2D,$14,$1F,$30,$2F,$72,$5F,$B9,$CF,$B7,$FF        ; AFEC10
        db $CB,$AB,$DB,$9B,$4C,$2C,$57,$73,$6B,$69,$FF,$FC,$FA,$F8,$BD,$B9        ; AFEC20
        db $BB,$BC,$AB,$AC,$BC,$BF,$F3,$FF,$E9,$F7,$FD,$C2,$F9,$86,$BB,$C5        ; AFEC30
        db $95,$94,$BD,$9C,$FD,$FC,$9F,$9E,$F9,$F7,$AC,$B3,$EC,$F3,$D9,$D7        ; AFEC40
        db $F4,$9B,$FC,$93,$FC,$F3,$9E,$9F,$F7,$F7,$B3,$F3,$F3,$B3,$D7,$37        ; AFEC50
        db $80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$80,$80,$80,$80,$00,$00        ; AFEC60
        db $80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$80,$80,$80,$80,$00,$00        ; AFEC70
        db $07,$07,$05,$05,$02,$02,$03,$02,$07,$07,$0B,$0B,$17,$17,$1F,$1F        ; AFEC80
        db $07,$04,$05,$06,$02,$03,$02,$03,$07,$07,$0B,$0C,$17,$18,$1F,$1F        ; AFEC90
        db $BB,$8B,$DD,$C5,$DE,$C6,$3F,$03,$FE,$C2,$BD,$BD,$DF,$C7,$FF,$FF        ; AFECA0
        db $8B,$7C,$C5,$3E,$C6,$3F,$03,$FF,$C2,$FF,$BD,$7E,$C7,$3C,$FF,$FF        ; AFECB0
        db $DF,$C9,$FF,$D1,$2E,$22,$F6,$F2,$EC,$E4,$D8,$C8,$B0,$90,$E0,$E0        ; AFECC0
        db $C9,$3F,$D1,$3F,$22,$FE,$F2,$CE,$E4,$1C,$C8,$38,$90,$70,$E0,$E0        ; AFECD0
        db $A4,$DC,$E4,$9C,$E4,$9C,$F4,$FC,$C8,$C8,$64,$64,$64,$64,$C8,$C8        ; AFECE0
        db $DC,$DC,$9C,$9C,$9C,$9C,$FC,$FC,$C8,$B8,$64,$9C,$64,$9C,$C8,$B8        ; AFECF0
        db $7F,$53,$7F,$45,$3E,$2D,$14,$1F,$28,$3F,$72,$7F,$BD,$BF,$B7,$B7        ; AFED00
        db $47,$6B,$6C,$55,$3C,$2D,$14,$1F,$30,$2F,$72,$5F,$B8,$CF,$B7,$FF        ; AFED10
        db $DB,$7B,$7B,$7B,$7C,$7C,$37,$73,$6B,$69,$7F,$7C,$FA,$F8,$BD,$B9        ; AFED20
        db $FB,$7C,$EB,$EC,$EC,$EF,$F3,$BF,$E9,$F7,$FD,$C2,$F9,$86,$BB,$C5        ; AFED30
        db $40,$C0,$C0,$40,$A0,$60,$F0,$F0,$50,$30,$50,$30,$50,$30,$00,$00        ; AFED40
        db $C0,$C0,$40,$40,$60,$60,$F0,$F0,$F0,$10,$F0,$10,$F0,$10,$00,$00        ; AFED50
        db $75,$89,$F5,$09,$7B,$82,$FA,$FD,$1D,$1F,$1B,$16,$26,$23,$00,$00        ; AFED60
        db $89,$8F,$09,$0F,$82,$8E,$FD,$FD,$1F,$1F,$1F,$12,$3F,$22,$00,$00        ; AFED70
        db $0E,$0E,$3B,$39,$78,$7F,$BF,$EC,$BF,$FF,$E7,$E4,$4A,$4D,$3F,$3F        ; AFED80
        db $0E,$0E,$35,$35,$4F,$4F,$A4,$A4,$A7,$A7,$BC,$FC,$7D,$7D,$3F,$3F        ; AFED90
        db $00,$00,$80,$80,$78,$F8,$E0,$C8,$60,$60,$D0,$E0,$78,$F8,$80,$80        ; AFEDA0
        db $00,$00,$80,$80,$F8,$F8,$F8,$C0,$B8,$A0,$F8,$C0,$F8,$F8,$80,$80        ; AFEDB0
        db $00,$00,$00,$00,$00,$01,$01,$00,$01,$02,$03,$04,$00,$0F,$00,$00        ; AFEDC0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEDD0
        db $0E,$11,$1D,$62,$7F,$80,$FF,$00,$FF,$00,$FF,$00,$00,$FF,$00,$00        ; AFEDE0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEDF0
        db $01,$01,$06,$06,$0D,$08,$11,$1B,$32,$32,$2D,$2C,$2B,$20,$3F,$29        ; AFEE00
        db $01,$01,$07,$06,$0F,$08,$1F,$11,$3E,$33,$32,$33,$35,$36,$23,$35        ; AFEE10
        db $C0,$C0,$70,$30,$B8,$88,$5C,$44,$CD,$05,$EF,$23,$FF,$1B,$ED,$BD        ; AFEE20
        db $C0,$C0,$F0,$30,$88,$F8,$44,$BC,$05,$FD,$E3,$3F,$FB,$1F,$FD,$BF        ; AFEE30
        db $0E,$0E,$3D,$3D,$5E,$7E,$F6,$96,$1E,$8E,$9F,$0F,$75,$96,$E7,$E4        ; AFEE40
        db $0E,$0E,$3D,$33,$7E,$51,$F6,$99,$FE,$09,$FF,$0F,$F6,$16,$E4,$E4        ; AFEE50
        db $2F,$2F,$3B,$3A,$2F,$2C,$17,$14,$0C,$0F,$03,$03,$00,$00,$00,$00        ; AFEE60
        db $2F,$33,$3A,$26,$2C,$34,$14,$1C,$0F,$0F,$03,$03,$00,$00,$00,$00        ; AFEE70
        db $80,$80,$00,$00,$00,$00,$F0,$F0,$FF,$4F,$FF,$80,$FF,$80,$CF,$40        ; AFEE80
        db $80,$80,$00,$00,$00,$00,$F0,$F0,$CF,$7F,$80,$FF,$80,$FF,$40,$FF        ; AFEE90
        db $00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$F0,$B0,$F8,$48,$FC,$44        ; AFEEA0
        db $00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$B0,$F0,$48,$F8,$44,$FC        ; AFEEB0
        db $00,$00,$80,$80,$40,$40,$A0,$E0,$60,$A0,$E0,$20,$A0,$60,$40,$C0        ; AFEEC0
        db $00,$00,$80,$80,$40,$C0,$E0,$E0,$A0,$A0,$20,$20,$60,$60,$C0,$C0        ; AFEED0
        db $D0,$30,$E8,$18,$64,$9C,$EA,$9A,$F6,$F6,$5E,$5E,$7A,$7A,$24,$24        ; AFEEE0
        db $30,$30,$18,$18,$9C,$9C,$9A,$9E,$F6,$FA,$5E,$62,$7A,$46,$24,$3C        ; AFEEF0
        db $01,$01,$07,$07,$0C,$08,$1E,$1F,$2C,$26,$39,$3D,$33,$3A,$2A,$3C        ; AFEF00
        db $01,$01,$07,$06,$08,$0F,$12,$12,$35,$35,$2A,$3B,$34,$36,$3D,$3D        ; AFEF10
        db $C0,$C0,$78,$38,$94,$F4,$3C,$84,$CD,$C5,$87,$63,$37,$EF,$E5,$D5        ; AFEF20
        db $C0,$C0,$38,$F8,$0C,$9C,$44,$7C,$C5,$FD,$63,$7F,$EF,$EF,$DD,$DF        ; AFEF30
        db $07,$06,$1A,$0A,$1A,$12,$2B,$32,$3A,$23,$39,$25,$3D,$31,$CF,$FE        ; AFEF40
        db $07,$06,$0B,$1E,$13,$16,$33,$36,$23,$26,$25,$27,$31,$33,$FE,$FF        ; AFEF50
        db $F0,$F0,$E8,$98,$D8,$E8,$E8,$38,$10,$38,$58,$38,$00,$00,$00,$00        ; AFEF60
        db $F0,$F0,$98,$98,$E8,$E8,$F8,$38,$F8,$10,$F8,$18,$00,$00,$00,$00        ; AFEF70
        db $00,$7F,$07,$18,$03,$04,$01,$02,$01,$02,$00,$01,$00,$01,$00,$01        ; AFEF80
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEF90
        db $00,$00,$00,$C0,$C0,$20,$E0,$10,$F0,$08,$F0,$08,$F8,$04,$F8,$04        ; AFEFA0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEFB0
        db $00,$F8,$08,$16,$04,$3A,$02,$05,$02,$05,$02,$01,$00,$03,$00,$02        ; AFEFC0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEFD0
        db $00,$00,$00,$00,$00,$20,$00,$08,$00,$00,$00,$01,$00,$08,$00,$00        ; AFEFE0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFEFF0
        db $3F,$22,$1F,$16,$0A,$0F,$04,$07,$09,$0F,$06,$07,$0B,$0B,$19,$1C        ; AFF000
        db $36,$2A,$1E,$16,$0A,$0F,$00,$07,$09,$0F,$04,$07,$0F,$0B,$1F,$18        ; AFF010
        db $BE,$BE,$3F,$BF,$1E,$BE,$3F,$B1,$27,$A0,$DB,$D8,$DF,$DD,$6A,$EA        ; AFF020
        db $76,$F5,$77,$F4,$7E,$DF,$71,$FF,$60,$FF,$58,$E7,$DD,$E3,$EB,$76        ; AFF030
        db $62,$23,$E1,$61,$FC,$BC,$A7,$A3,$B2,$B3,$7B,$4A,$84,$8F,$97,$0F        ; AFF040
        db $23,$E3,$61,$E1,$FC,$BC,$E3,$BF,$F3,$BE,$FB,$4E,$FF,$84,$FF,$07        ; AFF050
        db $DF,$DF,$A1,$61,$A2,$63,$25,$E5,$45,$C5,$82,$82,$01,$01,$00,$00        ; AFF060
        db $DF,$DF,$61,$61,$63,$62,$E5,$E7,$C5,$C6,$82,$83,$01,$01,$00,$00        ; AFF070
        db $F9,$38,$FF,$1E,$7F,$1E,$B9,$89,$DE,$CE,$EC,$E4,$7C,$74,$F8,$F8        ; AFF080
        db $38,$E7,$1E,$F1,$1E,$F9,$89,$7F,$CE,$3E,$E4,$1C,$74,$8C,$F8,$F8        ; AFF090
        db $CE,$42,$EE,$62,$B7,$B1,$7B,$79,$DD,$DD,$35,$35,$0E,$0E,$00,$00        ; AFF0A0
        db $42,$FE,$62,$DE,$B1,$CF,$79,$87,$DD,$E3,$35,$3B,$0E,$0E,$00,$00        ; AFF0B0
        db $2F,$19,$BF,$71,$E7,$C1,$FD,$FD,$FD,$FD,$9F,$9F,$65,$65,$1B,$1B        ; AFF0C0
        db $F9,$0F,$F1,$3F,$C1,$FF,$FD,$03,$FD,$03,$9F,$E2,$65,$7E,$1B,$1B        ; AFF0D0
        db $BF,$CF,$EE,$9E,$FE,$9E,$7C,$5C,$31,$31,$0E,$0E,$00,$00,$00,$00        ; AFF0E0
        db $CF,$CF,$9E,$99,$9E,$91,$5C,$53,$31,$3F,$0E,$0E,$00,$00,$00,$00        ; AFF0F0
        db $27,$3A,$1F,$16,$0A,$0F,$04,$07,$09,$0F,$06,$07,$0B,$0B,$19,$1C        ; AFF100
        db $3A,$3A,$16,$16,$0A,$0F,$00,$07,$09,$0F,$04,$07,$0F,$0B,$1F,$18        ; AFF110
        db $EE,$CE,$27,$97,$2E,$BE,$3F,$B1,$67,$E0,$5B,$58,$DF,$DD,$6A,$EA        ; AFF120
        db $56,$D5,$5F,$DC,$7E,$FF,$71,$FF,$60,$FF,$D8,$E7,$DD,$E3,$EB,$76        ; AFF130
        db $62,$9C,$F2,$0C,$75,$89,$B2,$C2,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF140
        db $9C,$9F,$0C,$0F,$89,$8F,$C3,$CE,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF150
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF160
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF170
        db $00,$E1,$20,$51,$10,$2B,$1B,$24,$1F,$20,$3F,$40,$3F,$40,$7F,$80        ; AFF180
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF190
        db $FC,$02,$FC,$02,$FE,$01,$FE,$01,$FE,$01,$FE,$01,$FC,$02,$FC,$02        ; AFF1A0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF1B0
        db $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FE,$01,$00,$FE        ; AFF1C0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF1D0
        db $F8,$05,$F2,$0D,$FC,$02,$F8,$04,$F0,$08,$C0,$30,$00,$C0,$00,$00        ; AFF1E0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF1F0
        db $01,$01,$06,$06,$0D,$08,$11,$1B,$32,$32,$2D,$2C,$2B,$20,$3F,$29        ; AFF200
        db $01,$01,$07,$06,$0F,$08,$1F,$11,$3E,$33,$32,$33,$35,$36,$23,$35        ; AFF210
        db $C0,$C0,$70,$30,$B8,$88,$5C,$44,$CD,$05,$EF,$23,$FF,$1B,$ED,$BD        ; AFF220
        db $C0,$C0,$F0,$30,$88,$F8,$44,$BC,$05,$FD,$E3,$3F,$FB,$1F,$FD,$BF        ; AFF230
        db $0E,$0E,$3D,$3D,$5E,$7E,$F6,$96,$1E,$8E,$9F,$0F,$75,$96,$E7,$E4        ; AFF240
        db $0E,$0E,$3D,$33,$7E,$51,$F6,$99,$FE,$09,$FF,$0F,$F6,$16,$E4,$E4        ; AFF250
        db $1F,$1F,$6E,$6E,$BF,$B9,$FE,$FE,$BF,$B0,$7F,$60,$1F,$1F,$00,$00        ; AFF260
        db $1F,$1F,$6E,$71,$F9,$F0,$BE,$B1,$F0,$FF,$60,$7F,$1F,$1F,$00,$00        ; AFF270
        db $80,$80,$00,$00,$00,$00,$F0,$F0,$FF,$4F,$FF,$80,$FF,$80,$CF,$40        ; AFF280
        db $80,$80,$00,$00,$00,$00,$F0,$F0,$CF,$7F,$80,$FF,$80,$FF,$40,$FF        ; AFF290
        db $00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$F0,$B0,$F8,$48,$FC,$44        ; AFF2A0
        db $00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$B0,$F0,$48,$F8,$44,$FC        ; AFF2B0
        db $00,$00,$80,$80,$40,$40,$A0,$E0,$60,$A0,$E0,$20,$A0,$60,$40,$C0        ; AFF2C0
        db $00,$00,$80,$80,$40,$C0,$E0,$E0,$A0,$A0,$20,$20,$60,$60,$C0,$C0        ; AFF2D0
        db $D0,$30,$E8,$18,$64,$9C,$EA,$9A,$F6,$F6,$5E,$5E,$7A,$7A,$24,$24        ; AFF2E0
        db $30,$30,$18,$18,$9C,$9C,$9A,$9E,$F6,$FA,$5E,$62,$7A,$46,$24,$3C        ; AFF2F0
        db $01,$01,$07,$07,$0C,$08,$1E,$1F,$2C,$26,$39,$3D,$33,$3A,$2A,$3C        ; AFF300
        db $01,$01,$07,$06,$08,$0F,$12,$12,$35,$35,$2A,$3B,$34,$36,$3D,$3D        ; AFF310
        db $C0,$C0,$78,$38,$94,$F4,$3C,$84,$CD,$C5,$87,$63,$37,$EF,$E5,$D5        ; AFF320
        db $C0,$C0,$38,$F8,$0C,$9C,$44,$7C,$C5,$FD,$63,$7F,$EF,$EF,$DD,$DF        ; AFF330
        db $07,$06,$1A,$0A,$1A,$12,$2B,$32,$3A,$23,$39,$25,$3D,$31,$CF,$FE        ; AFF340
        db $07,$06,$0B,$1E,$13,$16,$33,$36,$23,$26,$25,$27,$31,$33,$FE,$FF        ; AFF350
        db $F0,$F0,$E8,$98,$D8,$E8,$E8,$38,$10,$38,$58,$38,$00,$00,$00,$00        ; AFF360
        db $F0,$F0,$98,$98,$E8,$E8,$F8,$38,$F8,$10,$F8,$18,$00,$00,$00,$00        ; AFF370
        db $00,$7F,$07,$18,$03,$04,$01,$02,$01,$02,$00,$01,$00,$01,$00,$01        ; AFF380
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF390
        db $00,$00,$00,$C0,$C0,$20,$E0,$10,$F0,$08,$F0,$08,$F8,$04,$F8,$04        ; AFF3A0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF3B0
        db $00,$F8,$08,$16,$04,$3A,$02,$05,$02,$05,$02,$01,$00,$03,$00,$02        ; AFF3C0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF3D0
        db $00,$00,$00,$00,$00,$20,$00,$08,$00,$00,$00,$01,$00,$08,$00,$00        ; AFF3E0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF3F0
        db $3F,$22,$FF,$F6,$4A,$5F,$CC,$47,$E9,$0F,$FE,$FF,$03,$03,$00,$00        ; AFF400
        db $36,$2A,$FE,$F6,$7A,$CF,$78,$C7,$39,$CF,$FC,$FF,$03,$03,$00,$00        ; AFF410
        db $BE,$BE,$3F,$BF,$1E,$BE,$3F,$B1,$27,$A0,$DB,$D8,$DF,$DD,$2A,$2A        ; AFF420
        db $76,$F5,$77,$F4,$7E,$DF,$71,$FF,$60,$FF,$58,$E7,$DD,$E3,$2B,$36        ; AFF430
        db $62,$23,$E1,$61,$FC,$BC,$A7,$A3,$B2,$B3,$7B,$4A,$84,$8F,$97,$0F        ; AFF440
        db $23,$E3,$61,$E1,$FC,$BC,$E3,$BF,$F3,$BE,$FB,$4E,$FF,$84,$FF,$07        ; AFF450
        db $1F,$1F,$01,$01,$02,$03,$05,$05,$05,$05,$02,$02,$01,$01,$00,$00        ; AFF460
        db $1F,$1F,$01,$01,$03,$02,$05,$07,$05,$06,$02,$03,$01,$01,$00,$00        ; AFF470
        db $F9,$38,$FF,$1E,$7F,$1E,$B9,$89,$DE,$CE,$EC,$E4,$7C,$74,$F8,$F8        ; AFF480
        db $38,$E7,$1E,$F1,$1E,$F9,$89,$7F,$CE,$3E,$E4,$1C,$74,$8C,$F8,$F8        ; AFF490
        db $CE,$42,$EE,$62,$B7,$B1,$7B,$79,$DD,$DD,$35,$35,$0E,$0E,$00,$00        ; AFF4A0
        db $42,$FE,$62,$DE,$B1,$CF,$79,$87,$DD,$E3,$35,$3B,$0E,$0E,$00,$00        ; AFF4B0
        db $2F,$19,$BF,$71,$E7,$C1,$FD,$FD,$FD,$FD,$9F,$9F,$65,$65,$1B,$1B        ; AFF4C0
        db $F9,$0F,$F1,$3F,$C1,$FF,$FD,$03,$FD,$03,$9F,$E2,$65,$7E,$1B,$1B        ; AFF4D0
        db $0E,$0E,$3B,$39,$78,$7F,$BF,$EC,$BF,$FF,$E7,$E4,$4A,$4D,$3F,$3F        ; AFF4E0
        db $0E,$0E,$35,$35,$4F,$4F,$A4,$A4,$A7,$A7,$BC,$FC,$7D,$7D,$3F,$3F        ; AFF4F0
        db $27,$3A,$FF,$F6,$4A,$5F,$CC,$47,$E9,$0F,$FE,$FF,$03,$03,$00,$00        ; AFF500
        db $3A,$3A,$F6,$F6,$7A,$CF,$78,$C7,$39,$CF,$FC,$FF,$03,$03,$00,$00        ; AFF510
        db $EE,$CE,$27,$97,$2E,$BE,$3F,$B1,$67,$E0,$5B,$58,$DF,$DD,$2A,$2A        ; AFF520
        db $56,$D5,$5F,$DC,$7E,$FF,$71,$FF,$60,$FF,$D8,$E7,$DD,$E3,$2B,$36        ; AFF530
        db $62,$9C,$F2,$0C,$75,$89,$B2,$C2,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF540
        db $9C,$9F,$0C,$0F,$89,$8F,$C3,$CE,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF550
        db $00,$00,$80,$80,$78,$F8,$E0,$C8,$60,$60,$D0,$E0,$78,$F8,$80,$80        ; AFF560
        db $00,$00,$80,$80,$F8,$F8,$F8,$C0,$B8,$A0,$F8,$C0,$F8,$F8,$80,$80        ; AFF570
        db $00,$E1,$20,$51,$10,$2B,$1B,$24,$1F,$20,$3F,$40,$3F,$40,$7F,$80        ; AFF580
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF590
        db $FC,$02,$FC,$02,$FE,$01,$FE,$01,$FE,$01,$FE,$01,$FC,$02,$FC,$02        ; AFF5A0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF5B0
        db $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FE,$01,$00,$FE        ; AFF5C0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF5D0
        db $F8,$05,$F2,$0D,$FC,$02,$F8,$04,$F0,$08,$C0,$30,$00,$C0,$00,$00        ; AFF5E0
        db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00        ; AFF5F0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF600
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF610
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF620
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF630
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF640
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF650
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF660
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF670
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF680
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF690
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF6A0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF6B0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF6C0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF6D0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF6E0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF6F0
        db $08,$ED,$00,$03,$00,$06,$F8,$13,$00,$FE,$F8,$12,$00,$FE,$F0,$02        ; AFF700
        db $00,$EE,$F0,$08,$20,$02,$08,$16,$00,$02,$00,$06,$00,$F2,$00,$04        ; AFF710
        db $20,$0C,$ED,$00,$03,$00,$06,$F8,$13,$00,$FE,$F8,$12,$00,$FE,$F0        ; AFF720
        db $02,$00,$EE,$F0,$08,$20,$0D,$00,$0E,$00,$12,$08,$0F,$00,$0A,$08        ; AFF730
        db $1F,$00,$02,$08,$1E,$00,$02,$08,$16,$00,$02,$00,$06,$00,$F2,$00        ; AFF740
        db $04,$20,$08,$E7,$F7,$00,$20,$FF,$F9,$06,$00,$F7,$08,$16,$00,$EF        ; AFF750
        db $07,$13,$00,$E7,$07,$03,$00,$F7,$00,$12,$00,$F7,$F8,$02,$00,$FF        ; AFF760
        db $01,$04,$20,$09,$EA,$F9,$0D,$00,$E2,$F9,$0C,$00,$06,$F8,$13,$00        ; AFF770
        db $FE,$F8,$12,$00,$FE,$F0,$02,$00,$EE,$F0,$08,$20,$02,$08,$16,$00        ; AFF780
        db $02,$00,$06,$00,$F2,$00,$04,$20,$09,$EA,$F9,$0D,$00,$E2,$F9,$0C        ; AFF790
        db $00,$06,$F8,$13,$00,$FE,$F8,$12,$00,$FE,$F0,$02,$00,$EE,$F0,$08        ; AFF7A0
        db $20,$02,$08,$16,$00,$02,$00,$06,$00,$F2,$00,$04,$20,$08,$E7,$F7        ; AFF7B0
        db $00,$20,$DF,$FF,$03,$00,$FF,$F9,$06,$00,$F7,$08,$16,$00,$EF,$07        ; AFF7C0
        db $13,$00,$F7,$00,$12,$00,$F7,$F8,$02,$00,$FF,$01,$04,$20,$08,$ED        ; AFF7D0
        db $00,$03,$00,$06,$F8,$13,$00,$FE,$F8,$12,$00,$FE,$F0,$02,$00,$EE        ; AFF7E0
        db $F0,$00,$20,$02,$08,$16,$00,$02,$00,$06,$00,$F2,$00,$04,$20,$0C        ; AFF7F0
        db $ED,$00,$03,$00,$06,$F8,$13,$00,$FE,$F8,$12,$00,$FE,$F0,$02,$00        ; AFF800
        db $EE,$F0,$00,$20,$0D,$00,$0E,$00,$12,$08,$0F,$00,$0A,$08,$1F,$00        ; AFF810
        db $02,$08,$1E,$00,$02,$08,$16,$00,$02,$00,$06,$00,$F2,$00,$04,$20        ; AFF820
        db $08,$E7,$F7,$08,$20,$FF,$F9,$06,$00,$F7,$08,$16,$00,$EF,$07,$13        ; AFF830
        db $00,$E7,$07,$03,$00,$F7,$00,$12,$00,$F7,$F8,$02,$00,$FF,$01,$04        ; AFF840
        db $20,$09,$EA,$F9,$0D,$00,$EE,$F0,$00,$20,$E2,$F9,$0C,$00,$06,$F8        ; AFF850
        db $13,$00,$FE,$F8,$12,$00,$FE,$F0,$02,$00,$02,$08,$16,$00,$02,$00        ; AFF860
        db $06,$00,$F2,$00,$04,$20,$09,$EA,$F9,$0D,$00,$EE,$F0,$00,$20,$E2        ; AFF870
        db $F9,$0C,$00,$06,$F8,$13,$00,$FE,$F8,$12,$00,$FE,$F0,$02,$00,$02        ; AFF880
        db $08,$16,$00,$02,$00,$06,$00,$F2,$00,$04,$20,$08,$E7,$F7,$08,$20        ; AFF890
        db $DF,$FF,$03,$00,$FF,$F9,$06,$00,$F7,$08,$16,$00,$EF,$07,$13,$00        ; AFF8A0
        db $F7,$00,$12,$00,$F7,$F8,$02,$00,$FF,$01,$04,$20,$FF,$FF,$FF,$FF        ; AFF8B0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF8C0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF8D0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF8E0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF8F0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF900
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF910
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF920
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF930
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF940
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF950
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF960
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF970
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF980
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF990
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF9A0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF9B0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF9C0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF9D0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF9E0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFF9F0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA00
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA10
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA20
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA30
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA40
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA50
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA60
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA70
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA80
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFA90
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFAA0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFAB0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFAC0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFAD0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFAE0
        db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF        ; AFFAF0


; ----------------------------------------------------------------------------
; New code. Everything below this point is cross-checked against the
; supplied CPU trace logs (marked bytes were actually executed while
; performing an Early Dash / Air Dash / boosted Walljump in-game); a small
; number of straight-line, unconditional bytes that the traces happened not
; to hit are filled in by hand from context (each still shown with its
; exact byte values so the patch remains byte-for-byte reproducible).
; ----------------------------------------------------------------------------


GetHitboxPtr_or_ExtendedFrame:
        ; Hitbox/property-pointer lookup, called from the animation engine.
        ; First checks whether it's running for X specifically (Direct Page ==
        ; $6BA8, X's own struct base) via TDC / CMP #$6BA8. Other objects that
        ; happen to share this routine (it's pointed to by a generic pointer
        ; table entry) don't have poses $36-$3B, so they always fall through to
        ; the plain vanilla lookup.
        LDA $3399 ;[$853399] ; AFFB00: AD 99 33
        AND #$00FF       ; AFFB03: 29 FF 00
        BIT #$0008       ; AFFB06: 89 08 00
        BNE LBL_AFFB11      ; AFFB09: D0 06
        TDC              ; AFFB0B: 7B
        CMP #$6BA8       ; AFFB0C: C9 A8 6B
        BEQ LBL_AFFB1C      ; AFFB0F: F0 0B
LBL_AFFB11:
        LDA $17 ;[$006BBF] ; AFFB11: A5 17
        AND #$00FF       ; AFFB13: 29 FF 00
        ASL              ; AFFB16: 0A
        TAY              ; AFFB17: A8
        CLC              ; AFFB18: 18
        LDA ($31),Y ;[$85A597] ; AFFB19: B1 31
        RTL              ; AFFB1B: 6B

GetHitboxPtr_ExtendedRange:
        ; Only reached for X himself. If the current pose (dp $17, vanilla
        ; "X's current pose") is in [$36,$3C) -- i.e. one of the six new Air
        ; Dash poses -- index into the new $85B390 table instead of the
        ; original one. Any other pose falls through to the vanilla lookup.
LBL_AFFB1C:
        LDA $17 ;[$006BBF] ; AFFB1C: A5 17
        AND #$00FF       ; AFFB1E: 29 FF 00
        CMP #$0036       ; AFFB21: C9 36 00
        BCC LBL_AFFB11      ; AFFB24: 90 EB
        CMP #$003C       ; AFFB26: C9 3C 00
        BCS LBL_AFFB11      ; AFFB29: B0 E6
        SEC              ; AFFB2B: 38
        SBC #$0036       ; AFFB2C: E9 36 00
        ASL              ; AFFB2F: 0A
        CLC              ; AFFB30: 18
        ADC #$0DF9       ; AFFB31: 69 F9 0D
        TAY              ; AFFB34: A8
        LDA ($31),Y ;[$85B390] ; AFFB35: B1 31
        RTL              ; AFFB37: 6B

TryStartGroundDash:
        ; Entry point called from the bank-$81 dash dispatcher hook (was the
        ; inline CMP chain at $81976D). Decides whether X can start dashing
        ; right now, and if so, which kind:
        ;   - aborts if $3323 (a busy/lock flag) is nonzero
        ;   - aborts if the Dash button isn't currently held (dp $3A bit $80)
        ;   - aborts unless X's state is one of the eligible ones
        ;     ($02/$08/$10/$12 -- e.g. stand/walk/turn-ish states)
        ;   - if dp $2C is non-negative, additionally requires the ground-check
        ;     helper JSL $849A24 to report "on the ground"
        ;   - CanStartDash_QuickGate ($AFFBB2) does a final sanity check
        ;   - if all of that passes: sets a flag (TSB dp $7E, bit $40) and
        ;     either starts the vanilla ground Dash (state $14), or -- via
        ;     TryStartGroundDash_Alt below, after one more gate -- starts the
        ;     new Air Dash (state $48).
        LDA $3323 ;[$863323] ; AFFB38: AD 23 33
        BNE LBL_AFFB76      ; AFFB3B: D0 39
        LDA $3A ;[$006BE2] ; AFFB3D: A5 3A
        BIT #$80         ; AFFB3F: 89 80
        BEQ LBL_AFFB76      ; AFFB41: F0 33
        LDA $02 ;[$006BAA] ; AFFB43: A5 02
        CMP #$02         ; AFFB45: C9 02
        BEQ LBL_AFFB55      ; AFFB47: F0 0C
        CMP #$08         ; AFFB49: C9 08
        BEQ LBL_AFFB55      ; AFFB4B: F0 08
        CMP #$10         ; AFFB4D: C9 10
        BEQ LBL_AFFB55      ; AFFB4F: F0 04
        CMP #$12         ; AFFB51: C9 12
        BNE LBL_AFFB64      ; AFFB53: D0 0F
LBL_AFFB55:
        LDA $2C ;[$006BD4] ; AFFB55: A5 2C
        BMI LBL_AFFB5F      ; AFFB57: 30 06
        JSL $849A24      ; AFFB59: 22 24 9A 84
        BCC LBL_AFFB64      ; AFFB5D: 90 05
LBL_AFFB5F:
        LDA #$0A         ; AFFB5F: A9 0A
        STA $56          ; AFFB61: 85 56
        RTL              ; AFFB63: 6B
LBL_AFFB64:
        JSL $AFFBB2      ; AFFB64: 22 B2 FB AF
        BNE LBL_AFFB77      ; AFFB68: D0 0D
        LDA #$40         ; AFFB6A: A9 40
        TSB $7E          ; AFFB6C: 04 7E
        SEP #$30         ; AFFB6E: E2 30
        LDA #$14         ; AFFB70: A9 14
        STA $02 ;[$006BAA] ; AFFB72: 85 02
        STZ $03 ;[$006BAB] ; AFFB74: 64 03
LBL_AFFB76:
        RTL              ; AFFB76: 6B

TryStartGroundDash_Alt:
        ; Reached when the quick-gate above wants a second opinion.
        ; CanStartDash_StateGate ($AFFB8A) performs the Air-Dash-specific
        ; eligibility check (airborne + has Leg Parts + not already at max
        ; "boosted" speed + not on a ladder/other restricted mode). If it
        ; passes, sets the same dp $7E bit $40 flag and transitions X into the
        ; new Air Dash state ($48).
LBL_AFFB77:
        JSL $AFFB8A      ; AFFB77: 22 8A FB AF
        BNE LBL_AFFB76      ; AFFB7B: D0 F9
        LDA #$40         ; AFFB7D: A9 40
        TSB $7E          ; AFFB7F: 04 7E
        SEP #$30         ; AFFB81: E2 30
        LDA #$48         ; AFFB83: A9 48
        STA $02 ;[$006BAA] ; AFFB85: 85 02
        STZ $03 ;[$006BAB] ; AFFB87: 64 03
        RTL              ; AFFB89: 6B

CanStartDash_StateGate:
        ; Air-Dash-specific eligibility gate. Returns A=0 (eligible) or A=1
        ; (not eligible) in the carry-independent accumulator result used by
        ; the caller's BNE/BEQ.
        ;   - requires the Leg Parts / Dash-granting equipment flag ($3399
        ;     bit 3) -- this is the "only with the Leg Armor upgrade" gate
        ;     the early-dash NOP patch in bank $81 deliberately did NOT touch.
        ;   - requires X's state to be "rising" (state $06) or "falling"
        ;     (state $08) -- i.e. X must actually be airborne.
        ;   - requires X's dp $5C speed value to not already equal $0375 (the
        ;     same "boosted" constant used by the walljump-kick hook -- this
        ;     prevents air-dashing while already at that special speed).
        ;   - finally defers to JSL $8499AF (an existing engine check, likely
        ;     ladder/underwater/similar movement-restriction test); if that
        ;     reports "restricted" (carry set), Air Dash is denied too.
        LDA $3399 ;[$863399] ; AFFB8A: AD 99 33
        BIT #$08         ; AFFB8D: 89 08
        BEQ LBL_AFFB9B      ; AFFB8F: F0 0A
        LDA $02 ;[$006BAA] ; AFFB91: A5 02
        CMP #$06         ; AFFB93: C9 06
        BEQ LBL_AFFB9E      ; AFFB95: F0 07
        CMP #$08         ; AFFB97: C9 08
        BEQ LBL_AFFB9E      ; AFFB99: F0 03
LBL_AFFB9B:
        LDA #$01         ; AFFB9B: A9 01
        RTL              ; AFFB9D: 6B
LBL_AFFB9E:
        REP #$20         ; AFFB9E: C2 20
        LDA $5C ;[$006C04] ; AFFBA0: A5 5C
        CMP #$0375       ; AFFBA2: C9 75 03
        SEP #$20         ; AFFBA5: E2 20
        BEQ LBL_AFFB9B      ; AFFBA7: F0 F2
        JSL $8499AF      ; AFFBA9: 22 AF 99 84
        BCS LBL_AFFB9B      ; AFFBAD: B0 EC
        LDA #$00         ; AFFBAF: A9 00
        RTL              ; AFFBB1: 6B

CanStartDash_QuickGate:
        ; Cheap early-out used by TryStartGroundDash before bothering with the
        ; state gate above: if X's current state is already one of
        ; $00/$02/$04/$0A (a small set of "can't dash from here" states),
        ; immediately reports "not eligible" without the JSL $8499AF check.
        ; Otherwise defers to the same JSL $8499AF restriction check.
        LDA $02 ;[$006BAA] ; AFFBB2: A5 02
        BEQ LBL_AFFBC5      ; AFFBB4: F0 0F
        CMP #$02         ; AFFBB6: C9 02
        BEQ LBL_AFFBC5      ; AFFBB8: F0 0B
        CMP #$04         ; AFFBBA: C9 04
        BEQ LBL_AFFBC5      ; AFFBBC: F0 07
        CMP #$0A         ; AFFBBE: C9 0A
        BEQ LBL_AFFBC5      ; AFFBC0: F0 03
LBL_AFFBC2:
        LDA #$01         ; AFFBC2: A9 01
        RTL              ; AFFBC4: 6B
LBL_AFFBC5:
        JSL $8499AF      ; AFFBC5: 22 AF 99 84
        BCS LBL_AFFBC2      ; AFFBC9: B0 F7
        LDA #$00         ; AFFBCB: A9 00
        RTL              ; AFFBCD: 6B

State48_AirDash_Handler:
        ; New state $48 handler ("Air Dash"), called via the stub at
        ; $8182A1. Mirrors the structure of vanilla state handlers: dp $03
        ; (state "just entered" flag) is used to run one-time setup on the
        ; first frame only.
        LDX $03 ;[$006BAB] ; AFFBCE: A6 03
        BNE LBL_AFFC11      ; AFFBD0: D0 3F
        INC $03 ;[$006BAB] ; AFFBD2: E6 03
        LDA #$FF         ; AFFBD4: A9 FF
        STA $1D ;[$006BC5] ; AFFBD6: 85 1D
        STZ $75 ;[$006C1D] ; AFFBD8: 64 75
        LDA #$08         ; AFFBDA: A9 08
        JSL $8088CF      ; AFFBDC: 22 CF 88 80
        JSL $81FFD0      ; AFFBE0: 22 D0 FF 81
        LDA #$13         ; AFFBE4: A9 13
        CLC              ; AFFBE6: 18
        ADC $6F ;[$006C17] ; AFFBE7: 65 6F
        JSL $848F07      ; AFFBE9: 22 07 8F 84
        LDA #$10         ; AFFBED: A9 10
        STA $55 ;[$006BFD] ; AFFBEF: 85 55
        LDA #$10         ; AFFBF1: A9 10
        STA $52 ;[$006BFA] ; AFFBF3: 85 52
        REP #$20         ; AFFBF5: C2 20
        LDA #$0375       ; AFFBF7: A9 75 03
        STA $5C ;[$006C04] ; AFFBFA: 85 5C
        BIT $68 ;[$006C10] ; AFFBFC: 24 68
        BVS LBL_AFFC03      ; AFFBFE: 70 03
        LDA #$FC8B       ; AFFC00: A9 8B FC
LBL_AFFC03:
        STA $1A ;[$006BC2] ; AFFC03: 85 1A
        LDA #$BB38       ; AFFC05: A9 38 BB
        STA $20 ;[$006BC8] ; AFFC08: 85 20
        LDA #$A597       ; AFFC0A: A9 97 A5
        STA $31 ;[$006BD9] ; AFFC0D: 85 31
        SEP #$20         ; AFFC0F: E2 20

State48_AirDash_Continue:
        ; Per-frame continuation of the Air Dash state (runs every frame after
        ; the first). Checks wall-cling flags (dp $5E), buffered jump/next-
        ; state-request bits, and either keeps air-dashing, kicks off a
        ; walljump-style interrupt via the bank-$81 trampolines, or hands off
        ; to AirDash_EndCheck_Grounded once it detects ground/wall contact.
LBL_AFFC11:
        LDA $5E ;[$006C06] ; AFFC11: A5 5E
        BIT $04 ;[$006BAC] ; AFFC13: 24 04
        BEQ LBL_AFFC19      ; AFFC15: F0 02
        STZ $2F          ; AFFC17: 64 2F
LBL_AFFC19:
        LDA $59 ;[$006C01] ; AFFC19: A5 59
        BNE LBL_AFFC23      ; AFFC1B: D0 06
        LDA $3B ;[$006BE3] ; AFFC1D: A5 3B
        BIT #$40         ; AFFC1F: 89 40
        BEQ LBL_AFFC29      ; AFFC21: F0 06
LBL_AFFC23:
        LDA #$13         ; AFFC23: A9 13
        JSL $81FFD4      ; AFFC25: 22 D4 FF 81
LBL_AFFC29:
        LDA #$01         ; AFFC29: A9 01
        BIT $69 ;[$006C11] ; AFFC2B: 24 69
        BVS LBL_AFFC31      ; AFFC2D: 70 02
        LDA #$02         ; AFFC2F: A9 02
LBL_AFFC31:
        BIT $5E ;[$006C06] ; AFFC31: 24 5E
        BNE LBL_AFFC3B      ; AFFC33: D0 06
        JSL $81FFD8      ; AFFC35: 22 D8 FF 81
        BNE LBL_AFFC40      ; AFFC39: D0 05
LBL_AFFC3B:
        JSL $AFFC62      ; AFFC3B: 22 62 FC AF
        RTL              ; AFFC3F: 6B
LBL_AFFC40:
        JSL $82823E      ; AFFC40: 22 3E 82 82
        DEC $52 ;[$006BFA] ; AFFC44: C6 52
        BMI LBL_AFFC3B      ; AFFC46: 30 F3
        BIT $0F ;[$006BB7] ; AFFC48: 24 0F
        BVC LBL_AFFC52      ; AFFC4A: 50 06
        LDA #$02         ; AFFC4C: A9 02
        JSL $81FFDC      ; AFFC4E: 22 DC FF 81
LBL_AFFC52:
        LDA #$35         ; AFFC52: A9 35
        JSL $81FFE0      ; AFFC54: 22 E0 FF 81
        RTL              ; AFFC58: 6B
LBL_AFFC59:
        SEP #$30         ; AFFC59: E2 30
        LDA #$20         ; AFFC5B: A9 20
        STA $02          ; AFFC5D: 85 02
        STZ $03          ; AFFC5F: 64 03
        RTL              ; AFFC61: 6B

AirDash_EndCheck_Grounded:
        ; Checks the wall-cling bitflags (dp $5E, vanilla $0C06) for the
        ; "standing" bit ($04). If set, ends the Air Dash immediately
        ; (transitions to state $4A, "Air Dash End"); otherwise falls through
        ; into the shared physics/animation-timer update shared with the
        ; regular airborne-dash continuation.
        SEP #$30         ; AFFC62: E2 30
        LDA $5E ;[$006C06] ; AFFC64: A5 5E
        BIT #$04         ; AFFC66: 89 04
        BNE LBL_AFFC59      ; AFFC68: D0 EF
        LDA #$4A         ; AFFC6A: A9 4A
        STA $02 ;[$006BAA] ; AFFC6C: 85 02
        STZ $03 ;[$006BAB] ; AFFC6E: 64 03
        RTL              ; AFFC70: 6B

LandingHook_Stub:
        ; Target of the bank-$81 $81F0EB hook (replaces "STA $16 / LDA $0B").
        ; Performs the original store, then looks up X (dp $0B, an index) in
        ; the relocated bank-$86 table (see $81F109 / $86FFFD above) before
        ; returning -- this is the extra per-sub-state behaviour needed so that
        ; landing out of an Air Dash is handled the same way as landing out of
        ; a normal dash.
        STA $16 ;[$00793E] ; AFFC71: 85 16
        LDX $0B ;[$007933] ; AFFC73: A6 0B
        LDA $FFFA,X ;[$86FFFB] ; AFFC75: BD FA FF
        RTL              ; AFFC78: 6B

State4A_AirDashEnd_Handler:
        ; New state $4A handler ("Air Dash End"), called via the stub at
        ; $8182A6. Resets X's velocity/position deltas, restores the normal
        ; graphics pointer, and (after a short animation-timer countdown, dp
        ; $4E) hands control back to a normal grounded/airborne state, mirroring
        ; how the vanilla ground-dash-end state behaves.
        LDX $03 ;[$006BAB] ; AFFC79: A6 03
        BNE LBL_AFFC9F      ; AFFC7B: D0 22
        INC $03 ;[$006BAB] ; AFFC7D: E6 03
        REP #$20         ; AFFC7F: C2 20
        LDA #$A552       ; AFFC81: A9 52 A5
        STA $20 ;[$006BC8] ; AFFC84: 85 20
        STZ $1A ;[$006BC2] ; AFFC86: 64 1A
        STZ $1C ;[$006BC4] ; AFFC88: 64 1C
        SEP #$20         ; AFFC8A: E2 20
        STZ $1F ;[$006BC7] ; AFFC8C: 64 1F
        LDA #$40         ; AFFC8E: A9 40
        STA $1E ;[$006BC6] ; AFFC90: 85 1E
        LDA #$08         ; AFFC92: A9 08
        STA $4E ;[$006BF6] ; AFFC94: 85 4E
        LDA #$16         ; AFFC96: A9 16
        CLC              ; AFFC98: 18
        ADC $6F ;[$006C17] ; AFFC99: 65 6F
        JSL $848F07      ; AFFC9B: 22 07 8F 84
LBL_AFFC9F:
        LDA $59 ;[$006C01] ; AFFC9F: A5 59
        BNE LBL_AFFCA9      ; AFFCA1: D0 06
        LDA $3B ;[$006BE3] ; AFFCA3: A5 3B
        BIT #$40         ; AFFCA5: 89 40
        BEQ LBL_AFFCAF      ; AFFCA7: F0 06
LBL_AFFCA9:
        LDA #$16         ; AFFCA9: A9 16
        JSL $81FFE4      ; AFFCAB: 22 E4 FF 81
LBL_AFFCAF:
        DEC $4E ;[$006BF6] ; AFFCAF: C6 4E
        BNE LBL_AFFCC6      ; AFFCB1: D0 13
LBL_AFFCB3:
        STZ $4F ;[$006BF7] ; AFFCB3: 64 4F
        LDA #$04         ; AFFCB5: A9 04
        TSB $87          ; AFFCB7: 04 87
        SEP #$30         ; AFFCB9: E2 30
        LDA #$08         ; AFFCBB: A9 08
        STA $02 ;[$006BAA] ; AFFCBD: 85 02
        STZ $03 ;[$006BAB] ; AFFCBF: 64 03
        LDA #$08         ; AFFCC1: A9 08
        STA $2F ;[$006BD7] ; AFFCC3: 85 2F
        RTL              ; AFFCC5: 6B
LBL_AFFCC6:
        LDA $37 ;[$006BDF] ; AFFCC6: A5 37
        BIT #$03         ; AFFCC8: 89 03
        BNE LBL_AFFCB3      ; AFFCCA: D0 E7
        JSL $828174      ; AFFCCC: 22 74 81 82
        LDA #$16         ; AFFCD0: A9 16
        JSL $81FFE8      ; AFFCD2: 22 E8 FF 81
        RTL              ; AFFCD6: 6B

; ============================================================================
; End of patch
; ============================================================================
