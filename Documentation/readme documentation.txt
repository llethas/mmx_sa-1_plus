AI was used to assist in the creation of this project.

Patch order:

  1. mmxsa1_double_tap_disabled 
  2. chameleon_sting_ride_armor_fix_for_mmxsa1
  3. better_walljump_for_mmxsa1
  4. better_dialog_box_for_mmxsa1
  5. skip_boss_intro_for_mmxsa1
  6. extra_options_for_mmxsa1
  7. option_mode_exit_to_menu_for_mmxsa1
  8. hadouken_for_mmxsa1
  9. password_exit_to_menu_for_mmxsa1
 10. relocalization_compat_for_mmxsa1

"sa-1_plus.ips" contains all of the patches merged into one. Some of the patches require a previous patch to work, but not all of them.


Individual changes breakdown:

  mmxsa1_double_tap_disabled.ips:
      - Removes in-game slowdowns
      - Assigns dash to L by default
      - Passwords and Control Scheme are saved into SRAM (the patch "extra_options_for_mmxsa1" later adds SRAM save/load for the EXTRA OPTIONS menu toggles)
      - Sub-Tanks stop depleting at full health (though it's later made a toggle with the patch "extra_options_for_mmxsa1")
      - Double-Tap Dash disabled (though it's later made a toggle with the patch "extra_options_for_mmxsa1")

  chameleon_sting_ride_armor_fix_for_mmxsa1.ips:
      Fixed a bug in the original SA-1 patch, where if you entered a Ride Armor while invincible (using the C.STING charged shot), then got hit, the game would softlock

  better_walljump_for_mmxsa1.ips:
      - Walljump further while holding the Dash button (like Mega Man X2 onwards), instead of timing Jump+Dash

  better_dialog_box_for_mmxsa1.ips:
      - Dialog boxes open, close and scroll faster
      - Holding Y or B no longer auto-skips the dialog box (holding START still does), so you can speed up the text without accidentally skipping it

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

  password_exit_to_menu_for_mmxsa1.ips:
      - Implements an EXIT button in the PASS WORD screen, so you can go back to the main menu from there
      - Renames the "END" button at the PASS WORD screen to "START" (like Mega Man X2)

  relocalization_compat_for_mmxsa1.ips:
      - Makes the mmxsa1_double_tap_disabled patch compatible with the Relocalization patches


See the .asm files for more information about each patch.
