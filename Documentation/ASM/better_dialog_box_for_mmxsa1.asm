; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Better Dialog Box" Patch
;  Apply after: SA-1, Ride Armor Fix, Better Walljump
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off better_dialog_box_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Speeds up the two animations that play out on a dialog box:
;
;      1. Opening / closing the box            (~0.8s -> ~0.2s, ~12 frames)
;      2. Scrolling up to the next text page   (~0.33s -> ~0.1-0.2s, 6-12 frames)
;
;    These are two separate, unrelated pieces of game code, documented in
;    their own sections below.
;
;    A third part changes how the "next page" wait behaves while a button
;    is held (see PART 3):
;
;      - Holding Y / B (or any other non-START button) still speeds the text
;        up, but when a page is complete the box now WAITS FOR A NEW BUTTON
;        PRESS before scrolling to the next page, exactly like when no
;        button is held at all.
;      - Holding START is unchanged: it is even faster and it keeps
;        scrolling to the next page automatically.
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


; ############################################################################
; # PART 3 - "Wait for button" at the end of a text page: press, not hold
; ############################################################################
;
; Dialog text is printed by a task whose control-code handlers live in bank
; $80 (jump table at $80:E872, one entry per control code). Code $01 is the
; "page finished, wait for the player" handler at $80:E8B8:
;
;   E8B8  INC $333D             ; "waiting for button" flag
;   E8BB  JSR $8100             ; yield one frame
;   E8BE  JSR $EA89             ; A = (held $6BDE | held $6BDF) & $F0
;   E8C1  BNE $E8D7             ; any such button held -> leave the wait
;   E8C3  ...                   ; blink the arrow, yield, loop to E8BE
;   E8D7  STZ $333D / erase arrow / back to the text loop ($80:E7A3)
;
; The test is on HELD buttons, so a button that is still held when the page
; ends (nothing but the speed-up held down) leaves the wait immediately and
; the next page scrolls in by itself.
;
; Button words (SA-1 port, game buttons after the control-scheme remap done
; by $80:E5FD; they are NOT the raw joypad bits). All are 16-bit words:
;
;   $6BDE/$6BDF  buttons HELD this frame
;                  $6BDE: bit7 Dash  bit5 Weapon L  bit4 Weapon R
;                  $6BDF: bit7 Jump  bit6 Shot      bit4 START/menu
;                         (bits 3-0 = D-pad)
;   $6BE0/$6BE1  buttons HELD LAST frame (copy of $6BDE/F taken at the very
;                start of $80:E5FD, before the new state is read)
;   $6BE2/$6BE3  buttons NEWLY PRESSED = held & ~held-last, computed at the
;                end of $80:E5FD ($80:E62B-E634)
;
; Default scheme: Shot = Y, Jump = B, Dash = L, START = START. $F0 is the
; set of buttons the vanilla "any button" test uses; the same mask is kept
; here, so the exact same buttons that used to continue the dialog still do.
;
; WHY NOT JUST READ $6BE2/$6BE3?  (the Fire Wave bug)
;   The game itself writes to $6BE3. While Fire Wave is the selected weapon
;   the player code fakes a "Shot newly pressed" bit ($40) into $6BE3 on
;   alternate frames whenever Shot is held (rapid fire). A box that opened
;   while the player was firing Fire Wave therefore saw a "fresh press" every
;   other frame and skipped every page for Y (B was unaffected). The held
;   words ($6BDE/F) and the held-last words ($6BE0/1) are not touched by that
;   code, so the edge is computed here from those two, exactly like the game's
;   own routine at $80:E62B does, but without going through the polluted
;   $6BE2/$6BE3. (Same approach as the Mega Man X2 patch, where the same
;   thing happens with Bubble Splash.)
;
; New rule at the wait:
;   - START ($6BDF bit 4) held    -> leave the wait (as before: START keeps
;                                    auto-scrolling, nothing changes)
;   - otherwise, a $F0 button newly pressed this frame, i.e.
;       held & ~held-last & $F0F0 -> leave the wait
;   - otherwise                   -> keep waiting (arrow keeps blinking)
;
; The 5 bytes "JSR $EA89 / BNE $E8D7" at $80:E8BE are replaced by
; "JML WaitForPress / NOP"; WaitForPress jumps back to $80:E8D7 (leave) or
; $80:E8C3 (keep waiting), the two places the original BNE could go to.
; A/X/Y are 8-bit there and DB is unchanged by JML, so the absolute accesses
; to $6BDE-$6BE0 behave exactly like the ones in $80:EA89. A is switched to
; 16 bits for the edge test and back (SEP keeps the Z flag); X/Y and RAM are
; not touched. $80:EA89 itself is untouched: it is still used by the speed-up
; logic (wait between characters 1 frame instead of $6F) and by the
; timed-pause code.
; ----------------------------------------------------------------------------

; Hijack point (bank $80) - replace "JSR $EA89 / BNE $E8D7" (5 bytes)
assert read1($80E8BE) == $20 && read1($80E8BF) == $89 && read1($80E8C0) == $EA   ; JSR $EA89
assert read1($80E8C1) == $D0 && read1($80E8C2) == $14                            ; BNE $E8D7
assert read1($80E8C3) == $AD && read1($80E8D7) == $9C                            ; branch targets
assert read1($AFFEA0) == $FF && read1($AFFEDF) == $FF                            ; free space
org $80E8BE
        JML WaitForPress
        NOP

; ----------------------------------------------------------------------------
; WaitForPress
;   Out: JMP $80:E8D7 (leave the wait) or JMP $80:E8C3 (keep waiting).
; ----------------------------------------------------------------------------
org $AFFEA0
WaitForPress:
        LDA $6BDF
        AND #$10                  ; START held?
        BNE .leave                ; yes: unchanged behaviour (auto-advance)
        REP #$20
        LDA $6BE0                 ; buttons held last frame
        EOR #$FFFF                ; ... not held last frame
        AND $6BDE                 ; ... and held now = newly pressed
        AND #$F0F0                ; same buttons as the vanilla $EA89 test
        SEP #$20                  ; (SEP keeps Z)
        BNE .leave
        JML $80E8C3               ; nothing new pressed: keep waiting
.leave
        JML $80E8D7
assert pc() <= $AFFEE0

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $3E, $2E, $C1, $D1                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
