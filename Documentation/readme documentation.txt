AI was used to assist in the creation of this project.

Patch order:

  1. mmxsa1_double_tap_disabled
  2. better_walljump_for_mmxsa1
  3. faster_dialog_box_for_mmxsa1
  4. skip_boss_intro_for_mmxsa1
  5. extra_options_for_mmxsa1
  6. option_mode_exit_to_menu_for_mmxsa1
  7. hadouken_for_mmxsa1

"sa-1_plus.ips" contains all of the patches merged into one. You can pick and choose which patches to apply, however, mmxsa1_double_tap_disabled is required for all of them, and if you're applying the option_mode_exit_to_menu_for_mmxsa1 patch, it requires extra_options_for_mmxsa1 to be applied beforehand.


Individual changes breakdown:

  mmxsa1_double_tap_disabled.ips:
      - Removes in-game slowdowns
      - Assigns dash to L by default
      - Passwords and Control Scheme are saved into SRAM (the patch "extra_options_for_mmxsa1" later adds SRAM save/load for the EXTRA OPTIONS menu toggles)
      - Sub-Tanks stop depleting at full health (though it's later made a toggle with the patch "extra_options_for_mmxsa1")
      - Double-Tap Dash disabled (though it's later made a toggle with the patch "extra_options_for_mmxsa1")

  better_walljump_for_mmxsa1.ips:
      - Walljump further while holding the Dash button (like Mega Man X2 onwards), instead of timing Jump+Dash

  faster_dialog_box_for_mmxsa1.ips:
      - Dialog boxes open, close and scroll faster

  skip_boss_intro_for_mmxsa1.ips:
      - Pressing START skips the boss intro

  extra_options_for_mmxsa1.ips:
      - Implements the EXTRA OPTIONS menu with the following toggles (also implements their gameplay gates, and the SRAM patch for the toggles, alongside the UI elements):
          - D-TAP DASH (OFF by default, toggles double-tap dash)
          - EARLY DASH (ON by default, makes dash available from the start, without the Leg Armor)
          - AIRDASH (ON by default, makes airdash available when you have Leg Armor, like Mega Man X2)
          - BETTER SUB-TANK (ON by default, stops sub-tanks from depleting once health is full)

  option_mode_exit_to_menu_for_mmxsa1.ips:
      - Exiting OPTION MODE now goes back directly to the main menu, instead of restarting the intro

  hadouken_for_mmxsa1.ips:
      - Hadouken Capsule now appears in the 1st run instead of the 5th (the other requirements remain the same)
      - Hadouken can hit during i-frames (because sometimes the game shoots one Normal Buster pellet alongside the Hadouken)
      - Hadouken can hit Wolf Sigma (final boss' final form)


See the .asm files for more information about each patch.
