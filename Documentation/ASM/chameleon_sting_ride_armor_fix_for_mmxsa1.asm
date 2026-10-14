; ============================================================================
;  Mega Man X (SNES, USA, rev 1.0) -- "Chameleon Sting / Ride Armor" SA-1 Fix
;  Apply after: SA-1
;  Apply BEFORE: Better Walljump and every other patch of the set (their
;  header checksums are computed with this patch in the chain)
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off chameleon_sting_ride_armor_fix_for_mmxsa1.asm rom.sfc
;
;  THE BUG
;    With the SA-1 port, the charged Chameleon Sting made X invincible AND let
;    him board a Ride Armor, which never happens in the vanilla game.
;    Boarding in that state soft-locked X when he was hit, or when the enemy
;    pilot tried to jump into the armor.
;
;  ROOT CAUSE
;    The SA-1 port moved the game's work RAM from WRAM ($0800-$1FFF) to
;    BW-RAM, which the SA-1 reaches at +$6000 ($0Exx -> $6Exx, ...). One
;    reference was missed. The Ride Armor helper at $83:CAF8 tests a flag:
;
;        $83:CAF8  BIT $0E22      ; 2C 22 0E   <-- old WRAM address
;        $83:CAFB  BVC +5         ; flag clear -> return A=0
;        $83:CAFD  LDA #$14 : JMP $86F1
;
;    The SA-1 cannot see WRAM, so it read open bus (always 0): the V flag was
;    never set and the branch that makes the Ride Armor ignore an invincible X was
;    never taken. In the live game the flag sits at BW-RAM $0E22 (bit 6 is
;    set during the invincibility window).
;
;  THE FIX
;    One byte: the high byte of the operand, $0E -> $6E, so the SA-1 reads the
;    relocated variable like every other relocated reference.
;    BIT only reads memory: no RAM/SRAM writes, no stack or timing change.
;    No overlap with any other patch.
; ============================================================================

lorom

org $83CAFA
        db $6E                    ; BIT $6E22   (was BIT $0E22)

; ----------------------------------------------------------------------------
; Bank $80 -- SNES header checksum fix
; ----------------------------------------------------------------------------
; Checksum and complement for the order given in "Apply after:" + this patch.
org $80FFDC
        db $D4, $B6, $2B, $49                                                 ; 80FFDC

; ============================================================================
; End of patch
; ============================================================================
