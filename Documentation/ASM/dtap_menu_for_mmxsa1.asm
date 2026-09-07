; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "D-TAP DASH Toggle" Patch
;  Apply after: SA-1, Air Dash, Faster Dialog Box, Skip Boss Intro
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off dtap_menu_for_mmxsa1.asm rom.sfc
;
;  WHAT THIS PATCH DOES
;    Adds a new "D-TAP DASH" option to the Option Mode menu (between MENU
;    and SOUND MODE). The option controls whether the double-tap-to-dash
;    input is enabled during gameplay.
;
;  UI
;    - Extends the Option Mode cursor list from 10 entries to 11.
;    - Inserts the new row at index 6; STEREO/MONAURAL, BGM, S.E. and
;      EXIT shift down by one.
;    - Draws the label "D-TAP DASH" and the value "ON "/"OFF" as two
;      independent messages so each can be centered under its own
;      column (label under KEY CONFIG, value under the button icons).
;    - Supports the normal dim/bright highlighting used by the rest of
;      the menu.
;    - Left/Right while the cursor is on the new row toggles the setting
;      and redraws the row immediately.
;
;  STORAGE
;    - The setting is stored in battery-backed SA-1 BW-RAM at $40FF01
;      (0 = OFF, 1 = ON). A magic byte at $40FF00 is used for lazy
;      first-boot initialization so a fresh cartridge defaults to OFF.
;    - The location sits far past the region of BW-RAM used by the SA-1
;      patch for work RAM and the live key-mapping table.
;
;  GAMEPLAY
;    - The SA-1 patch replaced the vanilla double-tap sanity check with
;      a gate that only proceeds when I-RAM $3348 or $3208 is non-zero.
;      Neither flag is ever set by the game, so the double-tap detector
;      (still intact at $819723-$819756) was unreachable.
;    - This patch adds the new option flag as a third OR-condition on
;      that gate. When the option is ON the detector runs normally;
;      when OFF the gate returns early and double-tap dash is disabled.
;
;  FREE SPACE
;    - Bank $86 ($86FB80+) -- new message data and the relocated 11-entry
;      row-ID table.
;    - Bank $80 ($80FEB8+) -- relocated 11-entry jump table, text-pointer
;      helpers, cursor erase/select routines, init loop and toggle
;      handler.
;    - Bank $84 ($84F1C4+) -- SRAM flag reader and the expanded gate
;      check (callable via JSL from any bank).
;
;  HOOKS (in-place edits inside the existing Option Mode code)
;    $80EAEF  initial draw loop           -> JSR NewInitLoop
;    $80EB41  screen fade-in call         -> JSR DTapInitHook
;    $80EB86  cursor wrap-down bound      -> LDA #$0A
;    $80EB8E  cursor wrap-up bound        -> CMP #$0B
;    $80EBA2  erase-old-row block         -> JSR ErasePassNew
;    $80EBBF  draw-new-row block          -> JSR SelectPassNew
;    $80EBEA  dispatch jump-table pointer -> dw NewJumpTable
;    $81FF60  SA-1 double-tap gate        -> JML NewGateCheck
; ============================================================================

lorom

; ----------------------------------------------------------------------------
; Constants
; ----------------------------------------------------------------------------
!MSG_DRAW_BY_ID   = $89E3        ; A = message ID -> looks up pointer, draws it
!MSG_DRAW_RAW     = $89F5        ; entry after the ID->pointer lookup;
                                  ; caller must set $10/$11 to a message
                                  ; pointer in bank $86 (DB=$86)
!FRAME_SYNC       = $8100        ; yields one frame (cooperative multitasking)
!OPTION_LOOP      = $EB4A        ; main "wait for cursor input" loop entry
!STEREO_FLAG      = $7EFFCA      ; $F7 = STEREO, else MONAURAL (existing var)

; Battery-backed BW-RAM (bank $40)
!SRAM_MAGIC       = $40FF00      ; sentinel; $A5 once initialized
!SRAM_DTAP_FLAG   = $40FF01      ; 0 = OFF (default), 1 = ON

; ----------------------------------------------------------------------------
; New text data (bank $86 free space)
;
; Two independent messages per state so the label and value can be
; centered on different columns. Row 0 of the SOUND MODE column
; (TYPE $0A) places the text below MENU and above SOUND MODE.
;
; KEY CONFIG items are centered on column 11 -> "D-TAP DASH" (10 chars)
; starts at column 6. Button icons are centered on column ~21 ->
; "OFF"/"ON " (3 chars, space-padded) start at column 20 ($14).
; ----------------------------------------------------------------------------
org $86FB80
DTapLabelDim:
        db $0A, $20, $06, $0A
        db "D-TAP DASH"
        db $00

