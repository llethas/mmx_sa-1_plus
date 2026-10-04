; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Extra Options" Patch
;  Apply after: SA-1, Better Walljump, Faster Dialog Box, Skip Boss Intro
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off extra_options_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Adds a 4th item to the title-screen main menu, below OPTION MODE:
;
;          GAME  START / PASS WORD / OPTION MODE / EXTRA OPTIONS
;
;    EXTRA OPTIONS opens its own screen (Mega Man X1 menu style: same font,
;    palette, fade and colours as OPTION MODE) with four toggles and EXIT:
;
;          D-TAP DASH      OFF (default)  Double-tap-to-dash detector
;          EARLY DASH      ON  (default)  ON : Dash is usable from the start
;                                         OFF: Dash needs the Leg Armor
;                                              (vanilla)
;          AIRDASH         ON  (default)  ON : With the Leg Armor, a Dash
;                                              button press (or double-tap,
;                                              if D-TAP DASH is on) in
;                                              mid-air Air Dashes
;                                         OFF: no mid-air dash (vanilla)
;          BETTER SUB-TANK ON  (default)  ON : Sub-Tanks behave as in the
;                                              SA-1 patch: they heal 2 per
;                                              tick and stop depleting once
;                                              health is full
;                                         OFF: vanilla Sub-Tank behaviour
;          EXIT                           Saves the toggles to SRAM and
;                                         returns straight to the main menu
;                                         (it does NOT replay the intro like
;                                         OPTION MODE does)
;
;    LEFT/RIGHT toggles the highlighted option; UP/DOWN moves the cursor;
;    START / Y / A on EXIT leaves the screen (same keys as OPTION MODE's EXIT).
;
;  AIR DASH / EARLY DASH BASE FEATURES
;    - Dash available from the start (switchable: EARLY DASH)
;    - Leg Capsule gives Air Dash, like Mega Man X2 (switchable: AIRDASH)
;    The Air Dash code is reproduced below unchanged except for three tiny
;    hooks (marked "EXTRA OPTIONS HOOK") that consult the toggles.
;
;  STORAGE (battery-backed SA-1 BW-RAM, bank $40)
;    Working copy (what gameplay and the menu read; both CPUs can see it):
;        $40:FF10  D-TAP DASH       0 = OFF, 1 = ON
;        $40:FF11  EARLY DASH       0 = OFF, 1 = ON
;        $40:FF12  AIRDASH          0 = OFF, 1 = ON
;        $40:FF13  BETTER SUB-TANK  0 = OFF, 1 = ON
;    Saved copy (written ONLY when the player presses EXIT):
;        $40:FF00  'M'      signature
;        $40:FF01  'X'      signature
;        $40:FF02  D-TAP DASH
;        $40:FF03  EARLY DASH
;        $40:FF04  AIRDASH
;        $40:FF05  checksum = (FF02 + FF03 + FF04 + $A5) & $FF
;        $40:FF06  BETTER SUB-TANK
;        $40:FF07  complement of FF06 (FF06 XOR FF07 must be $FF)
;    BETTER SUB-TANK was added after the first three toggles, so it is stored
;    with its own validity check instead of being folded into the checksum:
;    a save made before it existed (valid FF00-FF05, nothing at FF06-FF07)
;    still loads, with BETTER SUB-TANK ON.
;    On every reset the saved copy is loaded into the working copy. If the
;    signature/checksum is not valid (fresh cartridge), defaults are used:
;    D-TAP OFF, EARLY DASH ON, AIRDASH ON, BETTER SUB-TANK ON. Toggling
;    without pressing EXIT and then resetting therefore discards the change.
;    Nothing else in the SA-1 port uses $40:FF00-FF1F (the control scheme /
;    password SRAM lives at $40:0100).
;
;  FREE SPACE USED
;    Bank $80 $80FEB8+   JSL trampolines for the bank-$80 menu helpers
;    Bank $86 $86FB80+   new message strings, cursor-Y table
;    Bank $AF $AFE990+   new code (menu screen, dispatcher, SRAM, gates,
;                        Sub-Tank hooks)
;    Bank $AF $AFEC80+   Early Dash (no Leg Armor) dash art, 5 x $200 bytes
;    Bank $AF $AFF8C0+   Early Dash (no Leg Armor) dash art, 6th block
;    Bank $AF $AFF700+   Air Dash data/code
;    Bank $AF $AFFB00+   Early Dash pose lookup
;    Bank $84 $848FF6    pose-lookup hook
;    Bank $85 $85B390+   Early Dash pose table + tile-DMA records
;
;  HOOKS INTO EXISTING CODE (besides the Air Dash ones below)
;    $80FDF9  boot: load saved toggles                      -> BootLoad
;    $80930D  main menu selection dispatcher                -> MenuDispatch
;    $80925D  main menu initial draw message id $10 -> $44
;    $809295  main menu cursor redraw message base $10 -> $44
;    $809278  cursor UP wrap  2 -> 3 ; $809283 DOWN wrap 3 -> 4
;    $80928C  cursor sprite-Y table                         -> MenuCursorY
;    $809237  initial cursor sprite Y $A6 -> $96
;    $80C752  Sub-Tank heal-per-tick                        -> SubTank_SetRate
;    $80C7B8  Sub-Tank "stop at full health" check          -> SubTank_FullCheck
;    $81FF60  SA-1 double-tap gate                          -> NewGateCheck
;    $86910B  message-pointer table ids $44-$5B             -> new messages
; ============================================================================

lorom

; ############################################################################
; # PART 1 - BANK $81 -- X's object code (the actual gameplay logic)
; ############################################################################

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
        db $71, $FF                                                           ; 81829F

NewState_48_AirDash:
        JSL $AFFBCE               ; 8182A1: 22 CE FB AF
        RTS                       ; 8182A5: 60
        ; state $48 = "Air Dash": long-calls into the new Air Dash
        ; state handler and returns.

NewState_4A_AirDashEnd:
        JSL $AFFC79               ; 8182A6: 22 79 FC AF
        RTS                       ; 8182AA: 60
        ; state $4A = "Air Dash End": long-calls into the new Air Dash
        ; end-of-dash handler and returns.

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
        ; was, in vanilla, LDA $3399 / BIT #$08 / BEQ $8196CA = "needs Leg Armor".
        ; Now: ask the EARLY DASH toggle. EarlyDash_Gate returns Z=1 when
        ; dashing is NOT allowed (EARLY DASH off AND no Leg Armor).
        JSL EarlyDash_Gate        ; 819712: 22 xx xx AF
        BEQ DashInput_Skip        ; 819716: F0 B1  (-> $8196CA, the RTS)
        NOP                       ; 819718: EA

DashInput_Skip = $8196CA

; ----------------------------------------------------------------------------
; Dash-type dispatcher hook: the vanilla inline chain of CMP/BEQ checks
; against X's dash sub-state is replaced with a JSL into new bank $AF logic
; (TryStartGroundDash) that layers in the new Air Dash eligibility checks
; on top of the original behaviour.
; ----------------------------------------------------------------------------

org $81976D
        db $22, $B2, $FB, $AF, $60                                            ; 81976D

org $819789
        JSL $AFFB38               ; 819789: 22 38 FB AF
        RTS                       ; 81978D: 60

; ----------------------------------------------------------------------------
; Landing / state-continue hook: replaces "STA $16 / LDA $0B" with a JSL that
; performs the same store, plus extra work, before falling through to the
; original JMP $848F07 (the state-change dispatcher -- called directly
; whenever code wants to jump straight into a new state's handler instead of
; waiting for next frame).
; ----------------------------------------------------------------------------

org $81F0EB
        JSL $AFFC71               ; 81F0EB: 22 71 FC AF
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
        db $FD, $FF                                                           ; 81F109
        ; (operand of "CMP $xxxx,X" at $81F108, now $FFFD instead of
        ; $DC64 -- see bank $86 section below for the relocated table)

; ----------------------------------------------------------------------------
; Relocated dispatch table (see the bank-$81 section above): now lives at
; $81FF71 with two extra entries appended ($8182A1 and $8182A6, the new Air
; Dash / Air Dash End stubs). All other entries are byte-identical to the
; original table that used to sit at $8182A1.
; ----------------------------------------------------------------------------

org $81FF71
        db $E9, $82, $98, $83, $03, $84, $81, $84                             ; 81FF71
        db $1D, $85, $F6, $85, $45, $8A, $51, $86                             ; 81FF79
        db $0E, $87, $34, $88, $04, $89, $31, $8B                             ; 81FF81
        db $43, $8B, $A7, $8B, $44, $8B, $4D, $8B                             ; 81FF89
        db $A0, $89, $F0, $89, $29, $8D, $69, $8D                             ; 81FF91
        db $AB, $8D, $E1, $8D, $75, $8E, $86, $8E                             ; 81FF99
        db $41, $8F, $7C, $91, $DD, $91, $3F, $92                             ; 81FFA1
        db $E9, $92, $0E, $93, $29, $8F, $4E, $8F                             ; 81FFA9
        db $B4, $8F, $0D, $90, $51, $90, $4D, $8B                             ; 81FFB1
        db $A1, $82, $A6, $82                                                 ; 81FFB9

; ----------------------------------------------------------------------------
; JSL-callable trampolines: five short "JSR <existing bank-$81 routine>;
; RTL" stubs. These let the new far-called ($JSL) code in bank $AF invoke
; pre-existing bank-$81 helper subroutines that only end in RTS (i.e. were
; never designed to be called from outside bank $81) as if they were long
; subroutines. Two of the five entries call the very same helper
; ($8193A8, likely an animation/frame-advance helper).
; ----------------------------------------------------------------------------

org $81FFD0
        JSR $9588  ; 81FFD0: 20 88 95  [$819588]
        RTL                       ; 81FFD3: 6B
        db $20, $A8, $93, $6B                                                 ; 81FFD4
        JSR $9D1A  ; 81FFD8: 20 1A 9D  [$819D1A]
        RTL                       ; 81FFDB: 6B
        JSR $9C66  ; 81FFDC: 20 66 9C  [$819C66]
        RTL                       ; 81FFDF: 6B
        JSR $9536  ; 81FFE0: 20 36 95  [$819536]
        RTL                       ; 81FFE3: 6B
        db $20, $A8, $93, $6B                                                 ; 81FFE4
        JSR $9560  ; 81FFE8: 20 60 95  [$819560]
        RTL                       ; 81FFEB: 6B

; ############################################################################
; # PART 2 - BANK $86 -- relocated per-sub-state lookup table
; ############################################################################
; Small per-sub-state lookup table, relocated (see bank $81 / $81F109 above)
; to $86FFFD.

org $86FFFA
        db $00, $01, $01, $0E, $14, $48                                       ; 86FFFA

; ############################################################################
; # PART 3 - BANK $8D -- sprite/OAM frame pointer tables
; ############################################################################
; Two existing pointer-table regions have some of their entries repointed
; at the new Air Dash animation-frame data that now lives in bank $AF
; (see the big data block in the bank-$AF section below).
; ============================================================================

org $8D82B2
        db $00, $F7, $AF, $21, $F7, $AF, $52, $F7                             ; 8D82B2
        db $AF, $73, $F7, $AF, $98, $F7, $AF, $BD                             ; 8D82BA
        db $F7, $AF                                                           ; 8D82C2
        ; 6 x 24-bit pointers: $AFF700, $AFF721, $AFF752, $AFF773,
        ; $AFF798, $AFF7BD -- all point into the new Air Dash frame
        ; data added in bank $AF.

org $8D8891
        db $DE, $F7, $AF, $FF, $F7, $AF, $30, $F8                             ; 8D8891
        db $AF, $51, $F8, $AF, $76, $F8, $AF, $9B                             ; 8D8899
        db $F8, $AF                                                           ; 8D88A1
        ; 6 more 24-bit pointers into the same new bank-$AF frame data:
        ; $AFF7DE, $AFF7FF, $AFF830, $AFF851, $AFF876, $AFF89B.

; ############################################################################
; # PART 4 - BANK $8F -- new OAM/hitbox record fragments (pure data)
; ############################################################################
; Small edits to existing per-pose sprite/hitbox records (tile offsets +
; attribute bytes). Not hand-decoded field by field -- shown here as raw data
; for byte-exact reproduction.
; ============================================================================

org $8FFE39
        db $03, $02, $08, $16                                                 ; 8FFE39

org $8FFE3E
        db $02, $00, $06                                                      ; 8FFE3E

org $8FFE42
        db $F2, $00, $04, $20                                                 ; 8FFE42

org $8FFE56
        db $02, $F7, $08, $16                                                 ; 8FFE56

org $8FFE5B
        db $FF, $01, $04, $20                                                 ; 8FFE5B

org $8FFE73
        db $03, $F7, $08, $16                                                 ; 8FFE73

org $8FFE78
        db $EF, $07, $13                                                      ; 8FFE78

org $8FFE7C
        db $FF, $01, $04, $20                                                 ; 8FFE7C

; ############################################################################
; # PART 5 - BANK $AF -- new free-space data + code
; ############################################################################
; This entire bank was unused ($FF-filled) space in the SA-1-patched ROM.
; The patch turns it into a combined data+code area:
;   $AFF700-$AFF8B7  new animation-frame / hitbox / OAM data for the six
;                     new Air Dash poses ($36-$3B) -- pure data.
;   $AFFB38-$AFFCD6  new 65816 code implementing the Early Dash / Air Dash
;                     decision logic, and the two new state handlers. Fully disassembled and commented
;                     below.
; ============================================================================

; ----------------------------------------------------------------------------
; New animation-frame / hitbox data for the Air Dash poses ($36-$3B).
; Referenced by the bank-$8D OAM pointer table above and consumed by the
; (mostly unmodified) vanilla sprite/hitbox-drawing engine. Reproduced
; verbatim as data.
; ----------------------------------------------------------------------------

org $AFF700
        db $08, $ED, $00, $03, $00, $06, $F8, $13                             ; AFF700
        db $00, $FE, $F8, $12, $00, $FE, $F0, $02                             ; AFF708
        db $00, $EE, $F0, $08, $20, $02, $08, $16                             ; AFF710
        db $00, $02, $00, $06, $00, $F2, $00, $04                             ; AFF718
        db $20, $0C, $ED, $00, $03, $00, $06, $F8                             ; AFF720
        db $13, $00, $FE, $F8, $12, $00, $FE, $F0                             ; AFF728
        db $02, $00, $EE, $F0, $08, $20, $0D, $00                             ; AFF730
        db $0E, $00, $12, $08, $0F, $00, $0A, $08                             ; AFF738
        db $1F, $00, $02, $08, $1E, $00, $02, $08                             ; AFF740
        db $16, $00, $02, $00, $06, $00, $F2, $00                             ; AFF748
        db $04, $20, $08, $E7, $F7, $00, $20, $FF                             ; AFF750
        db $F9, $06, $00, $F7, $08, $16, $00, $EF                             ; AFF758
        db $07, $13, $00, $E7, $07, $03, $00, $F7                             ; AFF760
        db $00, $12, $00, $F7, $F8, $02, $00, $FF                             ; AFF768
        db $01, $04, $20, $09, $EA, $F9, $0D, $00                             ; AFF770
        db $E2, $F9, $0C, $00, $06, $F8, $13, $00                             ; AFF778
        db $FE, $F8, $12, $00, $FE, $F0, $02, $00                             ; AFF780
        db $EE, $F0, $08, $20, $02, $08, $16, $00                             ; AFF788
        db $02, $00, $06, $00, $F2, $00, $04, $20                             ; AFF790
        db $09, $EA, $F9, $0D, $00, $E2, $F9, $0C                             ; AFF798
        db $00, $06, $F8, $13, $00, $FE, $F8, $12                             ; AFF7A0
        db $00, $FE, $F0, $02, $00, $EE, $F0, $08                             ; AFF7A8
        db $20, $02, $08, $16, $00, $02, $00, $06                             ; AFF7B0
        db $00, $F2, $00, $04, $20, $08, $E7, $F7                             ; AFF7B8
        db $00, $20, $DF, $FF, $03, $00, $FF, $F9                             ; AFF7C0
        db $06, $00, $F7, $08, $16, $00, $EF, $07                             ; AFF7C8
        db $13, $00, $F7, $00, $12, $00, $F7, $F8                             ; AFF7D0
        db $02, $00, $FF, $01, $04, $20, $08, $ED                             ; AFF7D8
        db $00, $03, $00, $06, $F8, $13, $00, $FE                             ; AFF7E0
        db $F8, $12, $00, $FE, $F0, $02, $00, $EE                             ; AFF7E8
        db $F0, $00, $20, $02, $08, $16, $00, $02                             ; AFF7F0
        db $00, $06, $00, $F2, $00, $04, $20, $0C                             ; AFF7F8
        db $ED, $00, $03, $00, $06, $F8, $13, $00                             ; AFF800
        db $FE, $F8, $12, $00, $FE, $F0, $02, $00                             ; AFF808
        db $EE, $F0, $00, $20, $0D, $00, $0E, $00                             ; AFF810
        db $12, $08, $0F, $00, $0A, $08, $1F, $00                             ; AFF818
        db $02, $08, $1E, $00, $02, $08, $16, $00                             ; AFF820
        db $02, $00, $06, $00, $F2, $00, $04, $20                             ; AFF828
        db $08, $E7, $F7, $08, $20, $FF, $F9, $06                             ; AFF830
        db $00, $F7, $08, $16, $00, $EF, $07, $13                             ; AFF838
        db $00, $E7, $07, $03, $00, $F7, $00, $12                             ; AFF840
        db $00, $F7, $F8, $02, $00, $FF, $01, $04                             ; AFF848
        db $20, $09, $EA, $F9, $0D, $00, $EE, $F0                             ; AFF850
        db $00, $20, $E2, $F9, $0C, $00, $06, $F8                             ; AFF858
        db $13, $00, $FE, $F8, $12, $00, $FE, $F0                             ; AFF860
        db $02, $00, $02, $08, $16, $00, $02, $00                             ; AFF868
        db $06, $00, $F2, $00, $04, $20, $09, $EA                             ; AFF870
        db $F9, $0D, $00, $EE, $F0, $00, $20, $E2                             ; AFF878
        db $F9, $0C, $00, $06, $F8, $13, $00, $FE                             ; AFF880
        db $F8, $12, $00, $FE, $F0, $02, $00, $02                             ; AFF888
        db $08, $16, $00, $02, $00, $06, $00, $F2                             ; AFF890
        db $00, $04, $20, $08, $E7, $F7, $08, $20                             ; AFF898
        db $DF, $FF, $03, $00, $FF, $F9, $06, $00                             ; AFF8A0
        db $F7, $08, $16, $00, $EF, $07, $13, $00                             ; AFF8A8
        db $F7, $00, $12, $00, $F7, $F8, $02, $00                             ; AFF8B0
        db $FF, $01, $04, $20                                                 ; AFF8B8

; ----------------------------------------------------------------------------
; New code. Everything below this point is cross-checked against the
; supplied CPU trace logs (marked bytes were actually executed while
; performing an Early Dash / Air Dash in-game); a small
; number of straight-line, unconditional bytes that the traces happened not
; to hit are filled in by hand from context (each still shown with its
; exact byte values so the patch remains byte-for-byte reproducible).
; ----------------------------------------------------------------------------

org $AFFB38

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
        JML TryStart_Hook         ; AFFB38: 5C xx xx AF  (EARLY DASH gate, see below)
        NOP                       ; AFFB3C: EA
        ; (was: LDA $3323 / BNE LBL_AFFB76 -- 5 bytes, replicated in the hook)
TryStart_Resume:
        LDA $3A  ; AFFB3D: A5 3A  [$006BE2]
        BIT #$80                  ; AFFB3F: 89 80
        BEQ LBL_AFFB76            ; AFFB41: F0 33
        LDA $02  ; AFFB43: A5 02  [$006BAA]
        CMP #$02                  ; AFFB45: C9 02
        BEQ LBL_AFFB55            ; AFFB47: F0 0C
        CMP #$08                  ; AFFB49: C9 08
        BEQ LBL_AFFB55            ; AFFB4B: F0 08
        CMP #$10                  ; AFFB4D: C9 10
        BEQ LBL_AFFB55            ; AFFB4F: F0 04
        CMP #$12                  ; AFFB51: C9 12
        BNE LBL_AFFB64            ; AFFB53: D0 0F
LBL_AFFB55:
        LDA $2C  ; AFFB55: A5 2C  [$006BD4]
        BMI LBL_AFFB5F            ; AFFB57: 30 06
        JSL $849A24               ; AFFB59: 22 24 9A 84
        BCC LBL_AFFB64            ; AFFB5D: 90 05
LBL_AFFB5F:
        LDA #$0A                  ; AFFB5F: A9 0A
        STA $56                   ; AFFB61: 85 56
        RTL                       ; AFFB63: 6B
LBL_AFFB64:
        JSL $AFFBB2               ; AFFB64: 22 B2 FB AF
        BNE LBL_AFFB77            ; AFFB68: D0 0D
        LDA #$40                  ; AFFB6A: A9 40
        TSB $7E                   ; AFFB6C: 04 7E
        SEP #$30                  ; AFFB6E: E2 30
        LDA #$14                  ; AFFB70: A9 14
        STA $02  ; AFFB72: 85 02  [$006BAA]
        STZ $03  ; AFFB74: 64 03  [$006BAB]
LBL_AFFB76:
        RTL                       ; AFFB76: 6B

TryStartGroundDash_Alt:
        ; Reached when the quick-gate above wants a second opinion.
        ; CanStartDash_StateGate ($AFFB8A) performs the Air-Dash-specific
        ; eligibility check (airborne + has Leg Parts + not already at max
        ; "boosted" speed + not on a ladder/other restricted mode). If it
        ; passes, sets the same dp $7E bit $40 flag and transitions X into the
        ; new Air Dash state ($48).
LBL_AFFB77:
        JSL $AFFB8A               ; AFFB77: 22 8A FB AF
        BNE LBL_AFFB76            ; AFFB7B: D0 F9
        LDA #$40                  ; AFFB7D: A9 40
        TSB $7E                   ; AFFB7F: 04 7E
        SEP #$30                  ; AFFB81: E2 30
        LDA #$48                  ; AFFB83: A9 48
        STA $02  ; AFFB85: 85 02  [$006BAA]
        STZ $03  ; AFFB87: 64 03  [$006BAB]
        RTL                       ; AFFB89: 6B

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
        ;     vanilla "boosted" walljump push-off speed -- this prevents
        ;     air-dashing while already at that special speed).
        ;   - finally defers to JSL $8499AF (an existing engine check, likely
        ;     ladder/underwater/similar movement-restriction test); if that
        ;     reports "restricted" (carry set), Air Dash is denied too.
        JML StateGate_Hook        ; AFFB8A: 5C xx xx AF  (AIRDASH gate, see below)
        NOP                       ; AFFB8E: EA
        ; (was: LDA $3399 / BIT #$08 -- 5 bytes, replicated in the hook)
StateGate_Resume:
        BEQ LBL_AFFB9B            ; AFFB8F: F0 0A
        LDA $02  ; AFFB91: A5 02  [$006BAA]
        CMP #$06                  ; AFFB93: C9 06
        BEQ LBL_AFFB9E            ; AFFB95: F0 07
        CMP #$08                  ; AFFB97: C9 08
        BEQ LBL_AFFB9E            ; AFFB99: F0 03
LBL_AFFB9B:
        LDA #$01                  ; AFFB9B: A9 01
        RTL                       ; AFFB9D: 6B
LBL_AFFB9E:
        REP #$20                  ; AFFB9E: C2 20
        LDA $5C  ; AFFBA0: A5 5C  [$006C04]
        CMP #$0375                ; AFFBA2: C9 75 03
        SEP #$20                  ; AFFBA5: E2 20
        BEQ LBL_AFFB9B            ; AFFBA7: F0 F2
        JSL $8499AF               ; AFFBA9: 22 AF 99 84
        BCS LBL_AFFB9B            ; AFFBAD: B0 EC
        LDA #$00                  ; AFFBAF: A9 00
        RTL                       ; AFFBB1: 6B

CanStartDash_QuickGate:
        ; Cheap early-out used by TryStartGroundDash before bothering with the
        ; state gate above: if X's current state is already one of
        ; $00/$02/$04/$0A (a small set of "can't dash from here" states),
        ; immediately reports "not eligible" without the JSL $8499AF check.
        ; Otherwise defers to the same JSL $8499AF restriction check.
        LDA $02  ; AFFBB2: A5 02  [$006BAA]
        BEQ LBL_AFFBC5            ; AFFBB4: F0 0F
        CMP #$02                  ; AFFBB6: C9 02
        BEQ LBL_AFFBC5            ; AFFBB8: F0 0B
        CMP #$04                  ; AFFBBA: C9 04
        BEQ LBL_AFFBC5            ; AFFBBC: F0 07
        CMP #$0A                  ; AFFBBE: C9 0A
        BEQ LBL_AFFBC5            ; AFFBC0: F0 03
LBL_AFFBC2:
        LDA #$01                  ; AFFBC2: A9 01
        RTL                       ; AFFBC4: 6B
LBL_AFFBC5:
        JSL $8499AF               ; AFFBC5: 22 AF 99 84
        BCS LBL_AFFBC2            ; AFFBC9: B0 F7
        LDA #$00                  ; AFFBCB: A9 00
        RTL                       ; AFFBCD: 6B

State48_AirDash_Handler:
        ; New state $48 handler ("Air Dash"), called via the stub at
        ; $8182A1. Mirrors the structure of vanilla state handlers: dp $03
        ; (state "just entered" flag) is used to run one-time setup on the
        ; first frame only.
        LDX $03  ; AFFBCE: A6 03  [$006BAB]
        BNE LBL_AFFC11            ; AFFBD0: D0 3F
        INC $03  ; AFFBD2: E6 03  [$006BAB]
        LDA #$FF                  ; AFFBD4: A9 FF
        STA $1D  ; AFFBD6: 85 1D  [$006BC5]
        STZ $75  ; AFFBD8: 64 75  [$006C1D]
        LDA #$08                  ; AFFBDA: A9 08
        JSL $8088CF               ; AFFBDC: 22 CF 88 80
        JSL $81FFD0               ; AFFBE0: 22 D0 FF 81
        LDA #$13                  ; AFFBE4: A9 13
        CLC                       ; AFFBE6: 18
        ADC $6F  ; AFFBE7: 65 6F  [$006C17]
        JSL $848F07               ; AFFBE9: 22 07 8F 84
        LDA #$10                  ; AFFBED: A9 10
        STA $55  ; AFFBEF: 85 55  [$006BFD]
        LDA #$10                  ; AFFBF1: A9 10
        STA $52  ; AFFBF3: 85 52  [$006BFA]
        REP #$20                  ; AFFBF5: C2 20
        LDA #$0375                ; AFFBF7: A9 75 03
        STA $5C  ; AFFBFA: 85 5C  [$006C04]
        BIT $68  ; AFFBFC: 24 68  [$006C10]
        BVS LBL_AFFC03            ; AFFBFE: 70 03
        LDA #$FC8B                ; AFFC00: A9 8B FC
LBL_AFFC03:
        STA $1A  ; AFFC03: 85 1A  [$006BC2]
        LDA #$BB38                ; AFFC05: A9 38 BB
        STA $20  ; AFFC08: 85 20  [$006BC8]
        LDA #$A597                ; AFFC0A: A9 97 A5
        STA $31  ; AFFC0D: 85 31  [$006BD9]
        SEP #$20                  ; AFFC0F: E2 20

State48_AirDash_Continue:
        ; Per-frame continuation of the Air Dash state (runs every frame after
        ; the first). Checks wall-cling flags (dp $5E), buffered jump/next-
        ; state-request bits, and either keeps air-dashing, kicks off a
        ; walljump-style interrupt via the bank-$81 trampolines, or hands off
        ; to AirDash_EndCheck_Grounded once it detects ground/wall contact.
LBL_AFFC11:
        LDA $5E  ; AFFC11: A5 5E  [$006C06]
        BIT $04  ; AFFC13: 24 04  [$006BAC]
        BEQ LBL_AFFC19            ; AFFC15: F0 02
        STZ $2F                   ; AFFC17: 64 2F
LBL_AFFC19:
        LDA $59  ; AFFC19: A5 59  [$006C01]
        BNE LBL_AFFC23            ; AFFC1B: D0 06
        LDA $3B  ; AFFC1D: A5 3B  [$006BE3]
        BIT #$40                  ; AFFC1F: 89 40
        BEQ LBL_AFFC29            ; AFFC21: F0 06
LBL_AFFC23:
        LDA #$13                  ; AFFC23: A9 13
        JSL $81FFD4               ; AFFC25: 22 D4 FF 81
LBL_AFFC29:
        LDA #$01                  ; AFFC29: A9 01
        BIT $69  ; AFFC2B: 24 69  [$006C11]
        BVS LBL_AFFC31            ; AFFC2D: 70 02
        LDA #$02                  ; AFFC2F: A9 02
LBL_AFFC31:
        BIT $5E  ; AFFC31: 24 5E  [$006C06]
        BNE LBL_AFFC3B            ; AFFC33: D0 06
        JSL $81FFD8               ; AFFC35: 22 D8 FF 81
        BNE LBL_AFFC40            ; AFFC39: D0 05
LBL_AFFC3B:
        JSL $AFFC62               ; AFFC3B: 22 62 FC AF
        RTL                       ; AFFC3F: 6B
LBL_AFFC40:
        JSL $82823E               ; AFFC40: 22 3E 82 82
        DEC $52  ; AFFC44: C6 52  [$006BFA]
        BMI LBL_AFFC3B            ; AFFC46: 30 F3
        BIT $0F  ; AFFC48: 24 0F  [$006BB7]
        BVC LBL_AFFC52            ; AFFC4A: 50 06
        LDA #$02                  ; AFFC4C: A9 02
        JSL $81FFDC               ; AFFC4E: 22 DC FF 81
LBL_AFFC52:
        LDA #$35                  ; AFFC52: A9 35
        JSL $81FFE0               ; AFFC54: 22 E0 FF 81
        RTL                       ; AFFC58: 6B
LBL_AFFC59:
        SEP #$30                  ; AFFC59: E2 30
        LDA #$20                  ; AFFC5B: A9 20
        STA $02                   ; AFFC5D: 85 02
        STZ $03                   ; AFFC5F: 64 03
        RTL                       ; AFFC61: 6B

AirDash_EndCheck_Grounded:
        ; Checks the wall-cling bitflags (dp $5E, vanilla $0C06) for the
        ; "standing" bit ($04). If set, ends the Air Dash immediately
        ; (transitions to state $4A, "Air Dash End"); otherwise falls through
        ; into the shared physics/animation-timer update shared with the
        ; regular airborne-dash continuation.
        SEP #$30                  ; AFFC62: E2 30
        LDA $5E  ; AFFC64: A5 5E  [$006C06]
        BIT #$04                  ; AFFC66: 89 04
        BNE LBL_AFFC59            ; AFFC68: D0 EF
        LDA #$4A                  ; AFFC6A: A9 4A
        STA $02  ; AFFC6C: 85 02  [$006BAA]
        STZ $03  ; AFFC6E: 64 03  [$006BAB]
        RTL                       ; AFFC70: 6B

LandingHook_Stub:
        ; Target of the bank-$81 $81F0EB hook (replaces "STA $16 / LDA $0B").
        ; Performs the original store, then looks up X (dp $0B, an index) in
        ; the relocated bank-$86 table (see $81F109 / $86FFFD above) before
        ; returning -- this is the extra per-sub-state behaviour needed so that
        ; landing out of an Air Dash is handled the same way as landing out of
        ; a normal dash.
        STA $16  ; AFFC71: 85 16  [$00793E]
        LDX $0B  ; AFFC73: A6 0B  [$007933]
        LDA $FFFA,X  ; AFFC75: BD FA FF  [$86FFFB]
        RTL                       ; AFFC78: 6B

State4A_AirDashEnd_Handler:
        ; New state $4A handler ("Air Dash End"), called via the stub at
        ; $8182A6. Resets X's velocity/position deltas, restores the normal
        ; graphics pointer, and (after a short animation-timer countdown, dp
        ; $4E) hands control back to a normal grounded/airborne state, mirroring
        ; how the vanilla ground-dash-end state behaves.
        LDX $03  ; AFFC79: A6 03  [$006BAB]
        BNE LBL_AFFC9F            ; AFFC7B: D0 22
        INC $03  ; AFFC7D: E6 03  [$006BAB]
        REP #$20                  ; AFFC7F: C2 20
        LDA #$A552                ; AFFC81: A9 52 A5
        STA $20  ; AFFC84: 85 20  [$006BC8]
        STZ $1A  ; AFFC86: 64 1A  [$006BC2]
        STZ $1C  ; AFFC88: 64 1C  [$006BC4]
        SEP #$20                  ; AFFC8A: E2 20
        STZ $1F  ; AFFC8C: 64 1F  [$006BC7]
        LDA #$40                  ; AFFC8E: A9 40
        STA $1E  ; AFFC90: 85 1E  [$006BC6]
        LDA #$08                  ; AFFC92: A9 08
        STA $4E  ; AFFC94: 85 4E  [$006BF6]
        LDA #$16                  ; AFFC96: A9 16
        CLC                       ; AFFC98: 18
        ADC $6F  ; AFFC99: 65 6F  [$006C17]
        JSL $848F07               ; AFFC9B: 22 07 8F 84
LBL_AFFC9F:
        LDA $59  ; AFFC9F: A5 59  [$006C01]
        BNE LBL_AFFCA9            ; AFFCA1: D0 06
        LDA $3B  ; AFFCA3: A5 3B  [$006BE3]
        BIT #$40                  ; AFFCA5: 89 40
        BEQ LBL_AFFCAF            ; AFFCA7: F0 06
LBL_AFFCA9:
        LDA #$16                  ; AFFCA9: A9 16
        JSL $81FFE4               ; AFFCAB: 22 E4 FF 81
LBL_AFFCAF:
        DEC $4E  ; AFFCAF: C6 4E  [$006BF6]
        BNE LBL_AFFCC6            ; AFFCB1: D0 13
LBL_AFFCB3:
        STZ $4F  ; AFFCB3: 64 4F  [$006BF7]
        LDA #$04                  ; AFFCB5: A9 04
        TSB $87                   ; AFFCB7: 04 87
        SEP #$30                  ; AFFCB9: E2 30
        LDA #$08                  ; AFFCBB: A9 08
        STA $02  ; AFFCBD: 85 02  [$006BAA]
        STZ $03  ; AFFCBF: 64 03  [$006BAB]
        LDA #$08                  ; AFFCC1: A9 08
        STA $2F  ; AFFCC3: 85 2F  [$006BD7]
        RTL                       ; AFFCC5: 6B
LBL_AFFCC6:
        LDA $37  ; AFFCC6: A5 37  [$006BDF]
        BIT #$03                  ; AFFCC8: 89 03
        BNE LBL_AFFCB3            ; AFFCCA: D0 E7
        JSL $828174               ; AFFCCC: 22 74 81 82
        LDA #$16                  ; AFFCD0: A9 16
        JSL $81FFE8               ; AFFCD2: 22 E8 FF 81
        RTL                       ; AFFCD6: 6B

; ############################################################################
; # PART 6 - EXTRA OPTIONS  (new code)
; ############################################################################

; ----------------------------------------------------------------------------
; Constants
; ----------------------------------------------------------------------------
!SRAM_SIG1    = $40FF00
!SRAM_SIG2    = $40FF01
!SRAM_DTAP    = $40FF02
!SRAM_EARLY   = $40FF03
!SRAM_AIR     = $40FF04
!SRAM_SUM     = $40FF05
!SRAM_SUB     = $40FF06           ; BETTER SUB-TANK (added after the first three,
!SRAM_SUBN    = $40FF07           ; stored with its own complement so saves made
                                  ; before it existed stay valid)

!W_DTAP       = $40FF10           ; working copies, indexed by item (0-3)
!W_EARLY      = $40FF11
!W_AIR        = $40FF12
!W_SUB        = $40FF13

!EXIT_ITEM    = $04               ; item index of EXIT (items 0-3 are toggles)
!NUM_ITEMS    = $05

!CURSOR       = $7EFF80           ; scratch, same byte OPTION MODE uses (it
!TMP          = $7EFF82           ; re-initialises it on entry, so no clash)

; message ids (the pointer table at $86910B has ~49 unused slots, $44-$74)
!MSG_MAIN0    = $44               ; $44-$47 main menu, cursor on row 0-3
!MSG_TITLE    = $48               ; "EXTRA OPTIONS" title
!MSG_ITEM0    = $49               ; $49-$58: 4 items x (off,off+,on,on+)
!MSG_EXIT     = $59               ; $59 dim, $5A highlighted
!MSG_CLRTITLE = $5B               ; blanks the gold "OPTION MODE" art on BG1

; ----------------------------------------------------------------------------
; 1. Message-pointer table entries (table at $86:910B, 2 bytes per id)
; ----------------------------------------------------------------------------
org $86910B+(!MSG_MAIN0*2)
        dw MsgMain0, MsgMain1, MsgMain2, MsgMain3
        dw MsgTitle
        dw MsgDTapOff, MsgDTapOffHi, MsgDTapOn, MsgDTapOnHi
        dw MsgEarlyOff, MsgEarlyOffHi, MsgEarlyOn, MsgEarlyOnHi
        dw MsgAirOff, MsgAirOffHi, MsgAirOn, MsgAirOnHi
        dw MsgSubOff, MsgSubOffHi, MsgSubOn, MsgSubOnHi
        dw MsgExit, MsgExitHi
        dw MsgClrTitle

; ----------------------------------------------------------------------------
; 2. Message data (bank $86 free space)
;    Format: [len][attr][vram lo][vram hi][len bytes of tile ids] ... [0]
;    VRAM word address = $0800 + row*32 + col  (BG3 tilemap)
;    attr $20 = normal (cyan), $24 = main-menu highlight, $2C = highlight
; ----------------------------------------------------------------------------
org $86FB80

; ----------------------------------------------------------------------------
; main menu: 4 rows at tile rows 18/20/22/24 (shifted up 16px from the
; original 20/22/24 so the 33px-tall cursor sprite fits above the screen
; bottom with four rows)
; ----------------------------------------------------------------------------
macro mainmenu(a1, a2, a3, a4)
        db 11, <a1> : dw $0A4A : db "GAME  START"                             ; row 18, col 10
        db  9, <a2> : dw $0A8A : db "PASS WORD"                               ; row 20
        db 11, <a3> : dw $0ACA : db "OPTION MODE"                             ; row 22
        db 13, <a4> : dw $0B0A : db "EXTRA OPTIONS"                           ; row 24
        db 0
endmacro

MsgMain0: %mainmenu($24, $20, $20, $20)
MsgMain1: %mainmenu($20, $24, $20, $20)
MsgMain2: %mainmenu($20, $20, $24, $20)
MsgMain3: %mainmenu($20, $20, $20, $24)

; cursor sprite Y for each main-menu row (was a 3-entry table at $86:8875)
MenuCursorY:
        db $96, $A6, $B6, $C6

; ----------------------------------------------------------------------------
; EXTRA OPTIONS title (regular font, row 4, centred: col 9)
; ----------------------------------------------------------------------------
MsgTitle:
        db 13, $24 : dw $0889 : db "EXTRA OPTIONS"
        db 0

; ----------------------------------------------------------------------------
; toggle rows: label at col 6, value at col 23 (rows 10/12/14/16).  "ON "
; ----------------------------------------------------------------------------
; is padded with a space so it fully overwrites the "F" of "OFF".
MsgDTapOff:     db 10, $20 : dw $0946 : db "D-TAP DASH" : db 3, $20 : dw $0957 : db "OFF" : db 0
MsgDTapOffHi:   db 10, $2C : dw $0946 : db "D-TAP DASH" : db 3, $2C : dw $0957 : db "OFF" : db 0
MsgDTapOn:      db 10, $20 : dw $0946 : db "D-TAP DASH" : db 3, $20 : dw $0957 : db "ON " : db 0
MsgDTapOnHi:    db 10, $2C : dw $0946 : db "D-TAP DASH" : db 3, $2C : dw $0957 : db "ON " : db 0

MsgEarlyOff:    db 10, $20 : dw $0986 : db "EARLY DASH" : db 3, $20 : dw $0997 : db "OFF" : db 0
MsgEarlyOffHi:  db 10, $2C : dw $0986 : db "EARLY DASH" : db 3, $2C : dw $0997 : db "OFF" : db 0
MsgEarlyOn:     db 10, $20 : dw $0986 : db "EARLY DASH" : db 3, $20 : dw $0997 : db "ON " : db 0
MsgEarlyOnHi:   db 10, $2C : dw $0986 : db "EARLY DASH" : db 3, $2C : dw $0997 : db "ON " : db 0

MsgAirOff:      db 7, $20 : dw $09C6 : db "AIRDASH" : db 3, $20 : dw $09D7 : db "OFF" : db 0
MsgAirOffHi:    db 7, $2C : dw $09C6 : db "AIRDASH" : db 3, $2C : dw $09D7 : db "OFF" : db 0
MsgAirOn:       db 7, $20 : dw $09C6 : db "AIRDASH" : db 3, $20 : dw $09D7 : db "ON " : db 0
MsgAirOnHi:     db 7, $2C : dw $09C6 : db "AIRDASH" : db 3, $2C : dw $09D7 : db "ON " : db 0

MsgSubOff:      db 15, $20 : dw $0A06 : db "BETTER SUB-TANK" : db 3, $20 : dw $0A17 : db "OFF" : db 0
MsgSubOffHi:    db 15, $2C : dw $0A06 : db "BETTER SUB-TANK" : db 3, $2C : dw $0A17 : db "OFF" : db 0
MsgSubOn:       db 15, $20 : dw $0A06 : db "BETTER SUB-TANK" : db 3, $20 : dw $0A17 : db "ON " : db 0
MsgSubOnHi:     db 15, $2C : dw $0A06 : db "BETTER SUB-TANK" : db 3, $2C : dw $0A17 : db "ON " : db 0

; ----------------------------------------------------------------------------
; EXIT (row 21, col 14)
; ----------------------------------------------------------------------------
MsgExit:       db 4, $20 : dw $0AAE : db "EXIT" : db 0
MsgExitHi:     db 4, $2C : dw $0AAE : db "EXIT" : db 0

; ----------------------------------------------------------------------------
; blank the "OPTION MODE" title art that gfx list $50 puts on BG1
; (BG1 map base = word $5000; art occupies rows 3-4, cols 5-26)
; ----------------------------------------------------------------------------
MsgClrTitle:
        db 22, $00 : dw $5065 : fillbyte $00 : fill 22
        db 22, $00 : dw $5085 : fillbyte $00 : fill 22
        db 0
assert pc() <= $870000

; ----------------------------------------------------------------------------
; 3. Bank $80 trampolines
;    The menu helpers are bank-$80 routines that end in RTS, so they can only
;    be JSR'd from bank $80. New code lives in bank $AF, so it JSLs these
;    stubs (JSR + RTL). They are frame-yield safe: the cooperative scheduler
;    ($8100) saves/restores the whole stack, so extra stack depth is fine.
; ----------------------------------------------------------------------------
org $80FEB8
T_8100: JSR $8100 : RTL          ; yield one frame
T_89E3: JSR $89E3 : RTL          ; draw message A
T_8A47: JSR $8A47 : RTL          ; clear sprites / flush
T_8BD1: JSR $8BD1 : RTL
T_88EE: JSR $88EE : RTL          ; BG register setup
T_B30B: JSR $B30B : RTL          ; graphics list loader (Y = list)
T_8975: JSR $8975 : RTL          ; fade in
T_8997: JSR $8997 : RTL          ; fade out
T_8875: JSR $8875 : RTL          ; queue sound/music cmd $F6 (Y = param)
T_888D: JSR $888D : RTL          ; queue sound A
assert pc() <= $80FFA0

; ----------------------------------------------------------------------------
; 4. Main menu hooks
; ----------------------------------------------------------------------------
; selection dispatcher: LDA $3C / ASL A / TAX  (4 bytes, replaced by the JML)
; followed by the original JMP ($9314,X) at $809311, which MenuDispatch jumps
; back to for rows 0-2 (so that instruction must stay intact).
org $80930D
        JML MenuDispatch

; initial draw of the main menu (message id $10 -> $44)
org $80925D
        db !MSG_MAIN0
; cursor-move redraw: message = $10 + cursor -> $44 + cursor
org $809295
        db !MSG_MAIN0
; cursor UP wrap-around: row 0 -> last row (2 -> 3)
org $809278
        db $03
; cursor DOWN wrap-around: after last row (3 -> 4)
org $809283
        db $04
; cursor sprite-Y table (LDA $8875,X, DB=$86) -> 4-entry table
org $80928C
        dw MenuCursorY
; initial cursor sprite Y (row 0)
org $809237
        db $96

; ----------------------------------------------------------------------------
; 5. Boot hook: load the saved toggles
;    $80FDF9 was "JML $808007" (right after the SA-1 init at $80FD9B, which
;    has already enabled BW-RAM writes via $2226).
; ----------------------------------------------------------------------------
org $80FDF9
        JML BootLoad

; ----------------------------------------------------------------------------
; 6. New code (bank $AF free space)
; ----------------------------------------------------------------------------
org $AFE990

; ----------------------------------------------------------------------------
; boot: saved copy -> working copy (or defaults)
; ----------------------------------------------------------------------------
BootLoad:
        PHP
        REP #$30                  ; (state is unknown this early)
        PHA
        SEP #$30
        LDA.l !SRAM_SIG1
        CMP.b #'M'
        BNE .defaults
        LDA.l !SRAM_SIG2
        CMP.b #'X'
        BNE .defaults
        LDA.l !SRAM_DTAP
        CLC
        ADC.l !SRAM_EARLY
        ADC.l !SRAM_AIR
        ADC.b #$A5
        CMP.l !SRAM_SUM
        BNE .defaults
        LDA.l !SRAM_DTAP : AND.b #$01 : STA.l !W_DTAP
        LDA.l !SRAM_EARLY : AND.b #$01 : STA.l !W_EARLY
        LDA.l !SRAM_AIR : AND.b #$01 : STA.l !W_AIR
        LDA.l !SRAM_SUB           ; BETTER SUB-TANK has its own check
        EOR.l !SRAM_SUBN          ; (value XOR complement must be $FF),
        CMP.b #$FF                ; so saves from before it existed load
        BNE .sub_default          ; fine with it ON
        LDA.l !SRAM_SUB : AND.b #$01 : STA.l !W_SUB
        BRA .done
.defaults:
        LDA.b #$00
        STA.l !W_DTAP
        LDA.b #$01
        STA.l !W_EARLY
        STA.l !W_AIR
.sub_default:
        LDA.b #$01
        STA.l !W_SUB
.done:
        REP #$20
        PLA
        PLP
        JML $808007               ; the instruction this hook replaced

; ----------------------------------------------------------------------------
; working copy -> SRAM (called when EXIT is pressed)
; ----------------------------------------------------------------------------
SaveSettings:
        PHP
        SEP #$30
        LDA.l !W_DTAP  : AND.b #$01 : STA.l !SRAM_DTAP
        LDA.l !W_EARLY : AND.b #$01 : STA.l !SRAM_EARLY
        LDA.l !W_AIR   : AND.b #$01 : STA.l !SRAM_AIR
        LDA.l !W_SUB   : AND.b #$01 : STA.l !SRAM_SUB
        EOR.b #$FF                ; complement = its validity check
        STA.l !SRAM_SUBN
        CLC
        LDA.l !SRAM_DTAP
        ADC.l !SRAM_EARLY
        ADC.l !SRAM_AIR
        ADC.b #$A5
        STA.l !SRAM_SUM
        LDA.b #'M' : STA.l !SRAM_SIG1  ; signature last: a torn save is ignored
        LDA.b #'X' : STA.l !SRAM_SIG2
        PLP
        RTS

; ----------------------------------------------------------------------------
; main menu selection dispatcher (8-bit A/X, DP=0, DB=$86)
; ----------------------------------------------------------------------------
MenuDispatch:
        LDA $3C
        CMP.b #$03
        BEQ .extra
        ASL A
        TAX
        JML $809311               ; JMP ($9314,X): the original dispatch
.extra:
        JSL ExtraOptionsScreen
; Return straight to the main menu: top-level state $38 = 2 (menu), substate
; and timers/cursor = 0 so its init runs again (reloads the logo graphics).
; This is exactly how the intro enters the menu ($80:8C80). OPTION MODE
; instead sets $38 = 0, which replays the intro.
        LDA.b #$02
        STA $38
        STZ $39
        STZ $3A
        STZ $3B
        STZ $3C
        JML $809357               ; the RTS that ended the original handler

; ----------------------------------------------------------------------------
; row drawing
; ----------------------------------------------------------------------------
; A = item (0-3 toggles, 4 = EXIT), Y = highlighted (0/1).  8-bit A/X/Y.
DrawRow:
        CMP.b #!EXIT_ITEM
        BEQ .exitrow
        TAX
        ASL A
        ASL A                     ; item * 4
        STA.l !TMP
        TYA
        CLC
        ADC.l !TMP
        STA.l !TMP                ; item*4 + highlighted
        LDA.l !W_DTAP,X           ; state (0/1) of this item
        ASL A
        CLC
        ADC.l !TMP
        CLC
        ADC.b #!MSG_ITEM0
        JSL T_89E3
        RTS
.exitrow:
        TYA
        CLC
        ADC.b #!MSG_EXIT
        JSL T_89E3
        RTS

DrawAll:
        LDX.b #$00
.next:
        PHX
        TXA
        LDY.b #$00
        CMP.l !CURSOR
        BNE .dim
        LDY.b #$01
.dim:
        JSR DrawRow
        PLX
        INX
        CPX.b #!NUM_ITEMS
        BNE .next
        RTS

; ----------------------------------------------------------------------------
; the EXTRA OPTIONS screen
; ----------------------------------------------------------------------------
; Same skeleton as OPTION MODE ($80:EAC1): blocking loop, one yield per frame,
; run with the screen already faded out by the main menu.
; In: 8-bit A/X, DP=0.  Out: screen faded out again, flags/DP restored.
ExtraOptionsScreen:
        PHP
        REP #$20
        PHD
        LDA.w #$0000
        TCD
        SEP #$30

        JSL T_8A47                ; same preamble as OPTION MODE
        JSL T_8BD1
        LDA.b #$00
        STA.l !CURSOR
        JSL T_88EE                ; BG registers
        LDA.b #!MSG_TITLE
        JSL T_89E3
        JSR DrawAll
        LDA.b #$07
        TSB $A2
        JSL T_8100

        LDY.b #$4E                ; same graphics/palette sets OPTION
        JSL T_B30B                ; MODE loads (font, title art, ...)
        JSL T_8100
        LDY.b #$50
        JSL T_B30B
        JSL T_8100
        REP #$10
        LDY.w #$0132
        JSL $828011
        SEP #$10
        JSL T_8100
        LDA.b #!MSG_CLRTITLE      ; remove the "OPTION MODE" art
        JSL T_89E3
        JSL T_8100
        JSL T_8975                ; fade in

.loop:
        LDA $AC                   ; newly pressed
        BIT.b #$04                ; DOWN
        BNE .down
        BIT.b #$08                ; UP
        BNE .up
        BIT.b #$03                ; RIGHT / LEFT
        BNE .toggle
        LDA.l !CURSOR
        CMP.b #!EXIT_ITEM
        BNE .frame
        LDA $AC                   ; START / Y   (same test as OPTION
        AND.b #$50                ; MODE's EXIT)
        BNE .exit
        LDA $AB                   ; A
        AND.b #$80
        BNE .exit
.frame:
        JSL T_8100
        BRA .loop

.down:
        LDA.l !CURSOR
        INC A
        CMP.b #!NUM_ITEMS
        BNE .move
        LDA.b #$00
        BRA .move
.up:
        LDA.l !CURSOR
        DEC A
        BPL .move
        LDA.b #!EXIT_ITEM
.move:
        PHA
        LDA.l !CURSOR
        LDY.b #$00
        JSR DrawRow               ; old row -> normal
        PLA
        STA.l !CURSOR
        LDY.b #$01
        JSR DrawRow               ; new row -> highlighted
        BRA .frame

.toggle:
        LDA.l !CURSOR
        CMP.b #!EXIT_ITEM
        BEQ .frame                ; EXIT row: nothing to toggle
        TAX
        LDA.l !W_DTAP,X
        EOR.b #$01
        STA.l !W_DTAP,X
        TXA
        LDY.b #$01
        JSR DrawRow
        BRA .frame

.exit:
        JSR SaveSettings          ; <- SRAM write happens here
        LDY.b #$04                ; same exit sequence as OPTION MODE
        JSL T_8875
        LDA.b #$F1
        JSL T_888D
        JSL T_8997                ; fade out
        REP #$20
        PLD
        PLP
        RTL

; ----------------------------------------------------------------------------
; 7. Gameplay gates
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; EXTRA OPTIONS HOOK: EARLY DASH
; ----------------------------------------------------------------------------
; Returns Z=1 ("dash NOT allowed") only if EARLY DASH is OFF *and* X does not
; have the Leg Armor ($3399 bit 3).  With the Leg Armor, dash is always allowed.
; 8-bit A.  Used by the double-tap detector entry ($819712) and the Dash
; button path (TryStart_Hook).
EarlyDash_Gate:
        LDA.l !W_EARLY
        BNE .allowed
        LDA $3399
        AND.b #$08
        RTL
.allowed:
        LDA.b #$01                ; Z=0
        RTL

; ----------------------------------------------------------------------------
; EXTRA OPTIONS HOOK: Dash button path
; ----------------------------------------------------------------------------
; Replaces "LDA $3323 / BNE <rtl>" at the entry of TryStartGroundDash.
TryStart_Hook:
        LDA $3323
        BNE .rtl
        JSL EarlyDash_Gate
        BEQ .rtl                  ; no Leg Armor and EARLY DASH off
        JML TryStart_Resume
.rtl:
        RTL

; ----------------------------------------------------------------------------
; EXTRA OPTIONS HOOK: AIRDASH
; ----------------------------------------------------------------------------
; Replaces "LDA $3399 / BIT #$08" at the entry of CanStartDash_StateGate.
; That gate is the only way into the Air Dash state ($48), from both the Dash
; button and the double-tap path, so gating it switches Air Dash off entirely.
; Returns A=1 (not eligible) when AIRDASH is OFF.
StateGate_Hook:
        LDA.l !W_AIR
        BEQ .deny
        LDA $3399
        BIT.b #$08
        JML StateGate_Resume      ; (Z from BIT decides, as originally)
.deny:
        LDA.b #$01
        RTL

; ----------------------------------------------------------------------------
; EXTRA OPTIONS HOOKS: BETTER SUB-TANK
; ----------------------------------------------------------------------------
; The SA-1 patch ("Sub-Tanks stop depleting at full health") changed three
; things in the weapons-menu Sub-Tank code. Two of them are toggled here; the
; third needs no toggle (see the end of this comment).
;
;  1. Heal rate.  Vanilla heals 1 per tick (every 4 frames), or 2 if a certain
;     byte has a low nibble >= $E ($80:C6F3-C70C). That check indexes
;     "$1F83,X" with X = (health & $7F) - $0A, i.e. it uses HEALTH as the
;     index, where it was clearly meant to use the Sub-Tank number. At 10+
;     health it reads real RAM (the Sub-Tank bytes and what follows them); at
;     9 or less health X wraps to $F6-$FF and the address ($2079-$2082) is
;     not RAM at all: it is open bus, which emulators such as Mesen return as
;     $1F (the operand's high byte), i.e. "+2" -- exactly what the vanilla
;     trace shows. The SA-1 patch dropped the check and always heals 2.
;     -> SubTank_SetRate: ON = always 2 (SA-1), OFF = the vanilla check,
;        reproduced instruction for instruction ($1F83 is $3383 in the SA-1
;        RAM map), with the open-bus case returning the same "+2".
;
;  2. Stop at full health.  Vanilla keeps ticking until the Sub-Tank's own
;     level reaches 0, so energy that is not needed is wasted. The SA-1 patch
;     added "LDA $339A / SEC / SBC $6BCF / BEQ <finish>" (max health - health
;     == 0 -> finish) right after the per-tick redraw, so the Sub-Tank keeps
;     whatever was not needed.
;     -> SubTank_FullCheck: ON = that check, OFF = never "full" (vanilla).
;
;  3. The routine that moves Sub-Tanks down after one is used ($80:CE08 in
;     the SA-1 ROM, $80:CDB7 in vanilla) gained a guard so it only shuffles
;     when the used Sub-Tank is empty. In vanilla flow it is only ever called
;     once the Sub-Tank IS empty, so the guard is always satisfied: with
;     BETTER SUB-TANK off the behaviour is identical to vanilla and it is
;     left alone.
;
; Both hooks run in the menu's context (8-bit A/X, the menu's direct page).

; Replaces "LDA #$02 / STA $11" (the heal-per-tick amount, dp $11) at $80C752.
SubTank_SetRate:
        LDA.b #$02
        STA $11                   ; ON: always +2 per tick (SA-1)
        LDA.l !W_SUB
        BNE .done
        LDA $6BCF                 ; OFF: vanilla $80:C6F3-C70C
        AND.b #$7F                ; (A = health & $7F at this point)
        SEC
        SBC.b #$0A                ; the vanilla index quirk
        TAX
        LDA.b #$01
        STA $11
        CPX.b #$80                ; X wrapped (health < 10): the vanilla
        BCS .inc                  ; address is open bus -> reads $1F -> +2
        LDA $3383,X               ; $1F83,X in the SA-1 RAM map
        AND.b #$0F
        CMP.b #$0E
        BCC .done
.inc:
        INC $11
.done:
        RTL

; Replaces "LDA $339A / SEC / SBC $6BCF" (7 bytes, followed by the original
; BEQ) at $80C7B8. Z=1 -> health is full -> finish (SA-1 behaviour).
; X (the Sub-Tank number) must be preserved.
SubTank_FullCheck:
        LDA.l !W_SUB
        BNE .on
        LDA.b #$01                ; OFF: Z=0, never "full" (vanilla)
        RTL
.on:
        LDA $339A
        SEC
        SBC $6BCF
        RTL

; ----------------------------------------------------------------------------
; EXTRA OPTIONS HOOK: D-TAP DASH
; ----------------------------------------------------------------------------
; Expanded double-tap gate, from dtap_menu_for_mmxsa1 (unchanged behaviour).
;
; The SA-1 patch's gate at $81FF60 only proceeds when I-RAM $3348 or $3208 is
; non-zero (neither is ever set by the game, so the vanilla double-tap
; detector at $819723-$819756 was unreachable). This adds the D-TAP DASH
; toggle as a third OR-condition, then implements Mega Man X2's two-stage
; dash commit:
;     QuickGate  -- states $00/$02/$04/$0A, then JSL $8499AF
;                   success -> original ground-dash tail at $81975A
;     StateGate  -- Leg Armor + airborne states $06/$08, AIRDASH on
;                   success -> face tapped direction, enter state $48
;     else       -> original 12-frame timer at $819766
; On D-TAP OFF it returns through the RTS at $81FF6A.
NewGateCheck:
        LDA $3348
        BNE .on
        LDA $3208
        BNE .on
        LDA.l !W_DTAP
        BEQ .fail
.on:
        LDA $02
        BEQ .gcheck
        CMP.b #$02
        BEQ .gcheck
        CMP.b #$04
        BEQ .gcheck
        CMP.b #$0A
        BNE .try_air
.gcheck:
        JSL $8499AF
        BCS .try_air
        LDA.b #$00
        JML $81975A               ; Z set: original ground-dash commit
.try_air:
        JSL CanStartDash_StateGate  ; Leg Armor + airborne + AIRDASH on
        BNE .timer
        LDA $37                   ; face the tapped direction (same
        BIT.b #$02                ; helper as vanilla $819576)
        BEQ .not_left
        STZ $69
        BRA .faced
.not_left:
        BIT.b #$01
        BEQ .faced
        LDA.b #$40
        STA $69
.faced:
        LDA.b #$40
        TRB $7E                   ; vanilla double-tap clears this bit
        SEP #$30
        LDA.b #$48                ; Air Dash state
        STA $02
        STZ $03
        JML $81FF6A               ; RTS back to the detector's caller
.timer:
        JML $819766               ; DEC $51 / timeout the double-tap window
.fail:
        JML $81FF6A
assert pc() <= $AFF700

; ----------------------------------------------------------------------------
; 8. EARLY DASH SPRITE FIX
; ----------------------------------------------------------------------------
; WITHOUT the Leg Armor, X has no dash art of his own: the vanilla game never
; lets him dash. Therefore we added six extra poses ($36-$3B) whose tiles
; show X's *normal* legs, plus a hook in the sprite engine that redirects
; the pose lookup to a new table whenever X (DP = $6BA8) lacks the
; Leg Armor ($3399 bit 3 clear).
;
; How the lookup works ($848FF6):
;   pose ($17) * 2 -> Y;  LDA ($31),Y  (DP $31 = $A597 -> bank-$85 table)
;   + $A597 = address of a tile-DMA record list in bank $85. Each record is
;   [len (x16 bytes)][24-bit source][flag: $60 = more follows, $E1 = last].
;   Vanilla pose $36 -> $85A7D2 -> sources $AE9C20/$AE9E20 (Leg Armor art).
;   Restored   pose $36 -> $85B3A0 -> sources in bank $AF (normal legs).

; ----------------------------------------------------------------------------
; bank $84: sprite engine, pose -> record-list lookup
; ----------------------------------------------------------------------------
; Vanilla:  LDA $17 / AND #$00FF / ASL / TAY / CLC / LDA ($31),Y   (10 bytes)
; The JSL routine returns the same value in A ($AFFB00 does the LDA ($31),Y).
org $848FF6
        JSL $AFFB00               ; 848FF6: 22 00 FB AF
        NOP                       ; 848FFA: EA
        NOP                       ; 848FFB: EA
        NOP                       ; 848FFC: EA
        NOP                       ; 848FFD: EA
        NOP                       ; 848FFE: EA
        CLC                       ; 848FFF: 18

; ----------------------------------------------------------------------------
; bank $AF: lookup routine
; ----------------------------------------------------------------------------
org $AFFB00
GetHitboxPtr_or_ExtendedFrame:
        ; Not X (DP != $6BA8), or X *has* the Leg Armor -> vanilla lookup.
        LDA $3399  ; AFFB00: AD 99 33  [$853399]
        AND #$00FF                ; AFFB03: 29 FF 00
        BIT #$0008                ; AFFB06: 89 08 00
        BNE LBL_AFFB11            ; AFFB09: D0 06
        TDC                       ; AFFB0B: 7B
        CMP #$6BA8                ; AFFB0C: C9 A8 6B
        BEQ LBL_AFFB1C            ; AFFB0F: F0 0B
LBL_AFFB11:
        LDA $17  ; AFFB11: A5 17  [$006BBF]
        AND #$00FF                ; AFFB13: 29 FF 00
        ASL                       ; AFFB16: 0A
        TAY                       ; AFFB17: A8
        CLC                       ; AFFB18: 18
        LDA ($31),Y  ; AFFB19: B1 31  [$85A597]
        RTL                       ; AFFB1B: 6B

GetHitboxPtr_ExtendedRange:
        ; X without Leg Armor: poses $36-$3B use the new $85B390 table.
LBL_AFFB1C:
        LDA $17  ; AFFB1C: A5 17  [$006BBF]
        AND #$00FF                ; AFFB1E: 29 FF 00
        CMP #$0036                ; AFFB21: C9 36 00
        BCC LBL_AFFB11            ; AFFB24: 90 EB
        CMP #$003C                ; AFFB26: C9 3C 00
        BCS LBL_AFFB11            ; AFFB29: B0 E6
        SEC                       ; AFFB2B: 38
        SBC #$0036                ; AFFB2C: E9 36 00
        ASL                       ; AFFB2F: 0A
        CLC                       ; AFFB30: 18
        ADC #$0DF9                ; AFFB31: 69 F9 0D
        TAY                       ; AFFB34: A8
        LDA ($31),Y  ; AFFB35: B1 31  [$85B390]
        RTL                       ; AFFB37: 6B
assert pc() == $AFFB38                  ; TryStartGroundDash starts here

; ----------------------------------------------------------------------------
; bank $85: pose table ($A597 + $0DF9 = $B390) + tile-DMA records
; ----------------------------------------------------------------------------
; Entries are offsets from $A597 (the value in DP $31).
org $85B390
        dw PoseRec_36-$A597, PoseRec_37-$A597, PoseRec_38-$A597
        dw PoseRec_39-$A597, PoseRec_3A-$A597, PoseRec_3B-$A597
        db $FF, $FF, $FF, $FF

macro dashrec(srcA, srcB)
        db $20 : dl <srcA> : db $60                                           ; 512 bytes, more records follow
        db $20 : dl <srcB> : db $E1                                           ; 512 bytes, last record
endmacro

PoseRec_36: %dashrec(AirDashGfx_A, AirDashGfx_B) : db $FF,$FF,$FF,$FF,$FF,$FF
PoseRec_37: %dashrec(AirDashGfx_A, AirDashGfx_B) : db $FF,$FF,$FF,$FF,$FF,$FF
PoseRec_38: %dashrec(AirDashGfx_C, AirDashGfx_D) : db $FF,$FF,$FF,$FF,$FF,$FF
PoseRec_39: %dashrec(AirDashGfx_A, AirDashGfx_B) : db $FF,$FF,$FF,$FF,$FF,$FF
PoseRec_3A: %dashrec(AirDashGfx_A, AirDashGfx_B) : db $FF,$FF,$FF,$FF,$FF,$FF
PoseRec_3B: %dashrec(AirDashGfx_E, AirDashGfx_F)
assert PoseRec_36 == $85B3A0 && PoseRec_3B == $85B3F0

; ----------------------------------------------------------------------------
; bank $AF: normal-legs dash tiles (6 x $200 bytes)
; ----------------------------------------------------------------------------
org $AFEC80
AirDashGfx_A:
        db $00, $00, $03, $03, $0E, $0E, $19, $11, $3C, $3F, $59, $4D, $73, $7A, $66, $75
        db $00, $00, $03, $03, $0E, $0D, $10, $1F, $24, $24, $6B, $6B, $54, $76, $69, $6D
        db $00, $00, $80, $80, $F0, $70, $28, $E8, $78, $08, $9B, $8B, $0C, $C4, $6B, $DB
        db $00, $00, $80, $80, $70, $F0, $18, $38, $88, $F8, $8B, $FB, $C4, $FF, $DB, $DC
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $80, $7E, $7E, $E9, $99
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $80, $7E, $FE, $F9, $8F
        db $66, $7E, $5B, $65, $7B, $45, $7A, $46, $24, $3C, $18, $18, $00, $00, $00, $00
        db $7E, $7E, $65, $65, $45, $45, $46, $46, $3C, $3C, $18, $18, $00, $00, $00, $00
        db $07, $07, $00, $00, $00, $00, $01, $01, $07, $06, $09, $09, $0A, $0A, $0B, $0B
        db $07, $07, $00, $00, $00, $00, $01, $01, $07, $06, $09, $0F, $0A, $0D, $0B, $0C
        db $D7, $D7, $EA, $E9, $DA, $B1, $32, $19, $3F, $1F, $56, $36, $F7, $F7, $7F, $3F
        db $D7, $EF, $EF, $F8, $FF, $90, $FF, $10, $FF, $1F, $F6, $19, $F7, $F8, $3F, $F8
        db $E0, $E0, $80, $80, $80, $80, $80, $80, $C0, $C0, $F0, $30, $78, $08, $BE, $86
        db $E0, $E0, $80, $80, $80, $80, $80, $80, $C0, $C0, $30, $F0, $08, $F8, $86, $7E
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $30, $30, $68, $58
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $30, $30, $58, $58
        db $00, $00, $03, $03, $0C, $0C, $1B, $11, $22, $36, $65, $64, $5B, $58, $57, $40
        db $00, $00, $03, $03, $0F, $0C, $1F, $11, $3E, $23, $7C, $67, $65, $66, $6B, $6C
        db $00, $00, $80, $80, $E0, $60, $70, $10, $B8, $88, $9B, $0B, $DC, $44, $FB, $3B
        db $00, $00, $80, $80, $E0, $60, $10, $F0, $88, $78, $0B, $FB, $C4, $7F, $FB, $3C
        db $1C, $17, $3F, $23, $3F, $2D, $33, $33, $2D, $2C, $3D, $3C, $3B, $39, $16, $12
        db $14, $17, $22, $23, $2D, $2D, $33, $3F, $2C, $33, $3C, $23, $39, $27, $12, $1E
        db $0F, $0F, $0A, $0C, $15, $19, $1D, $11, $1D, $11, $15, $19, $29, $39, $E7, $DF
        db $0F, $0F, $0C, $0D, $19, $1B, $11, $13, $11, $13, $19, $1B, $39, $3F, $DF, $DF
        db $00, $00, $03, $03, $0D, $0D, $17, $17, $1F, $1F, $17, $16, $0F, $0C, $03, $03
        db $00, $00, $03, $03, $0D, $0E, $1F, $1E, $17, $16, $1E, $1F, $0C, $0F, $03, $03
        db $04, $04, $E2, $E2, $DF, $DF, $ED, $28, $D9, $C9, $FE, $01, $FF, $1F, $E0, $E0
        db $04, $04, $E2, $E2, $DF, $3F, $2F, $18, $CF, $39, $07, $F8, $1F, $FF, $E0, $E0
        db $00, $20, $00, $20, $00, $30, $00, $30, $10, $28, $10, $29, $30, $4B, $32, $4D
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $80, $44, $88, $74, $70, $88, $E0, $10, $80, $62, $F0, $08, $00, $FE, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
org $AFEE80
AirDashGfx_B:
        db $55, $79, $4F, $75, $3E, $2D, $14, $1F, $28, $3F, $72, $7F, $BC, $BE, $B7, $B7
        db $7B, $7B, $74, $75, $2C, $2D, $14, $1F, $30, $2F, $72, $5F, $B9, $CF, $B7, $FF
        db $CB, $AB, $DB, $9B, $4C, $2C, $57, $73, $6B, $69, $FF, $FC, $FA, $F8, $BD, $B9
        db $BB, $BC, $AB, $AC, $BC, $BF, $F3, $FF, $E9, $F7, $FD, $C2, $F9, $86, $BB, $C5
        db $95, $94, $BD, $9C, $FD, $FC, $9F, $9E, $F9, $F7, $AC, $B3, $EC, $F3, $D9, $D7
        db $F4, $9B, $FC, $93, $FC, $F3, $9E, $9F, $F7, $F7, $B3, $F3, $F3, $B3, $D7, $37
        db $80, $80, $80, $80, $80, $80, $80, $80, $00, $00, $80, $80, $80, $80, $00, $00
        db $80, $80, $80, $80, $80, $80, $80, $80, $00, $00, $80, $80, $80, $80, $00, $00
        db $07, $07, $05, $05, $02, $02, $03, $02, $07, $07, $0B, $0B, $17, $17, $1F, $1F
        db $07, $04, $05, $06, $02, $03, $02, $03, $07, $07, $0B, $0C, $17, $18, $1F, $1F
        db $BB, $8B, $DD, $C5, $DE, $C6, $3F, $03, $FE, $C2, $BD, $BD, $DF, $C7, $FF, $FF
        db $8B, $7C, $C5, $3E, $C6, $3F, $03, $FF, $C2, $FF, $BD, $7E, $C7, $3C, $FF, $FF
        db $DF, $C9, $FF, $D1, $2E, $22, $F6, $F2, $EC, $E4, $D8, $C8, $B0, $90, $E0, $E0
        db $C9, $3F, $D1, $3F, $22, $FE, $F2, $CE, $E4, $1C, $C8, $38, $90, $70, $E0, $E0
        db $A4, $DC, $E4, $9C, $E4, $9C, $F4, $FC, $C8, $C8, $64, $64, $64, $64, $C8, $C8
        db $DC, $DC, $9C, $9C, $9C, $9C, $FC, $FC, $C8, $B8, $64, $9C, $64, $9C, $C8, $B8
        db $7F, $53, $7F, $45, $3E, $2D, $14, $1F, $28, $3F, $72, $7F, $BD, $BF, $B7, $B7
        db $47, $6B, $6C, $55, $3C, $2D, $14, $1F, $30, $2F, $72, $5F, $B8, $CF, $B7, $FF
        db $DB, $7B, $7B, $7B, $7C, $7C, $37, $73, $6B, $69, $7F, $7C, $FA, $F8, $BD, $B9
        db $FB, $7C, $EB, $EC, $EC, $EF, $F3, $BF, $E9, $F7, $FD, $C2, $F9, $86, $BB, $C5
        db $40, $C0, $C0, $40, $A0, $60, $F0, $F0, $50, $30, $50, $30, $50, $30, $00, $00
        db $C0, $C0, $40, $40, $60, $60, $F0, $F0, $F0, $10, $F0, $10, $F0, $10, $00, $00
        db $75, $89, $F5, $09, $7B, $82, $FA, $FD, $1D, $1F, $1B, $16, $26, $23, $00, $00
        db $89, $8F, $09, $0F, $82, $8E, $FD, $FD, $1F, $1F, $1F, $12, $3F, $22, $00, $00
        db $0E, $0E, $3B, $39, $78, $7F, $BF, $EC, $BF, $FF, $E7, $E4, $4A, $4D, $3F, $3F
        db $0E, $0E, $35, $35, $4F, $4F, $A4, $A4, $A7, $A7, $BC, $FC, $7D, $7D, $3F, $3F
        db $00, $00, $80, $80, $78, $F8, $E0, $C8, $60, $60, $D0, $E0, $78, $F8, $80, $80
        db $00, $00, $80, $80, $F8, $F8, $F8, $C0, $B8, $A0, $F8, $C0, $F8, $F8, $80, $80
        db $00, $00, $00, $00, $00, $01, $01, $00, $01, $02, $03, $04, $00, $0F, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $0E, $11, $1D, $62, $7F, $80, $FF, $00, $FF, $00, $FF, $00, $00, $FF, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
org $AFF080
AirDashGfx_C:
        db $01, $01, $06, $06, $0D, $08, $11, $1B, $32, $32, $2D, $2C, $2B, $20, $3F, $29
        db $01, $01, $07, $06, $0F, $08, $1F, $11, $3E, $33, $32, $33, $35, $36, $23, $35
        db $C0, $C0, $70, $30, $B8, $88, $5C, $44, $CD, $05, $EF, $23, $FF, $1B, $ED, $BD
        db $C0, $C0, $F0, $30, $88, $F8, $44, $BC, $05, $FD, $E3, $3F, $FB, $1F, $FD, $BF
        db $0E, $0E, $3D, $3D, $5E, $7E, $F6, $96, $1E, $8E, $9F, $0F, $75, $96, $E7, $E4
        db $0E, $0E, $3D, $33, $7E, $51, $F6, $99, $FE, $09, $FF, $0F, $F6, $16, $E4, $E4
        db $2F, $2F, $3B, $3A, $2F, $2C, $17, $14, $0C, $0F, $03, $03, $00, $00, $00, $00
        db $2F, $33, $3A, $26, $2C, $34, $14, $1C, $0F, $0F, $03, $03, $00, $00, $00, $00
        db $80, $80, $00, $00, $00, $00, $F0, $F0, $FF, $4F, $FF, $80, $FF, $80, $CF, $40
        db $80, $80, $00, $00, $00, $00, $F0, $F0, $CF, $7F, $80, $FF, $80, $FF, $40, $FF
        db $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $F0, $B0, $F8, $48, $FC, $44
        db $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $B0, $F0, $48, $F8, $44, $FC
        db $00, $00, $80, $80, $40, $40, $A0, $E0, $60, $A0, $E0, $20, $A0, $60, $40, $C0
        db $00, $00, $80, $80, $40, $C0, $E0, $E0, $A0, $A0, $20, $20, $60, $60, $C0, $C0
        db $D0, $30, $E8, $18, $64, $9C, $EA, $9A, $F6, $F6, $5E, $5E, $7A, $7A, $24, $24
        db $30, $30, $18, $18, $9C, $9C, $9A, $9E, $F6, $FA, $5E, $62, $7A, $46, $24, $3C
        db $01, $01, $07, $07, $0C, $08, $1E, $1F, $2C, $26, $39, $3D, $33, $3A, $2A, $3C
        db $01, $01, $07, $06, $08, $0F, $12, $12, $35, $35, $2A, $3B, $34, $36, $3D, $3D
        db $C0, $C0, $78, $38, $94, $F4, $3C, $84, $CD, $C5, $87, $63, $37, $EF, $E5, $D5
        db $C0, $C0, $38, $F8, $0C, $9C, $44, $7C, $C5, $FD, $63, $7F, $EF, $EF, $DD, $DF
        db $07, $06, $1A, $0A, $1A, $12, $2B, $32, $3A, $23, $39, $25, $3D, $31, $CF, $FE
        db $07, $06, $0B, $1E, $13, $16, $33, $36, $23, $26, $25, $27, $31, $33, $FE, $FF
        db $F0, $F0, $E8, $98, $D8, $E8, $E8, $38, $10, $38, $58, $38, $00, $00, $00, $00
        db $F0, $F0, $98, $98, $E8, $E8, $F8, $38, $F8, $10, $F8, $18, $00, $00, $00, $00
        db $00, $7F, $07, $18, $03, $04, $01, $02, $01, $02, $00, $01, $00, $01, $00, $01
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $00, $C0, $C0, $20, $E0, $10, $F0, $08, $F0, $08, $F8, $04, $F8, $04
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $F8, $08, $16, $04, $3A, $02, $05, $02, $05, $02, $01, $00, $03, $00, $02
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $00, $00, $00, $20, $00, $08, $00, $00, $00, $01, $00, $08, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
org $AFF280
AirDashGfx_D:
        db $3F, $22, $1F, $16, $0A, $0F, $04, $07, $09, $0F, $06, $07, $0B, $0B, $19, $1C
        db $36, $2A, $1E, $16, $0A, $0F, $00, $07, $09, $0F, $04, $07, $0F, $0B, $1F, $18
        db $BE, $BE, $3F, $BF, $1E, $BE, $3F, $B1, $27, $A0, $DB, $D8, $DF, $DD, $6A, $EA
        db $76, $F5, $77, $F4, $7E, $DF, $71, $FF, $60, $FF, $58, $E7, $DD, $E3, $EB, $76
        db $62, $23, $E1, $61, $FC, $BC, $A7, $A3, $B2, $B3, $7B, $4A, $84, $8F, $97, $0F
        db $23, $E3, $61, $E1, $FC, $BC, $E3, $BF, $F3, $BE, $FB, $4E, $FF, $84, $FF, $07
        db $DF, $DF, $A1, $61, $A2, $63, $25, $E5, $45, $C5, $82, $82, $01, $01, $00, $00
        db $DF, $DF, $61, $61, $63, $62, $E5, $E7, $C5, $C6, $82, $83, $01, $01, $00, $00
        db $F9, $38, $FF, $1E, $7F, $1E, $B9, $89, $DE, $CE, $EC, $E4, $7C, $74, $F8, $F8
        db $38, $E7, $1E, $F1, $1E, $F9, $89, $7F, $CE, $3E, $E4, $1C, $74, $8C, $F8, $F8
        db $CE, $42, $EE, $62, $B7, $B1, $7B, $79, $DD, $DD, $35, $35, $0E, $0E, $00, $00
        db $42, $FE, $62, $DE, $B1, $CF, $79, $87, $DD, $E3, $35, $3B, $0E, $0E, $00, $00
        db $2F, $19, $BF, $71, $E7, $C1, $FD, $FD, $FD, $FD, $9F, $9F, $65, $65, $1B, $1B
        db $F9, $0F, $F1, $3F, $C1, $FF, $FD, $03, $FD, $03, $9F, $E2, $65, $7E, $1B, $1B
        db $BF, $CF, $EE, $9E, $FE, $9E, $7C, $5C, $31, $31, $0E, $0E, $00, $00, $00, $00
        db $CF, $CF, $9E, $99, $9E, $91, $5C, $53, $31, $3F, $0E, $0E, $00, $00, $00, $00
        db $27, $3A, $1F, $16, $0A, $0F, $04, $07, $09, $0F, $06, $07, $0B, $0B, $19, $1C
        db $3A, $3A, $16, $16, $0A, $0F, $00, $07, $09, $0F, $04, $07, $0F, $0B, $1F, $18
        db $EE, $CE, $27, $97, $2E, $BE, $3F, $B1, $67, $E0, $5B, $58, $DF, $DD, $6A, $EA
        db $56, $D5, $5F, $DC, $7E, $FF, $71, $FF, $60, $FF, $D8, $E7, $DD, $E3, $EB, $76
        db $62, $9C, $F2, $0C, $75, $89, $B2, $C2, $00, $00, $00, $00, $00, $00, $00, $00
        db $9C, $9F, $0C, $0F, $89, $8F, $C3, $CE, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $E1, $20, $51, $10, $2B, $1B, $24, $1F, $20, $3F, $40, $3F, $40, $7F, $80
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $FC, $02, $FC, $02, $FE, $01, $FE, $01, $FE, $01, $FE, $01, $FC, $02, $FC, $02
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $FF, $00, $FF, $00, $FF, $00, $FF, $00, $FF, $00, $FF, $00, $FE, $01, $00, $FE
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $F8, $05, $F2, $0D, $FC, $02, $F8, $04, $F0, $08, $C0, $30, $00, $C0, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
org $AFF480
AirDashGfx_E:
        db $01, $01, $06, $06, $0D, $08, $11, $1B, $32, $32, $2D, $2C, $2B, $20, $3F, $29
        db $01, $01, $07, $06, $0F, $08, $1F, $11, $3E, $33, $32, $33, $35, $36, $23, $35
        db $C0, $C0, $70, $30, $B8, $88, $5C, $44, $CD, $05, $EF, $23, $FF, $1B, $ED, $BD
        db $C0, $C0, $F0, $30, $88, $F8, $44, $BC, $05, $FD, $E3, $3F, $FB, $1F, $FD, $BF
        db $0E, $0E, $3D, $3D, $5E, $7E, $F6, $96, $1E, $8E, $9F, $0F, $75, $96, $E7, $E4
        db $0E, $0E, $3D, $33, $7E, $51, $F6, $99, $FE, $09, $FF, $0F, $F6, $16, $E4, $E4
        db $1F, $1F, $6E, $6E, $BF, $B9, $FE, $FE, $BF, $B0, $7F, $60, $1F, $1F, $00, $00
        db $1F, $1F, $6E, $71, $F9, $F0, $BE, $B1, $F0, $FF, $60, $7F, $1F, $1F, $00, $00
        db $80, $80, $00, $00, $00, $00, $F0, $F0, $FF, $4F, $FF, $80, $FF, $80, $CF, $40
        db $80, $80, $00, $00, $00, $00, $F0, $F0, $CF, $7F, $80, $FF, $80, $FF, $40, $FF
        db $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $F0, $B0, $F8, $48, $FC, $44
        db $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $B0, $F0, $48, $F8, $44, $FC
        db $00, $00, $80, $80, $40, $40, $A0, $E0, $60, $A0, $E0, $20, $A0, $60, $40, $C0
        db $00, $00, $80, $80, $40, $C0, $E0, $E0, $A0, $A0, $20, $20, $60, $60, $C0, $C0
        db $D0, $30, $E8, $18, $64, $9C, $EA, $9A, $F6, $F6, $5E, $5E, $7A, $7A, $24, $24
        db $30, $30, $18, $18, $9C, $9C, $9A, $9E, $F6, $FA, $5E, $62, $7A, $46, $24, $3C
        db $01, $01, $07, $07, $0C, $08, $1E, $1F, $2C, $26, $39, $3D, $33, $3A, $2A, $3C
        db $01, $01, $07, $06, $08, $0F, $12, $12, $35, $35, $2A, $3B, $34, $36, $3D, $3D
        db $C0, $C0, $78, $38, $94, $F4, $3C, $84, $CD, $C5, $87, $63, $37, $EF, $E5, $D5
        db $C0, $C0, $38, $F8, $0C, $9C, $44, $7C, $C5, $FD, $63, $7F, $EF, $EF, $DD, $DF
        db $07, $06, $1A, $0A, $1A, $12, $2B, $32, $3A, $23, $39, $25, $3D, $31, $CF, $FE
        db $07, $06, $0B, $1E, $13, $16, $33, $36, $23, $26, $25, $27, $31, $33, $FE, $FF
        db $F0, $F0, $E8, $98, $D8, $E8, $E8, $38, $10, $38, $58, $38, $00, $00, $00, $00
        db $F0, $F0, $98, $98, $E8, $E8, $F8, $38, $F8, $10, $F8, $18, $00, $00, $00, $00
        db $00, $7F, $07, $18, $03, $04, $01, $02, $01, $02, $00, $01, $00, $01, $00, $01
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $00, $C0, $C0, $20, $E0, $10, $F0, $08, $F0, $08, $F8, $04, $F8, $04
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $F8, $08, $16, $04, $3A, $02, $05, $02, $05, $02, $01, $00, $03, $00, $02
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $00, $00, $00, $20, $00, $08, $00, $00, $00, $01, $00, $08, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
assert pc() <= $AFF700                 ; stay clear of the Air Dash OAM data
org $AFF8C0
AirDashGfx_F:
        db $3F, $22, $FF, $F6, $4A, $5F, $CC, $47, $E9, $0F, $FE, $FF, $03, $03, $00, $00
        db $36, $2A, $FE, $F6, $7A, $CF, $78, $C7, $39, $CF, $FC, $FF, $03, $03, $00, $00
        db $BE, $BE, $3F, $BF, $1E, $BE, $3F, $B1, $27, $A0, $DB, $D8, $DF, $DD, $2A, $2A
        db $76, $F5, $77, $F4, $7E, $DF, $71, $FF, $60, $FF, $58, $E7, $DD, $E3, $2B, $36
        db $62, $23, $E1, $61, $FC, $BC, $A7, $A3, $B2, $B3, $7B, $4A, $84, $8F, $97, $0F
        db $23, $E3, $61, $E1, $FC, $BC, $E3, $BF, $F3, $BE, $FB, $4E, $FF, $84, $FF, $07
        db $1F, $1F, $01, $01, $02, $03, $05, $05, $05, $05, $02, $02, $01, $01, $00, $00
        db $1F, $1F, $01, $01, $03, $02, $05, $07, $05, $06, $02, $03, $01, $01, $00, $00
        db $F9, $38, $FF, $1E, $7F, $1E, $B9, $89, $DE, $CE, $EC, $E4, $7C, $74, $F8, $F8
        db $38, $E7, $1E, $F1, $1E, $F9, $89, $7F, $CE, $3E, $E4, $1C, $74, $8C, $F8, $F8
        db $CE, $42, $EE, $62, $B7, $B1, $7B, $79, $DD, $DD, $35, $35, $0E, $0E, $00, $00
        db $42, $FE, $62, $DE, $B1, $CF, $79, $87, $DD, $E3, $35, $3B, $0E, $0E, $00, $00
        db $2F, $19, $BF, $71, $E7, $C1, $FD, $FD, $FD, $FD, $9F, $9F, $65, $65, $1B, $1B
        db $F9, $0F, $F1, $3F, $C1, $FF, $FD, $03, $FD, $03, $9F, $E2, $65, $7E, $1B, $1B
        db $0E, $0E, $3B, $39, $78, $7F, $BF, $EC, $BF, $FF, $E7, $E4, $4A, $4D, $3F, $3F
        db $0E, $0E, $35, $35, $4F, $4F, $A4, $A4, $A7, $A7, $BC, $FC, $7D, $7D, $3F, $3F
        db $27, $3A, $FF, $F6, $4A, $5F, $CC, $47, $E9, $0F, $FE, $FF, $03, $03, $00, $00
        db $3A, $3A, $F6, $F6, $7A, $CF, $78, $C7, $39, $CF, $FC, $FF, $03, $03, $00, $00
        db $EE, $CE, $27, $97, $2E, $BE, $3F, $B1, $67, $E0, $5B, $58, $DF, $DD, $2A, $2A
        db $56, $D5, $5F, $DC, $7E, $FF, $71, $FF, $60, $FF, $D8, $E7, $DD, $E3, $2B, $36
        db $62, $9C, $F2, $0C, $75, $89, $B2, $C2, $00, $00, $00, $00, $00, $00, $00, $00
        db $9C, $9F, $0C, $0F, $89, $8F, $C3, $CE, $00, $00, $00, $00, $00, $00, $00, $00
        db $00, $00, $80, $80, $78, $F8, $E0, $C8, $60, $60, $D0, $E0, $78, $F8, $80, $80
        db $00, $00, $80, $80, $F8, $F8, $F8, $C0, $B8, $A0, $F8, $C0, $F8, $F8, $80, $80
        db $00, $E1, $20, $51, $10, $2B, $1B, $24, $1F, $20, $3F, $40, $3F, $40, $7F, $80
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $FC, $02, $FC, $02, $FE, $01, $FE, $01, $FE, $01, $FE, $01, $FC, $02, $FC, $02
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $FF, $00, $FF, $00, $FF, $00, $FF, $00, $FF, $00, $FF, $00, $FE, $01, $00, $FE
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        db $F8, $05, $F2, $0D, $FC, $02, $F8, $04, $F0, $08, $C0, $30, $00, $C0, $00, $00
        db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
assert pc() <= $AFFB00                 ; stay clear of the lookup routine

; ----------------------------------------------------------------------------
; BETTER SUB-TANK hook sites (weapons menu, bank $80)
; ----------------------------------------------------------------------------
org $80C752                       ; was: A9 02 85 11   LDA #$02 / STA $11
        JSL SubTank_SetRate       ; (the RTS at $80C756 is untouched)
org $80C7B8                       ; was: AD 9A 33 38 ED CF 6B
        JSL SubTank_FullCheck     ; LDA $339A / SEC / SBC $6BCF
        NOP : NOP : NOP           ; (the BEQ at $80C7BF is untouched)

; Replace the SA-1 gate body; last byte of the original 11-byte region becomes
; the RTS stub used by the fail / air-dash-success paths.
org $81FF60
        JML NewGateCheck
        padbyte $EA
        pad $81FF6A
        RTS

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $23, $D2, $DC, $2D                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
