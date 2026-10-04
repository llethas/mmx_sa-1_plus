; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Faster Dialog Box" Patch
;  Apply after: SA-1, Better Walljump
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off faster_dialog_box_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Speeds up the two animations that play out on a dialog box:
;
;      1. Opening / closing the box            (~0.8s -> ~0.2s, ~12 frames)
;      2. Scrolling up to the next text page   (~0.33s -> ~0.1-0.2s, 6-12 frames)
;
;    These are two separate, unrelated pieces of game code, documented in
;    their own sections below.
; ============================================================================

lorom

; ############################################################################
; # PART 1 - Box opening / closing
; ############################################################################
;
; When the dialog box opens, its black background grows from a point into
; a full-size box; when it closes, it shrinks back down. This is driven by
; two counters living on the dialog box object's direct page ($7928):
;
;   $1A (DP)  - primary box-size counter
;   $1B (DP)  - secondary box-size counter
;
; While opening, both counters are incremented by 1 every frame until they
; reach fixed targets stored at DP $07 and $08 (normally ~$58 and ~$30).
; While closing, the same two counters are decremented by 1 every frame
; until they reach 0. Whichever counter has the longer distance to travel
; determines how long the animation takes; at the original 1 unit/frame
; that's roughly 88 frames (~1.5s) each way.
;
; A shared "did anything move this frame?" flag at absolute address $0000
; is incremented by the same code whenever a counter is still short of its
; target; once a frame passes with the flag staying at 0, the box knows
; both counters are finished and advances to the next state (open -> idle,
; or close -> fully closed).
;
; This patch replaces the single-step INC/DEC on $1A and $1B with much
; larger per-frame steps, while keeping the original targets so the box
; still ends up exactly the right size:
;
;   Open  $1A : +7/frame  (reaches target $07 in ~12 frames)
;   Open  $1B : +4/frame  (reaches target $08 in exactly 12 frames)
;   Close $1A : -7/frame  (reaches 0 in ~12 frames)
;   Close $1B : -4/frame  (reaches 0 in ~12 frames)
;
; Since the original code only stops on exact equality (BEQ) against the
; target, a step that could overshoot needs to be clamped afterwards -
; clamped to the target when opening, clamped to 0 when closing - so the
; box always finishes exactly where it's supposed to instead of stalling
; past its target and never triggering the "finished" flag.
;
; Four spots in bank $83 are hijacked, each replacing a 5-byte
; "INC $0000 / INC-or-DEC $xx" sequence with a JSL to one of four small
; replacement routines living in free space at the end of the ROM.
; ----------------------------------------------------------------------------

!CNT_1A    = $1A                 ; primary box-size counter (DP-relative)
!CNT_1B    = $1B                 ; secondary box-size counter
!TGT_1A    = $07                 ; open target for $1A
!TGT_1B    = $08                 ; open target for $1B
!FLAG      = $0000               ; "still moving this frame?" flag

; ----------------------------------------------------------------------------
; Hijack points (bank $83)
; ----------------------------------------------------------------------------

; Open path - replace the 5-byte "INC $0000 / INC $xx" sequences
org $83F5CE
        JSL OpenStep_1A
        NOP

org $83F5D9
        JSL OpenStep_1B
        NOP

; Close path - replace the 5-byte "INC $0000 / DEC $xx" sequences
org $83F602
        JSL CloseStep_1A
        NOP

org $83F60B
        JSL CloseStep_1B
        NOP

; ----------------------------------------------------------------------------
; OpenStep_1A  - $1A += 7, clamp to target $07
; DP is still $7928 when called.
; ----------------------------------------------------------------------------
org $AFFE00
OpenStep_1A:
        INC !FLAG
        LDA !CNT_1A
        CLC
        ADC #$07                 ; ~12 frames to reach the open target
        CMP !TGT_1A
        BCC .store
        LDA !TGT_1A               ; clamp
.store
        STA !CNT_1A
        RTL

