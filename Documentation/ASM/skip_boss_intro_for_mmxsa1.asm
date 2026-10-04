; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Skip Boss Intro" Patch
;  Apply after: SA-1, Better Walljump, Faster Dialog Box
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
;    Pressing START at any point of the boss intro skips the rest of it and
;    enters the selected stage. START works from the very first frame of the
;    intro, including the black loading phase right after the stage is
;    confirmed. Stages whose boss is already defeated ("reentering stage",
;    no intro) are not affected: the game's own re-entry logic still runs
;    even if START is held on the stage-select screen (see PART 2).
; ============================================================================

lorom

; ############################################################################
; # PART 1 - How the intro works, and where the patch hooks in
; ############################################################################
;
; The stage-select screen runs from the main loop at $80:94D5:
;
;   LDX $D1 / JSR ($94DF,X) / JSR $8100 (yield one frame) / BRA $94D5
;
; Direct page variables involved:
;
;   $D1 (DP)  - screen module              ($02 = stage select)
;   $D2 (DP)  - stage-select sub-module    ($00 = cursor, $02 = boss intro,
;                                           $04 = stage load)
;   $D3 (DP)  - boss intro state           (offset into the table at $80:958A)
;   $D7 (DP)  - boss intro timer, shared by the states
;   $A8 (DP)  - joypad high byte, held     (bit 4 = START)
;   $337A     - selected stage
;
; Boss intro states ($D3):
;
;   $00        setup: loads graphics and fades in. ONE long call that yields
;              frames internally (~75 frames), so the state dispatcher is not
;              reached again until it finishes
;   $02-$12    animation steps, one call per frame
;   $14        final hold. Ends when any button is held or timer $D7 expires:
;              sets $D3 = $16 and fades out
;   $16        cleanup, then $D2 = $04 (stage load). This is the same cleanup
;              the "reentering stage" path uses
;
; Because state $00 never returns to the dispatcher, a START test in the
; dispatcher would be blind for its whole duration. Instead this patch hooks
; the task scheduler at $80:80B5, the "DEC wait-counter" step, which runs
; every frame for the main task (slot 0) while it is waiting.
;
; On a skip request the main task is rewound: $D3 is forced to $14 with its
; timer expired, so the game's own end-of-intro code fades out and runs state
; $16, and execution restarts at the main loop with a fresh stack, discarding
; whatever intro routine was in flight.
;
; Undoing what an interrupted state $00 leaves behind:
;
;   - $337A is temporarily +$0D inside state $00 ($80:9623 / $80:967A,
;     restored at $80:962F / $80:968E). If the skip lands in between, it is
;     corrected here (valid stage ids are all below $0D).
;   - Scheduler slot 1 ($40) runs a helper task ($80:B08A) during state $00.
;     It is killed so it cannot keep touching VRAM / palettes afterwards.
;   - DB and D are restored. $80:B594 and $80:B59D yield with a different
;     DB, which hangs the main loop if it is kept.
;   - The main loop expects 8-bit A/X/Y and its stack at $013D.
; ----------------------------------------------------------------------------

