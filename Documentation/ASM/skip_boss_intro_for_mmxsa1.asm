; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Skip Boss Intro" Patch
;  Apply after: the SA-1 patch (mmxsa1_double_tap_disabled.ips)
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off skip_boss_intro_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    During a boss stage intro (lightning / name plate / badge), pressing
;    START skips the remainder of the sequence and enters the stage.
;
;    The intro is driven by a small state machine:
;      $D3  = state index into jump table $80958A
;      $D7  = per-state timer
;    States $02-$0E are the visible intro. State $10 ($809898) is the game's
;    own cleanup path: it clears name-plate objects and advances toward
;    gameplay. This patch forces that cleanup state when START is pressed.
;
;  HOW IT WORKS
;    The intro dispatcher at $809585 is:
;      LDX $D3
;      JMP ($958A,X)
;    It is replaced with a JSL into free space in bank $AF. The new routine:
;
;      1. If $D3 < $02 (intro not active / between intros):
;           clear the one-shot flag and run the original dispatcher.
;      2. If START was newly pressed this frame ($7E00AB bit $1000),
;         the one-shot flag is clear, and $02 <= $D3 < $10:
;           - set the one-shot flag ($7E1F00)
;           - black out the screen ($B3 / $2100 = $00) to hide leftover
;             lightning / portrait sprites during teardown
;           - set $D3 = $10, $D7 = $01 so cleanup runs immediately
;      3. Always finish by performing the original indirect jump through
;         $80958A,X (computed into $7E0000 as a 24-bit pointer, then
;         JML [$0000]).
;
;    Edge detection uses the game's "newly pressed" input mirror at $7E00AB
;    so holding START does not re-trigger. The one-shot flag prevents a
;    second press in the same intro from interfering; it is cleared when
;    $D3 falls below $02 (next intro or left the sequence).
;
;    Brightness is set to $00 (black, display still enabled) rather than
;    force-blank ($80) so the normal stage fade-in can raise $B3 again.
;
;  RAM
;    $D3       intro state index
;    $D7       intro state timer
;    $B3       brightness mirror (copied to $2100 by the main loop)
;    $7E00AB   newly pressed controller buttons (word)
;    $7E1F00   one-shot "already skipped this intro" flag (patch)
;    $7E0000   temp 24-bit jump pointer (patch; bank byte at $7E0002)
;
;  FREE SPACE
;    Bank $AF is unused in the SA-1-patched ROM; routine is at $AFFE90.
; ============================================================================

lorom

; ----------------------------------------------------------------------------
; Hook: intro state dispatcher
; Original: LDX $D3 / JMP ($958A,X)
; ----------------------------------------------------------------------------
org $809585
        JSL BossIntroSkip
        NOP

; ----------------------------------------------------------------------------
; Skip routine
; ----------------------------------------------------------------------------
org $AFFE90
BossIntroSkip:
        PHP
        SEP #$20
        LDA $D3
        CMP #$02
        BCS .in_intro

        ; Intro not active -- allow a future intro to be skipped
        LDA #$00
        STA $7E1F00
        BRA .dispatch

.in_intro:
        REP #$20
        LDA $7E00AB              ; newly pressed buttons
        BIT #$1000               ; Start
        SEP #$20
        BEQ .dispatch

        LDA $7E1F00               ; already skipped this intro?
        BNE .dispatch

        LDA $D3
        CMP #$10                 ; already in/past cleanup?
        BCS .dispatch

        ; --- perform skip ---
        LDA #$01
        STA $7E1F00               ; one-shot

        LDA #$00                 ; black screen (no force-blank bit)
        STA $B3
        STA $2100

        LDA #$10                 ; game's cleanup state
        STA $D3
        LDA #$01                 ; expire its timer this frame
        STA $D7

.dispatch:
        PLP
        LDX $D3
        REP #$20
        LDA $80958A,X             ; handler address from jump table
        STA $7E0000
        SEP #$20
        LDA #$80                 ; bank $80
        STA $7E0002
        PLA : PLA : PLA           ; discard JSL return address
        JML [$0000]               ; -> original state handler

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum
; ----------------------------------------------------------------------------
; This patch's shipped IPS does not modify the header checksum bytes at
; $80FFDC-$80FFDF; the value left behind by the previous patch in the chain
; (Faster Dialog Box) is carried through unchanged. No write is needed here
; -- building with --fix-checksum=off keeps it that way.

; ============================================================================
; End of patch
; ============================================================================