; ----------------------------------------------------------------------------
; OpenStep_1B  - $1B += 4, clamp to target $08
; ----------------------------------------------------------------------------
org $AFFE20
OpenStep_1B:
        INC !FLAG
        LDA !CNT_1B
        CLC
        ADC #$04                 ; exactly 12 frames to reach the open target
        CMP !TGT_1B
        BCC .store
        LDA !TGT_1B
.store
        STA !CNT_1B
        RTL

; ----------------------------------------------------------------------------
; CloseStep_1A  - $1A -= 7, clamp to 0
; ----------------------------------------------------------------------------
org $AFFE40
CloseStep_1A:
        INC !FLAG
        LDA !CNT_1A
        SEC
        SBC #$07
        BCS .store                ; no borrow -> still >= 0
        LDA #$00                  ; clamp
.store
        STA !CNT_1A
        RTL

; ----------------------------------------------------------------------------
; CloseStep_1B  - $1B -= 4, clamp to 0
; ----------------------------------------------------------------------------
org $AFFE60
CloseStep_1B:
        INC !FLAG
        LDA !CNT_1B
        SEC
        SBC #$04
        BCS .store
        LDA #$00
.store
        STA !CNT_1B
        RTL

; ############################################################################
; # PART 2 - Scrolling up to the next text page
; ############################################################################
;
; When a text page finishes and the player presses the button, the box
; doesn't reopen or resize - the background layer the text is printed on
; (BG3, hardware scroll register $2112 / BG3VOFS) is smoothly scrolled
; upward to reveal the next page, then holds at the new position.
;
; This is driven by a small generic "scroll effect" system, separate from
; the box-size counters in Part 1:
;
;   $863334 (RAM) - per-frame step added to the scroll position each frame
;   $863338 (RAM) - target scroll distance for this page (set elsewhere,
;                   normally one page's worth of text rows)
;   $0000BE (RAM) - current scroll position, added to every frame and
;                   copied out to hardware register $2112 each frame by
;                   the game's normal register-flush routine
;
; A one-time setup routine at $80EA92 initializes this system - among
; other things it hardcodes the per-frame step to 2. At 2 pixels/frame,
; scrolling a typical 40-pixel page (five 8-pixel tile rows) takes
; 40/2 = 20 frames (~0.33s).
;
; $80EA92 is a *shared* utility - ten different call sites across the ROM
; use it for other effects (menus, HUD reveals, etc.), and the step size
; is hardcoded inside the shared routine rather than passed in by the
; caller. Patching it directly would speed up every other effect that
; uses it too.
;
; This patch instead hijacks only the ONE call site used by the dialog
; text-scroll (bank $83, the box's per-frame state code). That call still
; runs the original setup exactly as before, then immediately overwrites
; just its own copy of the per-frame step from 2 to 4 before the first
; frame of scrolling happens. No other caller of $80EA92 is touched.
;
; At the new step of 4 pixels/frame, a typical 40-pixel page takes
; 40/4 = 10 frames; a taller page (up to 48px / six rows) takes exactly
; 12 frames; a shorter page takes fewer still.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Hijack point (bank $83) - the JSL that kicks off the page-scroll effect
; ----------------------------------------------------------------------------
; Original 4 bytes: JSL $80EA92   (runs the shared setup, step defaults to 2)
; Same size in, same size out - no NOP padding needed.
org $83F5E5
        JSL ScrollSpeedOverride

; ----------------------------------------------------------------------------
; ScrollSpeedOverride
;   Runs the original scroll-effect setup, then overrides just the per-frame
;   step for this call site so only the dialog text-scroll speeds up.
;   Entered with 8-bit A/X, DP=$7928, DB=$86 - all restored to those exact
;   values by $80EA92 on return (it saves/restores P and D itself), so no
;   setup is required here.
; ----------------------------------------------------------------------------
org $AFFE80
ScrollSpeedOverride:
        JSL $80EA92               ; original setup (defaults: step=2, etc.)
        LDA #$04                  ; faster per-frame scroll step (was 2)
        STA $3334
        RTL

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $58, $13, $A7, $EC                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