; ############################################################################
; # PART 2 - Re-entering a stage with START held
; ############################################################################
;
; Boss intro state $00 ($80:95A2) starts with the game's own "is there an
; intro to play?" test:
;
;   95A2  STZ $33A0              ; $33A0 = "re-entering stage" flag, cleared
;   95A5  LDX $337A              ; selected stage
;   95A8  BNE $95B2              ; stage 0                   -> no intro
;   95B2  LDA $88C0,X / BEQ      ; stage without a boss       -> no intro
;   95B7  CPX #$09   / BCS       ; stage id >= 9              -> no intro
;   95BB  JSR $A000              ; A = bitmask of defeated bosses
;   95BE  LDX $337A / AND $88CD,X / BNE
;                                ; this boss already defeated -> no intro
;   95AA  LDA #$16 / STA $D3     ; skip straight to cleanup (state $16)
;         STA $33A0              ; ...and flag "re-entering stage" ($16)
;
; $33A0 != 0 is what later makes the boss room treat the boss as already
; beaten: X just teleports out to the password screen, without the victory
; music/pose or the weapon demonstration screen ($81:8C61, $81:8C9E,
; $81:8CC1 and $80:9BEA all test it).
;
; THE BUG: with START held on the stage-select screen the hook fired on the
; very first frame of the sub-module, i.e. BEFORE state $00 had run. The
; re-entry test above never executed, so $33A0 stayed $00 and the boss room
; behaved as if the boss was just defeated for the first time.
;
; THE FIX:
;   1. Before skipping, the hook evaluates the very same test (IsReentry,
;      below, reusing the game's own $80:A000 routine). If the stage is a
;      re-entry, the hook does NOTHING and lets state $00 run normally: it
;      sets $D3 = $16 and $33A0 = $16 by itself.
;   2. When the hook does skip a real intro it now also clears $33A0, which
;      is what state $00 does first ($80:95A2), because state $00 may not
;      have run yet (START held from the first frame). Otherwise a stale
;      $16 left by an earlier re-entry could leak into a first-time clear.
;
; IsReentry is pure (no side effect other than the DB switch that the caller
; restores, and $00 which is saved/restored) and idempotent, so it gives the
; same answer on every frame. Once state $00 has passed its test it biases
; $337A by +$0D, which IsReentry recognises as "real intro running".
;
!MAIN_LOOP = $94D5               ; main loop: LDX $D1
!NEXT_TASK = $80B9               ; scheduler: continue with the next task
!RESUME    = $80E9               ; scheduler: resume the current task
!STACK_TOP = $013D               ; main loop stack level

; ----------------------------------------------------------------------------
; Hijack point (bank $80) - scheduler wait-counter step
; ----------------------------------------------------------------------------
; Original 4 bytes: DEC $31,X / BEQ $80E9   (D6 31 F0 30)
; Same size in, same size out - no NOP padding needed.
org $8080B5
        JML SkipHook              ; 5C xx xx 80
assert pc() == $8080B9            ; falls into the scheduler's "next task"

; ----------------------------------------------------------------------------
; SkipHook
;   Entered with 8-bit A/X, X = scheduler slot offset (0 = main task).
;   If START is held during a boss intro that is really going to play, the
;   main task is rewound as described above. If the stage is a re-entry (no
;   intro) or START is not held, the two original instructions run.
; ----------------------------------------------------------------------------
org $80FF00
SkipHook:
        CPX #$00                  ; only the main task (slot 0)
        BNE .normal
        LDA $D1
        CMP #$02                  ; stage select module
        BNE .normal
        LDA $D2
        CMP #$02                  ; boss intro sub-module
        BNE .normal
        LDA $D3
        CMP #$14                  ; states $00-$12 only; $14 ends by itself
        BCS .normal               ; and $16+ is already leaving
        LDA $A8
        AND #$10                  ; START held?
        BEQ .normal

        PHB                       ; (kept only for the "no skip" exit)
        PEA $8686                 ; DB = $86 (the main loop's bank)
        PLB
        PLB
        JSR IsReentry             ; C=1: stage has no intro (re-entry)
        BCC .skip
        PLB                       ; re-entry: leave everything to the game,
        LDX #$00                  ; state $00 sets $D3=$16 and $33A0=$16
        BRA .normal

.skip
        STZ $33A0                 ; state $00's first action; it may not have
                                  ; run yet, don't keep a stale "re-entry" flag
        LDA #$14
        STA $D3                   ; final intro state...
        LDA #$01
        STA $D7                   ; ...with its timer already expired
        STZ $40                   ; kill the slot 1 helper task
        LDA $337A                 ; undo state $00's temporary stage +$0D
        CMP #$0D
        BCC .stage_ok
        SBC #$0D                  ; carry is set
        STA $337A
.stage_ok
        LDA #$03
        STA $30                   ; main task = running
        STZ $A0                   ; current task = main
        REP #$10
        LDX #!STACK_TOP
        TXS                       ; back to the main loop's stack level
        SEP #$30
        PEA $0000
        PLD                       ; D = 0
        JMP !MAIN_LOOP

.normal
        DEC $31,X                 ; original instructions
        BEQ .resume
        JMP !NEXT_TASK
.resume
        JMP !RESUME

; ----------------------------------------------------------------------------
; IsReentry
;   Same decision as boss intro state $00 ($80:95A5-$95C4), see PART 2.
;   In:  DB = $86, 8-bit A/X
;   Out: C = 1 -> the game will NOT play an intro for $337A (re-entry)
;        C = 0 -> a real intro is (or will be) running
;   Clobbers A, X. Preserves $00 ($80:A000 uses it as scratch).
; ----------------------------------------------------------------------------
IsReentry:
        LDX $337A
        CPX #$0D
        BCS .intro                ; biased stage id: state $00 already passed
                                  ; its test, so this is a real intro
        TXA
        BEQ .reentry              ; stage 0
        LDA $88C0,X
        BEQ .reentry              ; stage without a boss intro
        CPX #$09
        BCS .reentry              ; stage id >= 9
        LDA $00
        PHA                       ; save scratch
        JSR $A000                 ; A = defeated-boss bitmask
        LDX $337A
        AND $88CD,X               ; this stage's boss bit
        TAX
        PLA
        STA $00                   ; restore scratch
        TXA                       ; Z = boss not defeated yet
        BNE .reentry              ; already defeated
.intro
        CLC
        RTS
.reentry
        SEC
        RTS
assert pc() <= $80FFA0            ; $80FFA4+ holds the SA-1 JML stubs

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $6C, $5F, $93, $A0                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