DTapLabelBright:
        db $0A, $2C, $06, $0A
        db "D-TAP DASH"
        db $00

DTapValueOffDim:
        db $03, $20, $14, $0A
        db "OFF"
        db $00

DTapValueOffBright:
        db $03, $2C, $14, $0A
        db "OFF"
        db $00

DTapValueOnDim:
        db $03, $20, $14, $0A
        db "ON "
        db $00

DTapValueOnBright:
        db $03, $2C, $14, $0A
        db "ON "
        db $00

; ----------------------------------------------------------------------------
; Relocated 11-entry row-ID table (original was the 10-entry table at
; $86BCDB). Index 6 is a placeholder; the init loop skips it and the
; dedicated draw routines handle the new row instead.
; ----------------------------------------------------------------------------
NewRowTable:
        db $1F, $1D, $2D, $21, $23, $25, $1F, $40, $29, $2B, $27

; ----------------------------------------------------------------------------
; Relocated 11-entry jump table (original was the 10-entry inline table
; at $80EBEC). Must stay in bank $80 because the dispatch uses an
; indirect JMP.
; ----------------------------------------------------------------------------
org $80FEB8
NewJumpTable:
        dw $EC00, $EC00, $EC00, $EC00, $EC00, $EC00    ; 0-5: KEY CONFIG
        dw DTapToggleHandler                           ; 6: D-TAP DASH (new)
        dw $EC99                                       ; 7: STEREO/MONAURAL
        dw $ECE1                                       ; 8: BGM
        dw $ED25                                       ; 9: S.E.
        dw $ED84                                       ; 10: EXIT

; Pointer table for the six message variants (label dim/bright + value
; off-dim/off-bright/on-dim/on-bright). Long addressing is required
; because callers run with DB=$86.
CombinedPtrTable:
        dw DTapLabelDim, DTapLabelBright
        dw DTapValueOffDim, DTapValueOffBright
        dw DTapValueOnDim, DTapValueOnBright

; X = table index*2 on entry.
SetTextPtr:
        LDA.l CombinedPtrTable,X
        STA $10
        LDA.l CombinedPtrTable+1,X
        STA $11
        RTS

; X = label index (0 or 2), Y = value index (4/6/8/10).
; MSG_DRAW_RAW clobbers Y, so the value index is preserved on the stack.
DrawLabelAndValue:
        PHY
        JSR SetTextPtr
        JSR !MSG_DRAW_RAW
        PLY
        TYA
        TAX
        JSR SetTextPtr
        JSR !MSG_DRAW_RAW
        RTS

; X = label index (0 or 2), A = flag (0/1).
; value_index = 4 + label_index + flag*4
DrawDTapState:
        ASL A
        ASL A
        STA $00
        CLC
        TXA
        ADC $00
        ADC #$04
        TAY
        JSR DrawLabelAndValue
        RTS

; ----------------------------------------------------------------------------
; Toggle handler (jump-table entry 6).
; Waits for Left/Right (bits 0-1 of $AC), flips the SRAM flag, redraws
; the row in its selected/bright state, then returns to the main menu
; input loop. Modeled on the existing STEREO/MONAURAL handler at $80EC99.
; ----------------------------------------------------------------------------
DTapToggleHandler:
        LDA $AC
        AND #$03
        BNE .toggle
        JSR !FRAME_SYNC
        JMP !OPTION_LOOP
.toggle:
        JSL ReadDTapFlag
        EOR #$01
        STA.l !SRAM_DTAP_FLAG
        LDX.b #2
        JSR DrawDTapState
        JSR !FRAME_SYNC
        JMP !OPTION_LOOP

; ----------------------------------------------------------------------------
; Cursor "erase old row" replacement (original $80EBA2-$80EBBE).
; Special-cases index 6 for the new option; otherwise falls through to
; the original row-ID / stereo logic with renumbered indices.
; ----------------------------------------------------------------------------
ErasePassNew:
        LDA.l $7EFF81
        TAX
        CPX #$06
        BNE .not_ours
        JSL ReadDTapFlag
        LDX.b #0
        JSR DrawDTapState
        RTS
