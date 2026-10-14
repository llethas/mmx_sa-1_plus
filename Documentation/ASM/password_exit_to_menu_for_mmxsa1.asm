; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "PASS WORD: EXIT to menu" Patch
;  Apply after (in this order):
;    mmxsa1_double_tap_disabled.ips
;    chameleon_sting_ride_armor_fix_for_mmxsa1.ips
;    better_walljump_for_mmxsa1.ips
;    better_dialog_box_for_mmxsa1.ips
;    skip_boss_intro_for_mmxsa1.ips
;    extra_options_for_mmxsa1.ips
;    option_mode_exit_to_menu_for_mmxsa1.ips
;    hadouken_for_mmxsa1.ips
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off password_exit_to_menu_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Renames the "END" button to "START" and adds an "EXIT" entry under it on the PASS WORD screen that the Main
;    Menu opens. The pointer arrow can be moved onto it like any other row:
;    DOWN from START goes to EXIT, UP from EXIT goes back to START, DOWN from
;    EXIT wraps to the first digit row, and UP from the first digit row
;    wraps to EXIT. START or Y (the buttons that confirm "START") on EXIT
;    fades out like the normal confirm does and returns directly to the Main
;    Menu, silently (the menu has no music). Digit editing and the START
;    button (submit password) are unchanged, and the EXIT row never reads or
;    writes the password.
;
;  SCOPE
;    The only caller of the PASS WORD input loop ($80:EF45) is the Main Menu
;    handler for row 1 ($80:9326). The password screens shown after beating a
;    boss use a different loop ($80:F07E) and are never touched.
;
; ############################################################################
; # PART 1 - How the screen works (and why this patch is so small)
; ############################################################################
;
;  The loop at $80:EF45 runs with DP = $3248 and a state byte in $01
;  (0 = init, 2 = fade in, 4 = input, 6 = fade out; the loop ends when DP $00
;  is cleared, which the fade-out state does through $80:DBEA).
;
;  Unlike Mega Man X2, the confirm button is not a sprite: "END" is BG3 text
;  (message $35, drawn at the end of the init state). The pointer arrow is the
;  sprite object $87:807E, and it is already written for more than one
;  button row: it reads the cursor row from DP $07 and
;        row 0-2 : Y = row * $30 + $26, X = column * $30 + $38  (digits)
;        row >= 3: Y = (row - 3) * $10 + $AB, X = $30            (buttons)
;  So row 3 is END ($AB = 171) and row 4 lands at $BB = 187, exactly 16 px
;  below it. Row 4 was simply never reachable, because the D-pad clamp at
;  $80:EFFE only lets $07 be 0-3. This patch:
;
;    1. Lets the clamp accept row 4.                      (2 bytes)
;    2. Draws "EXIT" in the same BG3 font as "END",
;       two tile rows below it (VRAM word $0AE7, row 23, col 7), and renames END to START, by drawing a
;       new message ($5C = "START" + "EXIT") instead of $35. The panel already
;       has room there and no new graphics are needed.
;    3. Hooks the confirm routine ($80:F038, the JSR to the password check
;       $80:F24C): on row 4 it does not check/copy any password, it sets a
;       "leave" marker and starts the game's own fade-out state ($01 := 6).
;       On any other row it just runs the original check.
;    4. Hooks the Main Menu handler right after the loop returns ($80:933C):
;       if the marker is set it returns to the Main Menu the same way
;       option_mode_exit_to_menu does ($38 = 2, $39-$3C = 0, then RTS out of
;       the handler), instead of continuing to the stage select. It also
;       restores the music tracker (see below).
;
; ############################################################################
; # PART 2 - Music, SRAM, RAM
; ############################################################################
;
;  MUSIC: the PASS WORD screen starts its own song ($28) and the confirm state
;    fades it out. The Main Menu has no music (the $1F logo jingle played by
;    the intro is over by then), so the exit hook sends NO sound command and
;    the menu stays silent. It only writes $1F back into the $7E:FFFD
;    "current song" tracker, so that the game's state when it leaves the menu
;    is the same as if the PASS WORD screen had never been opened.
;
;  SRAM / BW-RAM: this patch makes NO SRAM writes and reads none. The
;    saved password ($40:0100-$010B, read by the screen's init) and the
;    control scheme / EXTRA OPTIONS toggles ($40:0110+, $40:FF00+) are not
;    touched; the exit path skips the "copy digits to $7E:FFCB" step too, so
;    nothing the player typed before pressing EXIT leaks into the game.
;    Edited digits live only in the screen's DP ($3248+$18..$23), which
;    $80:DBEA clears when the screen fades out, as usual.
;
;  RAM: the marker is $00:0039, the menu sub-state. It is dead while the PASS
;    WORD loop runs (the Main Menu handler never returns to the menu state
;    machine in the original game), is set to $EE only by the EXIT press, and
;    is overwritten with 0 by the exit hook. (DP $3248 variables can't hold it:
;    $80:DBEA clears them on the way out.) The screen's DP is otherwise
;    unchanged.
;
; ############################################################################
; # PART 3 - Compatibility with the rest of the patch set
; ############################################################################
;
;  Free space used (all verified to be $FF in the fully patched ROM):
;    $80:FEED-FEF5   9 bytes. Free after Option Mode Exit ($80:FEE0-FEEC);
;                    Skip Boss Intro starts at $80:FF00.
;    $80:FF8E-FF99  12 bytes. Free between Skip Boss Intro's code
;                    (asserts <= $80FFA0) and the SA-1 JML stubs at $80FFA4.
;    $86:FE40-FE51  18 bytes. Free after Extra Options' strings (which end
;                    below $86FE39) and before the table at $86FFFA.
;    $86:91C3        message pointer slot $5C (Extra Options uses $44-$5B).
;    $AF:FCE0-FD4F  Free after the Air Dash code ($AFFCD6) and before Better
;                    Dialog Box's routines at $AFFE00.
;
;  Hijacked original bytes (each asserted below): $80:EFD1, $80:F000,
;  $80:F00B, $80:F038-F03A, $80:933C-933E. None are touched by any other
;  patch of the set. Extra Options hooks $80:930D/925D/9295/9278/9283/928C/
;  9237 in the same Main Menu code, Option Mode Exit hooks $80:934D, Skip
;  Boss Intro hooks $80:80B5 -- all different bytes. The hook at $80:933C
;  keeps the original "LDA #$02 / STA $D1 / STZ $D2 / STZ $D3 / JMP $94D5"
;  that follows it, so the normal "END" path (stage select) is unchanged.
;
;  Skip Boss Intro's scheduler hook only reacts while $D1 = 2 and $D2 = 2
;  (the stage-select boss intro) and so never fires on this screen.
; ============================================================================

