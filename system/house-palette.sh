#!/usr/bin/env bash
# =============================================================================
#  house-palette.sh — the one palette for the boot chain (rEFInd, Plymouth, ly).
#
#  It is pinned and does not follow the desktop theme
#  (docs/design/shell-and-bars/boot-screens.md):
#    * `dram-theme` is sudo-free by design; the boot chain lives in /boot, /etc
#      and the initramfs, so re-theming it on every desktop switch would mean
#      sudo + an initramfs rebuild for a colour change.
#    * The boot chain is what you see when the desktop is broken. It must be
#      boring, known and identical on every host (the pam_faillock lockout and
#      the ly dur_file crash were both debugged from this screen).
#  After changing a value here, change the same colors in
#  plymouth-letterpress/letterpress.script, render the images again with
#  gen-boot-assets.py, and re-run the three apply scripts.
#
#  Source it:   . "$(dirname "$0")/house-palette.sh"
#  Python reads it too (gen-boot-assets.py parses the HP_* lines), so keep the
#  format exactly `HP_NAME=rrggbb` — no quotes, no '#', one per line.
# =============================================================================
HP_PAPER=1c140f        # background (top)
HP_PAPER_BOTTOM=100c09 # background (bottom of the gradient)
HP_INK=e6d6cb          # text
HP_SUBTEXT=a89484      # secondary text, hairlines that must not shout
HP_ACCENT=c0442b       # vermilion: progress bar, selection frame, errors
export HP_PAPER HP_PAPER_BOTTOM HP_INK HP_SUBTEXT HP_ACCENT

# ly wants 0xSSRRGGBB (SS = style byte; 00 plain, 01 bold).
hp_ly() { printf '0x%s%s' "${2:-00}" "$1"; }