.not_ours:
        LDA.w NewRowTable,X
        CPX #$07
        BNE .draw_msg
        LDA.l !STEREO_FLAG
        CMP #$F7
        BEQ .stereo_dim
        LDA #$42
        BRA .draw_msg
.stereo_dim:
        LDA #$40
.draw_msg:
        JSR !MSG_DRAW_BY_ID
        RTS

; ----------------------------------------------------------------------------
; Cursor "draw newly-selected row" replacement (original $80EBBF-$80EBDC).
; ----------------------------------------------------------------------------
SelectPassNew:
        LDA.l $7EFF80
        TAX
        CPX #$06
        BNE .not_ours
        JSL ReadDTapFlag
        LDX.b #2
        JSR DrawDTapState
        RTS
.not_ours:
        LDA.w NewRowTable,X
        INC
        CPX #$07
        BNE .draw_msg
        LDA.l !STEREO_FLAG
        CMP #$F7
        BEQ .stereo_bright
        LDA #$43
        BRA .draw_msg
.stereo_bright:
        LDA #$41
.draw_msg:
        JSR !MSG_DRAW_BY_ID
        RTS

; ----------------------------------------------------------------------------
; Initial screen-open draw loop (original was the 13-byte inline loop
; at $80EAEF). Draws all 11 rows except index 6, which is handled by
; DTapInitHook so a placeholder icon is never written into the sprite
; character budget.
; ----------------------------------------------------------------------------
NewInitLoop:
        LDX #$0A
.loop:
        CPX #$06
        BEQ .skip
        PHX
        LDA.w NewRowTable,X
        JSR !MSG_DRAW_BY_ID
        PLX
.skip:
        DEX
        BPL .loop
        RTS

; ----------------------------------------------------------------------------
; Post-init draw for the new row (dim state). Replaces the original
; "JSR $8975" fade-in call at $80EB41 (same size). Calls the fade-in
; first, then draws the label+value pair.
; ----------------------------------------------------------------------------
DTapInitHook:
        JSR $8975
        JSL ReadDTapFlag
        LDX.b #0
        JSR DrawDTapState
        RTS

; ============================================================================
;  In-place edits to Option Mode ($80EAD1-$80EC00)
; ============================================================================

; Replace the original 13-byte init draw loop
org $80EAEF
        JSR NewInitLoop
        padbyte $EA
        pad $80EAFC

; Hook the fade-in call (3 bytes)
org $80EB41
        JSR DTapInitHook

; Cursor wrap-down: 10 items -> 11
org $80EB86
        LDA #$0A

; Cursor wrap-up: 10 items -> 11
org $80EB8E
        CMP #$0B

; Replace the 29-byte erase-old-row block
org $80EBA2
        JSR ErasePassNew
        padbyte $EA
        pad $80EBBF

; Replace the 30-byte draw-new-row block
org $80EBBF
        JSR SelectPassNew
        padbyte $EA
        pad $80EBDD

; Point the dispatch JMP at the new 11-entry table
org $80EBEA
        dw NewJumpTable

; ============================================================================
;  SRAM flag reader (bank $84 free space)
;  Lazily initializes the magic byte and flag to OFF on first access.
; ============================================================================
org $84F1C4
ReadDTapFlag:
        LDA.l !SRAM_MAGIC
        CMP #$A5
        BEQ .valid
        LDA #$A5
        STA.l !SRAM_MAGIC
        LDA #$00
        STA.l !SRAM_DTAP_FLAG
.valid:
        LDA.l !SRAM_DTAP_FLAG
        RTL

; ============================================================================
;  Expanded double-tap gate
;
;  The SA-1 patch's gate at $81FF60 only proceeds when I-RAM $3348 or
;  $3208 is non-zero. This routine adds the option flag as a third
;  OR-condition. On success it continues into the original tail at
;  $81FF6B; on failure it returns via a one-byte RTS stub that lives
;  inside bank $81 so the program bank is restored correctly.
; ============================================================================
NewGateCheck:
        LDA $3348
        BNE .proceed
        LDA $3208
        BNE .proceed
        JSL ReadDTapFlag
        BEQ .fail
.proceed:
        JML $81FF6B
.fail:
        JML $81FF6A

; Replace the SA-1 gate body; last byte of the original 11-byte region
; becomes the RTS stub used by the fail path.
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
org $80FFDC
        db $A5, $EC, $5A, $13                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