lorom

; ############################################################################
; # Original code this patch relies on (asserted)
; ############################################################################

assert read1($80EFD0) == $A9 && read1($80EFD1) == $35 && read1($80EFD2) == $20   ; LDA #$35 / JSR $89E3
assert read1($80F000) == $C9 && read1($80F001) == $04 && read1($80F002) == $90   ; CMP #$04 / BCC
assert read1($80F00A) == $A9 && read1($80F00B) == $03 && read1($80F00C) == $85   ; LDA #$03 / STA $07
assert read1($80F038) == $20 && read1($80F039) == $4C && read1($80F03A) == $F2   ; JSR $F24C
assert read1($80F03B) == $D0 && read1($80F03C) == $26                            ; BNE $F063
assert read1($80F063) == $60                                                     ; RTS
assert read1($80933C) == $20 && read1($80933D) == $45 && read1($80933E) == $EF   ; JSR $EF45
assert read1($80933F) == $A9 && read1($809340) == $02                            ; LDA #$02
assert read1($8691C3) == $C5 && read1($8691C4) == $98                            ; free message slot $5C (filler)
assert read1($80FEED) == $FF && read1($80FEF5) == $FF                            ; free after OptionExit
assert read1($80FEEC) == $60                                                     ; OptionExit's RTS (option_mode_exit applied)
assert read1($80FF8E) == $FF && read1($80FF99) == $FF
assert read1($86FE40) == $FF && read1($86FE51) == $FF
assert read1($AFFCE0) == $FF && read1($AFFD4F) == $FF
assert read1($AFFCD6) == $6B                                                     ; end of State4A (extra_options applied)

; ############################################################################
; # Constants
; ############################################################################

!MSG_PW      = $5C               ; new message id: "START" + "EXIT"
!MARK        = $000039           ; menu sub-state, used as the "leave" marker
!MARK_VAL    = $EE
!ROW_EXIT    = $04               ; cursor row of EXIT (END = 3)
!TITLE_SONG  = $1F               ; value of the "current song" tracker ($7E:FFFD) on the menu

; ############################################################################
; # PART 1 - Hijack points
; ############################################################################

