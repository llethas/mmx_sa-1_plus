; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Hadouken" Patch
;  Apply after: SA-1, Better Walljump, Faster Dialog Box, Skip Boss Intro,
;               Extra Options, Option Mode Exit To Menu
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off hadouken_for_mmxsa1.asm rom.sfc
;
;  WHAT IT DOES
;    Makes it possible to get the Hadouken on the first qualifying visit to
;    Armored Armadillo's stage, makes Wolf Sigma vulnerable to the Hadouken,
;    and makes the Hadouken ignore invincibility frames (because the game
;    sometimes shoots a normal buster pellet alongside the Hadouken).
; ============================================================================

lorom

; ----------------------------------------------------------------------------
; 1. Hadouken capsule available on the first qualifying visit
; ----------------------------------------------------------------------------
;
; Vanilla gates the Armored Armadillo Hadouken capsule behind a stage-revisit
; counter that must reach 5 before the rest of the spawn checks are even
; evaluated:
;
;   $87:CA96  CMP #$05
;   $87:CA98  BCC skip_capsule
;
; Two bytes starting at $87:CA97 are overwritten so the instruction stream
; becomes:
;
;   $87:CA96  CMP #$C9
;   $87:CA98  ORA ($2A,X)
;
; The original branch no longer exists; execution always falls through into
; the remaining (untouched) completion-flag / state-flag / room checks.
; Net effect: the capsule can appear on the first visit that already
; satisfies every other requirement.
; ----------------------------------------------------------------------------
org $87CA97
        db $C9, $01

; ----------------------------------------------------------------------------
; 2. Hadouken damages Wolf Sigma
; ----------------------------------------------------------------------------
;
; Every boss has a per-weapon damage table. Wolf Sigma's entry for Hadouken
; (weapon ID 4) was the sentinel value $80 ("this weapon never affects me").
; It is changed to $20 -- the same fixed damage Hadouken deals to every
; other boss.
; ----------------------------------------------------------------------------
org $86F19D
        db $20

; ----------------------------------------------------------------------------
; 3. Hadouken ignores invincibility frames
; ----------------------------------------------------------------------------
;
; When a boss is flashing after a hit, damage lookups are redirected to a
; shared "iframe" table ($86:EF9B) whose every entry is zero. Only the
; Hadouken slot (5th byte, weapon ID 4) is changed to $20. All other weapons
; remain blocked by iframes exactly as before.
; ----------------------------------------------------------------------------
org $86EF9F
        db $20

; ----------------------------------------------------------------------------
; 4. Correct death handling when a killing blow lands during iframes
; ----------------------------------------------------------------------------
;
; After a hit that reduces HP to zero the shared damage routine writes a
; new AI state ($06) and then returns. The boss's own update code checks its
; hitstun timer ($35) immediately afterwards; if that timer is still running
; the entire death-transition path is skipped for that frame.
;
; With patch 3 it becomes possible for a Hadouken to land while the timer is
; still active. The original two instructions at the lethal path
;
;   $84:9E98  STA $0004
;   $84:9E9A  LDA #$06
;
; are therefore replaced by a JSL to a short helper that:
;
;   - performs those two instructions,
;   - if (and only if) the object's AI pointer matches one of the boss
;     values listed below, also clears:
;       $35  -- generic hitstun (so every boss dies cleanly)
;       $38  -- Armored Armadillo's HP-restore timer
;       $3D  -- Boomer Kuwanger's after-image / ghost timer
;
; The AI-pointer list was taken directly from traces of every boss fight;
; no other object in the game uses these values. Ordinary enemies are
; therefore left completely untouched.
;
; X (the object/weapon index used by the caller for STA $0001,X) and the
; data bank are preserved so projectiles such as the Homing Torpedo still
; receive their correct destroy/explode state after a lethal hit.
; ----------------------------------------------------------------------------
org $849E98
        JSL HadoukenClearHitstunOnKill
        NOP

; ----------------------------------------------------------------------------
; Helper placed in previously unused space in bank $87
; ----------------------------------------------------------------------------
org $87FED5
HadoukenClearHitstunOnKill:
        STA $0004                ; original instruction
        LDA #$06                 ; original instruction
        PHA                       ; preserve A = #$06 for the STA $0001,X that follows
        PHX                       ; preserve caller's X (object/weapon index)
        PHB
        PHK
        PLB                       ; DB = current bank so the table can be read with absolute addressing
        REP #$20
        LDA $20                   ; object's AI pointer
        LDX #$0000
.loop:
        CMP BossAIList,X
        BEQ .found
        INX
        INX
        CPX #BossAIListEnd-BossAIList
        BCC .loop
        ; not a boss -- leave all timers alone
        SEP #$20
        PLB
        PLX
        BRA .done
.found:
        SEP #$20
        PLB
        PLX
        STZ $35                   ; clear hitstun
        STZ $38                   ; clear Armored Armadillo HP-restore timer
        STZ $3D                   ; clear Boomer Kuwanger ghost timer
.done:
        PLA                       ; restore A = #$06
        RTL

; Exact 16-bit AI pointers for every boss (little-endian).
; Taken from full traces of each fight.
BossAIList:
        ; Chill Penguin
        dw $C437, $C42D, $C447
        ; Spark Mandrill
        dw $CFD6, $CFA0, $CFD1
        ; Armored Armadillo
        dw $C94F, $C945, $C959
        ; Launch Octopus
        dw $C607, $C35C
        ; Boomer Kuwanger
        dw $C58D
        ; Sting Chameleon
        dw $C751, $C771, $C759
        ; Storm Eagle
        dw $D407
        ; Flame Mammoth
        dw $C839
        ; BoSpider
        dw $D652
        ; D-Rex
        dw $D59D, $D643, $D64D
        ; Rangda Bangda
        dw $D537, $D55B, $C3C5
        ; Velguarder
        dw $CD1B, $CD11
        ; Vile (phase 2)
        dw $D820
        ; Sigma phase 1
        dw $D78B, $D7A1, $D787
        ; Sigma phase 2
        dw $D867, $D863, $D859, $D793, $D79D
BossAIListEnd:

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; With the edits above in place, the ROM's contents change; the header's
; checksum and checksum-complement bytes are patched so cartridge-checksum
; validators (and picky emulators/flash carts) still report a valid ROM.
; The value is for the patch order given in "Apply after:"; every patch in
; the set carries its own, so the ROM is valid after each step.
org $80FFDC
        db $30, $08, $CF, $F7                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
