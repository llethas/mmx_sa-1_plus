AI was used to assist in the creation of this project.

All .asm files were compiled using Asar with the flag "--fix-checksum=off".

You must apply the patches to a Mega Man X USA 1.0 version ROM.

The patch order is:
    mmxsa1_double_tap_disabled -> airdash_for_mmxsa1 -> faster_dialog_box_for_mmxsa1 -> skip_boss_intro_for_mmxsa1 -> dtap_menu_for_mmxsa1 -> hadouken_for_mmxsa1

"sa-1_plus.ips" contains all of the patches merged into one. You can pick and choose which patches to apply, however, mmxsa1_double_tap_disabled is required for all of them.



mmxsa1_double_tap_disabled.ips:
    - Removes in-game slowdowns
    - Passwords and Control Scheme are saved into SRAM
    - Sub-Tanks stop depleting at full health
    - Dash defaulted to L button
    - Double-Tap Dash disabled (though it's later made a toggle with the patch "dtap_menu_for_mmxsa1")

dtap_menu_for_mmxsa1.ips:
    - Double-tap Dash toggle in the options menu (OFF by default), also saved into SRAM

airdash_for_mmxsa1.ips:
    - Dash available from the start
    - Leg Capsule now gives Air Dash (like Mega Man X2)
    - Walljump further while holding the Dash button (like Mega Man X2 onwards), instead of timing Jump+Dash

hadouken_for_mmxsa1.ips:
    - Hadouken Capsule now appears in the 1st run instead of the 5th (the other requirements remain the same)
    - Hadouken can hit during i-frames (because sometimes the game shoots one Normal Buster pellet alongside the Hadouken)
    - Hadouken can hit Wolf Sigma (final boss' final form)

faster_dialog_box_for_mmxsa1.ips:
    - Dialog boxes open, close and scroll faster

skip_boss_intro_for_mmxsa1.ips:
    - Skips the boss intro by pressing START



See the .asm files for more information about each patch.