; Init state: draw message $5C ("START" + "EXIT") instead of $35 ("END").
org $80EFD1
        db !MSG_PW

; D-pad clamp: rows 0-4 are valid. Original: CMP #$04 ... LDA #$03 (UP wrap)
org $80F001                      ; operand of CMP #$04 at $80:F000
        db $05                   ; was $04
org $80F00B
        db !ROW_EXIT             ; was $03  (UP from the top row -> EXIT)

; Confirm routine: JSR $F24C (password check) -> JSR PwChkStub. The BNE after
; it ($80:F03B) is untouched: A != 0 means "stay on the screen".
org $80F038
        JSR PwChkStub            ; was JSR $F24C

; Main Menu PASS WORD handler: JSR $EF45 -> JSR PwWrap (same size).
org $80933C
        JSR PwWrap               ; was JSR $EF45

; ############################################################################
; # PART 2 - Message data (bank $86)
; ############################################################################
;  Format: [len][attr][vram lo][vram hi][len bytes of tile ids] ... [0]
;  VRAM word = $0800 + row*32 + col (BG3 map). "START" replaces vanilla "END"
;  (same spot: row 21, col 7); EXIT is row 23, col 7, same attribute ($20).

org $86910B+(!MSG_PW*2)
        dw MsgPassword

org $86FE40
MsgPassword:
        db 5, $20 : dw $0AA7 : db "START"
        db 4, $20 : dw $0AE7 : db "EXIT"
        db 0
assert pc() <= $86FE52

; ############################################################################
; # PART 3 - Bank $80 stubs
; ############################################################################
;  The hooks are JSRs inside bank $80; the code proper lives in bank $AF.

org $80FEED
PwChkStub:
        JSL PwCheck              ; A = 0: password ok, != 0: stay (as $F24C)
        RTS
PwOrigCheck:
        JSR $F24C                ; the original password check
        RTL
assert pc() <= $80FF00

org $80FF8E
PwWrap:
        JSR $EF45                ; the PASS WORD loop
        JSL PwPost               ; A = 1 if EXIT was pressed
        BEQ .normal
        PLA                      ; drop our return address ($9340) ...
        PLA
        .normal
        RTS                      ; ... so this leaves the Main Menu handler
assert pc() <= $80FFA0

; ############################################################################
; # PART 4 - Bank $AF code (8-bit A/X)
; ############################################################################

org $AFFCE0

; ----------------------------------------------------------------------------
; PwCheck - replaces "JSR $F24C" in the confirm routine (DP = $3248)
;   Row 4 (EXIT): set the marker, go to the fade-out state, report "stay"
;   (A = 1) so the game neither checks nor copies the password.
;   Otherwise: the original password check, flags/A returned untouched.
; ----------------------------------------------------------------------------
PwCheck:
        LDA $07                  ; cursor row
        CMP #!ROW_EXIT
        BEQ .exit
        JSL PwOrigCheck
        RTL
        .exit
        LDA #!MARK_VAL
        STA.l !MARK
        LDA #$06
        STA $01                  ; game's own fade-out state (music fade, fade out)
        LDA #$01                 ; Z = 0 -> the BNE after the JSR returns
        RTL

; ----------------------------------------------------------------------------
; PwPost - runs right after the PASS WORD loop returned (DP = 0)
;   Marker set: back to the Main Menu like option_mode_exit does, and the
;   the music tracker restored (nothing is played). Out: A = 1 (exit) / 0 (normal).
; ----------------------------------------------------------------------------
PwPost:
        LDA.l !MARK
        CMP #!MARK_VAL
        BNE .normal
        LDA #$02
        STA $38                  ; top-level state: title/main menu
        STZ $39                  ; clears the marker, menu init substate
        STZ $3A
        STZ $3B
        STZ $3C                  ; cursor on GAME START
        LDA #!TITLE_SONG         ; no sound command: the menu has no music. Only put
        STA.l $7EFFFD            ; the "current song" tracker back to what the menu had
        LDA #$01
        RTL
        .normal
        LDA #$00
        RTL
assert pc() <= $AFFD50

; ############################################################################
; # SNES header checksum
; ############################################################################
; Complement + checksum for the patch order given in "Apply after:" + this patch
; (standard SNES checksum, 1.5 MB ROM mirrored as 1 MB + 2 x 0.5 MB).
org $80FFDC
        db $C3, $79, $3C, $86                                                 ; 80FFDC (complement, checksum)

; ============================================================================
; End of patch
; ============================================================================
