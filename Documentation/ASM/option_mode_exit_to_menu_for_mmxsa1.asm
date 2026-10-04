; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Option Mode Exit To Menu" Patch
;  Apply after: SA-1, Extra Options (required)
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off option_mode_exit_to_menu_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Pressing EXIT in OPTION MODE returns straight to the main menu, exactly
;    like EXIT in EXTRA OPTIONS already does, instead of restarting the
;    intro.
;
;    Does not overlap Hadouken (either order works).
; ============================================================================

lorom

; ############################################################################
; # PART 1 - Why OPTION MODE restarted the intro
; ############################################################################
;
; Main menu handler for row 2 (OPTION MODE), $80:934A:
;
;         JSR $EAC1                 ; run OPTION MODE
;         STZ $38                   ; top-level state 0 = intro  <- the restart
;         STZ $39,$3A,$3B,$3C
;         RTS
;
; $38 is a byte offset into a 2-entry state table ($80:8C68): 0 = intro,
; 2 = title/main menu. EXTRA OPTIONS uses $38 = 2, with $39-$3C = 0 so the
; menu's init (substate 0) runs again. This patch does the same for
; OPTION MODE.
;
; SRAM:
;
; OPTION MODE persists the control scheme live: every remap writes both WRAM
; ($7EFFC0+) and BW-RAM ($6110+ = $40:0110) the moment it changes
; ($80:EC7F / $80:EC8D). Its EXIT handler ($80:ED84) writes nothing; it only
; plays sounds and fades out. So there is no save-on-exit to preserve, and
; this patch adds no SRAM writes. The intro replay only re-read $6110+ into
; WRAM if its WRAM marker ($7EFFA0, vs the ROM header) was stale, i.e. on
; first boot - skipping it loses nothing. Nothing after boot changes BW-RAM
; write-enable ($2226) or the block map ($2224).
; ----------------------------------------------------------------------------

!STATE     = $38                 ; top-level state (0 = intro, 2 = main menu)
!MENU      = $02                 ; top-level state of the title/main menu

; ----------------------------------------------------------------------------
; Hijack point (bank $80) - the STZ chain after OPTION MODE returns
; ----------------------------------------------------------------------------
; Original 11 bytes: STZ $38 / STZ $39 / STZ $3A / STZ $3B / STZ $3C / RTS
; The first 4 bytes become a JMP, the rest is NOP padding. The original RTS
; at $809357 is deliberately kept: Extra Options' MenuDispatch does
; JML $809357.
org $80934D
        JMP OptionExit            ; 4C xx xx
        NOP : NOP : NOP : NOP : NOP : NOP : NOP   ; rest of the old STZ chain
assert pc() == $809357

; ----------------------------------------------------------------------------
; OptionExit
;   Free space in bank $80, right after Extra Options' trampolines (which
;   assert they end below $80FEE0).
; ----------------------------------------------------------------------------
org $80FEE0
OptionExit:
        LDA.b #!MENU              ; top-level state 2 = main menu
        STA !STATE
        STZ $39                   ; substate 0 = menu init (reloads logo gfx)
        STZ $3A
        STZ $3B
        STZ $3C                   ; cursor on GAME START
        RTS                       ; back to the caller of $80:934A
assert pc() <= $80FFA0

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $5A, $D5, $A5, $2A                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
