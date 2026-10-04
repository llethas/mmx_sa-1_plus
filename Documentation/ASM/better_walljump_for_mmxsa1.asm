; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Better Walljump" Patch
;  Apply after: SA-1
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off better_walljump_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Walljump further while HOLDING the Dash button (like Mega Man X2
;    onwards), instead of having to time Jump + Dash. This behaviour is
;    always on.
;
;    Requires the SA-1 patch (it uses the SA-1 port's relocated RAM map).
;    Independent of every other patch in the set: no overlapping bytes, and
;    no free space is used.
; ============================================================================

lorom

; ############################################################################
; # PART 1 - Walljump push-off speed
; ############################################################################
;
; When X kicks off a wall, his horizontal push-off speed ($5C) is picked
; from two values:
;
;   $0178  (~1.47 px/frame)  - normal push-off
;   $0375  (~3.46 px/frame)  - boosted push-off
;
; Vanilla only picked the boosted speed if two separate timing flags lined
; up on the same frame, which in practice meant a frame-perfect Jump + Dash:
;
;         LDA #$0178                ; default (slow) push speed
;         LDX $56  : BEQ +          ; needs flag A set...
;         LDX $6C  : BNE +          ; ...AND flag B clear
;         LDX #$10 : STX $55        ; (side effect, no longer needed)
;         LDA #$0375                ; fast push speed
;       + STA $5C
;
; This patch replaces that with a single test of "is the Dash button
; currently held" (bit $80 of DP $36, the SA-1 port's held-buttons word at
; $6BDE). Holding Dash through the walljump gives the boosted speed.
;
; The code at $81876D (16-bit A, entered right after "REP #$20") is
; rewritten in place. It is 3 bytes shorter than the code it replaces, so
; the leftovers are NOPs and the following "STA $5C" at $81877F is
; untouched.
; ----------------------------------------------------------------------------

!HELD      = $36                 ; held-buttons word (DP, $006BDE)
!DASH_BTN  = $0080               ; Dash button bit
!SLOW      = $0178               ; normal push-off speed
!FAST      = $0375               ; boosted push-off speed

; ----------------------------------------------------------------------------
; Walljump_PushOffSpeed - rewritten in place (bank $81)
; ----------------------------------------------------------------------------
org $81876D
Walljump_PushOffSpeed:
        LDA !HELD                 ; 81876D: A5 36
        BIT.w #!DASH_BTN          ; 81876F: 89 80 00  Dash held?
        BNE .boosted              ; 818772: D0 05
        LDA.w #!SLOW              ; 818774: A9 78 01
        BRA .store                ; 818777: 80 03
.boosted
        LDA.w #!FAST              ; 818779: A9 75 03
.store
        NOP                       ; 81877C: EA
        NOP                       ; 81877D: EA
        NOP                       ; 81877E: EA
        ; 81877F: STA $5C   (original code continues, unchanged)

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $A7, $B6, $58, $49                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
