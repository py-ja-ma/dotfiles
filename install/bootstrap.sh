#!/usr/bin/env bash
# usage: bootstrap.sh [--dry-run] [--yes|-y] [--phase N]
#
# Builds pj's Hyprland dram on a fresh (or existing) Arch box. Interactive and
# vendor-aware: detects CPU (AMD/Intel), GPU (NVIDIA/Intel/AMD) and form
# factor (laptop/desktop), shows what it found, lets you override, then
# installs only the matching package sets and writes vendor-correct early-KMS
# modules and kernel parameters. Idempotent: every phase is safe to re-run.
# The user layer is applied with the home-manager pinned in flake.lock. Two
# safety prompts always ask, even with --yes ("repo not at ~/git/dotfiles -
# continue anyway?" and "/nix half-removed - proceed regardless?"); phase 6
# (hardening) always asks. Inside WSL (a host file with form = "wsl", the clone of
# decisions/0021) only phases 1 and 3 run: Windows owns the kernel, the boot chain,
# the firewall and the session, and the clone has no [dram] repo.
#
#   --dry-run     print every action, change nothing
#   --yes, -y     accept detection, run phases 1-5 unasked
#   --phase N     run one phase only
#   -h, --help    this text
#
# exit: 0 ok · 1 a phase failed or was refused · 2 bad usage
# see: docs/platforms/arch/install.md

# THE LAYER BOUNDARY (do not blur it):
#   system layer -> pacman ([dram] included) + the scripts in system/. Owns /etc, the ESP,
#                   the initramfs, the kernel, the bootloader.
#   user layer   -> the Home Manager flake. Owns ~/.config and CLI tools.
# Nix on Arch cannot own the system layer. That is by design.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO/install/lib/detect.sh"
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"

DRY=0
ASSUME=0
ONLY_PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes | -y) ASSUME=1 ;;
    --phase)
      ONLY_PHASE="${2:?--phase needs a number}"
      shift
      [[ $ONLY_PHASE =~ ^[1-6]$ ]] || {
        echo "--phase must be 1-6, got: $ONLY_PHASE" >&2
        exit 2
      }
      ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
  shift
done

say() { printf '\n\033[1;35m######\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[1;33m  !! %s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31m  ** %s\033[0m\n' "$*" >&2
  exit 1
}
# shellcheck disable=SC2294  # eval is deliberate: it lets --dry-run print the
# exact command string instead of executing it.
run() { if [ "$DRY" = 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else eval "$@"; fi; }
ask() { # ask "question" -> 0 for yes; no tty -> no (never blocks on a pipe)
  [ "$DRY" = 1 ] && {
    info "[dry-run] would ask: $1"
    return 0
  }
  [ -t 0 ] || {
    warn "no terminal to answer '$1' — taking that as no (use --yes)"
    return 1
  }
  local a
  read -rp "  $1 [y/N] " a
  [ "${a,,}" = y ]
}
phase_wanted() { [ -z "$ONLY_PHASE" ] || [ "$ONLY_PHASE" = "$1" ]; }

[ -f /etc/arch-release ] || die "This targets Arch Linux."
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root. It will sudo when needed."

# ---------------------------------------------------------------- phase 0 ----
say "0) Hardware detection"
detect_report
CPU=$(detect_cpu)
GPUS=$(detect_gpus)
FORM=$(detect_form_factor)
PLATFORM=$(detect_platform)
HOST=$(cat /etc/hostname 2>/dev/null)
[ -n "$HOST" ] || die "/etc/hostname is empty or missing — set the hostname first (hostnamectl set-hostname <name>)"
# The host file must be of this platform's kind (dram's platform guard, decisions/0021):
# inside WSL the distro takes the Windows computer name unless /etc/wsl.conf names it,
# and cabin's Windows is `cabin` — this would install the bench host's kernels and session
if [ -f "$REPO/modules/hosts/$HOST.nix" ] && [ "$(host_form "$REPO" "$HOST")" != "$PLATFORM" ]; then
  if [ "$PLATFORM" = wsl ]; then
    die "this is WSL, but modules/hosts/$HOST.nix is a metal host: name the distro in /etc/wsl.conf ([network] hostname=<host>-wsl, system/wsl/wsl.conf; install/windows/dram-windows/wsl.ps1 does it), then wsl.exe --terminate <distro> from Windows"
  fi
  die "modules/hosts/$HOST.nix is a WSL clone (form = \"wsl\"), but this is not WSL — is /etc/hostname right?"
fi
if [ "$PLATFORM" = wsl ]; then
  # the clone's GPU and devices are Windows': no hardware list to choose (roles.sh)
  GPUS=""
  info "WSL: Windows owns the kernel, the boot chain and the GPU; phases 1 and 3 run, 2 and 4-6 do not"
else
  [ "$(detect_boot_mode)" = uefi ] || warn "Not booted in UEFI mode. rEFInd and the ESP steps will not work."
  [ "$CPU" = unknown ] && warn "Could not identify the CPU vendor."
  [ -z "$GPUS" ] && warn "No display controller detected."
fi

if [ "$ASSUME" != 1 ] && [ "$DRY" != 1 ] && [ "$PLATFORM" != wsl ]; then
  echo
  if ! ask "Use this detection?"; then
    read -rp "  CPU vendor (amd/intel): " CPU
    read -rp "  GPU vendor(s), space separated (nvidia/intel/amd): " GPUS
    read -rp "  Form factor (laptop/desktop): " FORM
  fi
fi

# What install/arch-install.sh recorded (decisions/0010): a machine it installed boots
# systemd-boot + a UKI from /efi; anything else is the older rEFInd layout.
FACTS=/etc/dram/install-facts.env
BOOTLOADER=refind
[ -f "$FACTS" ] && BOOTLOADER="$(sed -n 's/^BOOTLOADER=//p' "$FACTS")"
[ "$PLATFORM" = wsl ] || info "Boot: ${BOOTLOADER:-refind}$([ -f "$FACTS" ] && echo " (from $FACTS)")"

# NVIDIA: nvidia-open needs Turing+. Swap in nvidia-dkms for older cards.
NV_PKGFILE=gpu-nvidia.txt
if [[ " $GPUS " == *" nvidia "* ]] && [ "$(detect_nvidia_open_ok)" != yes ]; then
  warn "This NVIDIA GPU looks pre-Turing; nvidia-open will not work on it."
  warn "Will substitute nvidia-dkms for nvidia-open."
  NV_PKGFILE=gpu-nvidia-legacy.txt
  PKGDIR_NV=$(mktemp -d)
  sed 's/^nvidia-open$/nvidia-dkms/' "$REPO/packages/gpu-nvidia.txt" >"$PKGDIR_NV/$NV_PKGFILE"
else
  PKGDIR_NV="$REPO/packages"
fi

# Which package files apply: base + hardware (detected above) + this host's roles
# (the `roles = [ … ];` line of modules/hosts/$HOST.nix) + packages/host-$HOST.txt.
# One reader for all of it: install/lib/roles.sh (decisions/0009).
[ -f "$REPO/modules/hosts/$HOST.nix" ] \
  || warn "no modules/hosts/$HOST.nix yet — installing base + hardware only; add the host file with its roles, then re-run phase 1"
# shellcheck disable=SC2086 # GPUS is a space-separated vendor list
mapfile -t PKGFILES < <(host_package_files "$REPO" "$HOST" "$CPU" "$FORM" $GPUS)
# pre-Turing NVIDIA: the substituted list replaces gpu-nvidia.txt
for i in "${!PKGFILES[@]}"; do
  [ "${PKGFILES[$i]}" = "$REPO/packages/gpu-nvidia.txt" ] && PKGFILES[i]="$PKGDIR_NV/$NV_PKGFILE"
done
info "Roles: $(roles_of "$REPO/modules/hosts/$HOST.nix" | tr '\n' ' ')(base is implicit; builder is system/dram-builder-setup.sh's)"

echo
info "Package sets selected:"
for f in "${PKGFILES[@]}"; do
  [ -f "$f" ] && info "  $(basename "$f")  ($(grep -vcE '^\s*(#|$)' "$f") pkgs)" || warn "  missing: $f"
done

# ---------------------------------------------------------------- phase 1 ----
if phase_wanted 1; then
  say "1) Arch repo packages"
  warn "NEVER run 'pacman -Sy <pkg>' by hand. Always -Syu. A partial upgrade is the"
  warn "classic way to break Arch."
  if [ "$ASSUME" = 1 ] || ask "Install the selected repo packages?"; then
    # steam, lib32-mesa, lib32-nvidia-utils ... live in [multilib], which a fresh
    # archinstall leaves commented out. Uncomment the section header + its Include.
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
      info "enabling [multilib] in /etc/pacman.conf"
      # range ends at the stanza's blank line, so an already-uncommented Include
      # cannot make it run on into the next commented repo
      run "sudo sed -i '/^#\[multilib\]/,/^$/ s/^#\(\[multilib\]\|Include\)/\1/' /etc/pacman.conf" || die "could not enable multilib"
    else info "multilib already enabled"; fi
    # One full upgrade first (pacstrap only synced), then dram apply converges to the
    # roles: packages, units, role hooks (decisions/0008). It never upgrades itself and
    # refuses on a half-synced system, which this -Syu rules out.
    run "sudo pacman -Syu --noconfirm" || die "pacman -Syu failed"
    APPLY_ARGS=""
    [ "$DRY" = 1 ] && APPLY_ARGS="--dry-run"
    [ "$ASSUME" = 1 ] && [ "$DRY" != 1 ] && APPLY_ARGS="--yes"
    run "DRAM_REPO='$REPO' bash '$REPO/dotfiles/.local/bin/dram' apply $APPLY_ARGS" \
      || warn "dram apply reported problems (above) — [dram] packages need the repo synced first (phase 2); re-run: bash $REPO/dotfiles/.local/bin/dram apply"
  fi
fi

# ---------------------------------------------------------------- phase 2 ----
if phase_wanted 2 && [ "$PLATFORM" = wsl ]; then
  say "2) [dram] packages — skipped in WSL"
  info "no [dram] in the clone (v1, decisions/0021): its plan leaves the [dram] names out (packages/wsl-skip.tsv)"
elif phase_wanted 2; then
  say "2) [dram] packages (our signed repo; no AUR helper)"
  # Everything that used to come from the AUR is vendored into pkgs/ and built on
  # the builder (decisions/0005); paru left the hosts 2026-10-10 (decisions/0013).
  # --- [dram]: the signed repo built on cabin, first (docs/toolchain/packaging/README.md) ---
  if [ -f "$REPO/pkgs/dram.asc" ]; then
    run "sudo bash '$REPO/system/pacman-dram-repo.sh'" || die "pacman-dram-repo.sh failed"
    if [ -f /var/lib/dram-repo/dram.db ]; then
      DRAMLIST=$(bash "$REPO/bin/pkgs.sh" list --install | tr '\n' ' ')
      # shellcheck disable=SC2086
      run "sudo pacman -Syu --needed $DRAMLIST" || die "pacman -Syu from [dram] failed"
      # [dram] names a role claims (gaming: gamescope-session, dram-gaming-mode …) come
      # with dram apply, which phase 1 ran before [dram] existed: run it again
      APPLY_ARGS=""
      [ "$DRY" = 1 ] && APPLY_ARGS="--dry-run"
      [ "$ASSUME" = 1 ] && [ "$DRY" != 1 ] && APPLY_ARGS="--yes"
      run "DRAM_REPO='$REPO' bash '$REPO/dotfiles/.local/bin/dram' apply $APPLY_ARGS" \
        || warn "dram apply reported problems (above); re-run: bash $REPO/dotfiles/.local/bin/dram apply"
    else
      warn "[dram] not synced on this host yet: bin/sync-dram-repo.sh from the Mac (handbook 07 §5), then --phase 2 again"
    fi
  else
    warn "no pkgs/dram.asc — [dram] skipped"
  fi
  AURLIST=$(sed 's/#.*//' "$REPO/packages/aur.txt" | grep -vE '^\s*$' | tr '\n' ' ' | sed 's/ *$//')
  if [ -n "$AURLIST" ]; then
    warn "packages/aur.txt lists: $AURLIST — vendor them into pkgs/ (docs/toolchain/packaging/README.md §7); no AUR helper is installed"
  else
    info "packages/aur.txt lists no packages — everything is in [dram]"
  fi
fi

# ---------------------------------------------------------------- phase 3 ----
if phase_wanted 3; then
  say "3) Nix + Home Manager + the dram (user layer)"
  warn "The repo path is LOAD-BEARING. modules/options.nix builds every dotfile symlink from"
  warn "the literal string \$HOME/git/dotfiles. A different clone path leaves every"
  warn "symlink dangling."
  if [ "$REPO" != "$HOME/git/dotfiles" ]; then
    warn "This repo is at $REPO, not \$HOME/git/dotfiles."
    ask "Continue anyway?" || die "Move the repo to ~/git/dotfiles and re-run."
  fi
  if [ "$ASSUME" = 1 ] || ask "Install Nix and apply the Home Manager flake?"; then
    # Two valid layouts: multi-user (daemon, /nix/var/nix/profiles/default) and
    # single-user (no daemon, ~/.nix-profile). cabin is single-user. Either one
    # counts as "installed" — never run the multi-user installer over a working
    # single-user store.
    NIX_MULTI=/nix/var/nix/profiles/default/bin/nix
    NIX_SINGLE="$HOME/.nix-profile/bin/nix"
    have_nix() { command -v nix >/dev/null || [ -x "$NIX_MULTI" ] || [ -x "$NIX_SINGLE" ]; }
    if [ -d /nix ] && ! have_nix; then
      warn "/nix exists but there is no nix binary — a half-removed install."
      warn "Installing over this can misbehave. Inspect it first:  sudo du -sh /nix"
      ask "Proceed regardless?" || die "Resolve /nix first."
    fi
    if ! have_nix; then
      # PINNED installer. https://nixos.org/nix/install floats to the newest
      # release; the hosts run nix 2.34.x. install/nix-install.sha256 holds
      # "<sha256>  <url>" for one versioned script, downloaded to a temp file
      # and verified before it runs (bump both together: docs/security/software-supply/pins.md).
      read -r NIX_SUM NIX_URL <"$REPO/install/nix-install.sha256"
      [ -n "$NIX_SUM" ] && [ -n "$NIX_URL" ] || die "install/nix-install.sha256 is malformed"
      NIX_TMP=$(mktemp)
      run "curl -fsSL --proto '=https' --tlsv1.2 -o '$NIX_TMP' '$NIX_URL'" || die "could not download $NIX_URL"
      if [ "$DRY" != 1 ]; then
        echo "$NIX_SUM  $NIX_TMP" | sha256sum -c --quiet - \
          || die "nix installer sha256 MISMATCH for $NIX_URL — expected $NIX_SUM (install/nix-install.sha256). Not running it."
        info "nix installer verified: $NIX_URL"
      else
        info "[dry-run] would verify $NIX_URL against $NIX_SUM"
      fi
      # --yes answers the installer's own confirmations (sudo still asks for the
      # password once); --no-channel-add keeps the floating nixpkgs-unstable
      # channel off a box whose nixpkgs is pinned by flake.lock
      run "sh '$NIX_TMP' --daemon --yes --no-channel-add" || die "nix installer failed"
      run "rm -f '$NIX_TMP'"
    elif [ -x "$NIX_SINGLE" ] && [ ! -x "$NIX_MULTI" ]; then
      info "nix already present (single-user install at $NIX_SINGLE)"
    else info "nix already present"; fi
    # shellcheck disable=SC1091
    [ -r /etc/profile.d/nix.sh ] && . /etc/profile.d/nix.sh
    # shellcheck disable=SC1091
    [ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    if [ -x "$NIX_MULTI" ]; then
      run "sudo systemctl enable --now nix-daemon.socket" || warn "could not enable nix-daemon.socket"
    else
      info "single-user nix: no daemon to enable"
    fi
    ME="$(id -un)"
    info "Applying homeConfigurations.\"$ME@$HOST\""
    if [ ! -f "$REPO/modules/hosts/$HOST.nix" ]; then
      warn "no modules/hosts/$HOST.nix — flake.nix derives <user>@$HOST from that file."
      warn "Copy modules/hosts/lantern.nix to modules/hosts/$HOST.nix, set its flags, git add + commit it."
      die "Add the host entry, then run --phase 3 again."
    elif git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      && ! git -C "$REPO" ls-files --error-unmatch "modules/hosts/$HOST.nix" >/dev/null 2>&1; then
      # a git flake only sees files git tracks; an untracked host file builds nothing
      die "modules/hosts/$HOST.nix is not tracked by git — flakes only see tracked files: git add it (and commit), then --phase 3 again"
    elif ! grep -qE "hostName[[:space:]]*=[[:space:]]*\"$HOST\"" "$REPO/modules/hosts/$HOST.nix"; then
      die "modules/hosts/$HOST.nix does not set hostName = \"$HOST\" (copied from another host?) — fix it first"
    elif [ "$(host_user "$REPO" "$HOST")" != "$ME" ]; then
      die "modules/hosts/$HOST.nix says user \"$(host_user "$REPO" "$HOST")\" but you are $ME — set dram.user there (or log in as that user)"
    else
      # Flakes on for the single-user case (no /etc/nix/nix.conf). The flake
      # manages ~/.config/nix/nix.conf from then on; this only seeds it so the
      # very first build can run. HOME_MANAGER_BACKUP_EXT moves it aside (.bak)
      # when Home Manager takes the file over, exactly like dram-switch (dated suffix).
      run "mkdir -p ~/.config/nix && grep -q experimental-features ~/.config/nix/nix.conf 2>/dev/null || printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf"
      # Build + activate the host's activationPackage straight from the flake.
      # This uses the home-manager pinned in flake.lock, NOT an unpinned
      # `home-manager/master`, so the first switch is the same build that
      # `nix flake check` and dram-switch produce later.
      ATTR="$REPO#homeConfigurations.\"$ME@$HOST\".activationPackage"
      NIXF="nix --extra-experimental-features 'nix-command flakes'"
      run "$NIXF build --no-link '$ATTR'" || die "home-manager build failed"
      run "HOME_MANAGER_BACKUP_EXT=bak-$(date +%Y%m%d-%H%M) \"\$($NIXF path-info '$ATTR')/activate\"" || die "home-manager activation failed"
      # the seed is now Home Manager's backup of it; one line we wrote, not the user's
      # (dram doctor would warn about it as an unreviewed *.bak-* file)
      for f in ~/.config/nix/nix.conf.bak-*; do
        [ -f "$f" ] && [ "$(cat "$f")" = "experimental-features = nix-command flakes" ] && run "rm -f '$f'"
      done
    fi
    if [ "$PLATFORM" != wsl ]; then # the session's units; a WSL clone has no session
      # The swaync package ships a user unit that races the dram's own autostart and
      # leaves the user session "degraded" (dram-switch then warns every run).
      run "systemctl --user mask swaync.service" || warn "could not mask swaync.service"
      # PAM (pam_gnome_keyring in /etc/pam.d/ly) must own gnome-keyring-daemon: the
      # socket-activated user unit starts it first without the login password and the
      # login keyring then never unlocks (seen on cabin 2026-10-05).
      run "systemctl --user mask gnome-keyring-daemon.socket gnome-keyring-daemon.service" || warn "could not mask gnome-keyring-daemon units"
    fi
    warn "From now on ALWAYS use 'dram switch'. NEVER bare 'home-manager switch' —"
    warn "it ignores the flake, reads ~/.config/home-manager/home.nix, and once tore"
    warn "down every dotfile symlink."
  fi
fi

# ---------------------------------------------------------------- phase 4-6 in WSL ----
# The boot look, early KMS and the firewall are Windows' in a WSL clone (decisions/0021);
# maintenance.sh, which phase 4 also runs, came with dram apply in phase 1 (its base hook)
if [ "$PLATFORM" = wsl ]; then
  for p in 4 5 6; do
    phase_wanted "$p" || continue
    case "$p" in
      4) say "4) System ricing — skipped in WSL (no greeter, boot menu or session; maintenance.sh ran with dram apply)" ;;
      5) say "5) Plymouth and early KMS — skipped in WSL (Microsoft's kernel boots the VM)" ;;
      6) say "6) Hardening — skipped in WSL (Windows' firewall and the Hyper-V firewall; sshd stays on 127.0.0.1)" ;;
    esac
  done
fi

# ---------------------------------------------------------------- phase 4 ----
if phase_wanted 4 && [ "$PLATFORM" != wsl ]; then
  say "4) System ricing — rEFInd theme, ly greeter, single session"
  if [ "$BOOTLOADER" = systemd-boot ]; then
    info "systemd-boot + UKIs (install/arch-install.sh): the rEFInd menu and the Plymouth splash"
    info "come with dram apply (system/system-dram.sh, after Secure Boot is set up)"
  else
    warn "this host does not boot UKIs: system/apply-refind.sh and plymouth-setup.sh handle only"
    warn "the UKI chain now (decisions/0011); reinstall with install/arch-install.sh"
  fi
  if [ "$ASSUME" = 1 ] || ask "Configure and enable the ly greeter on tty2?"; then
    warn "ly's 'dur_file' animation is BANNED. It crashed the boot twice on lantern"
    warn "(2026-07-02) and forced an external-ISO recovery. apply-ly.sh refuses it."
    run "sudo bash '$REPO/system/apply-ly.sh' --anim none" || die "apply-ly.sh failed"
    # ly ships ONLY a templated unit on this build. There is no plain ly.service.
    run "sudo systemctl enable ly@tty2.service" || die "could not enable ly@tty2.service"
    info "Collapsing duplicate Hyprland sessions (keeping hyprland.desktop)"
    if [ "$BOOTLOADER" = systemd-boot ]; then
      # system-dram.sh also themes rEFInd; on a systemd-boot machine do only its session step
      run "sudo rm -f /usr/share/wayland-sessions/hyprland-uwsm.desktop"
    else
      run "sudo bash '$REPO/system/system-dram.sh'" || warn "system-dram.sh reported problems"
    fi
    # Make it stick: without NoExtract every hyprland upgrade re-created
    # hyprland-uwsm.desktop and two sessions reappeared in the greeter.
    NOEX='NoExtract = usr/share/wayland-sessions/hyprland-uwsm.desktop'
    if ! grep -qxF "$NOEX" /etc/pacman.conf; then
      run "sudo sed -i '/^\[options\]/a $NOEX' /etc/pacman.conf" || warn "could not add NoExtract to /etc/pacman.conf"
    fi
    info "hyprland-uwsm.desktop is NoExtract'ed in pacman.conf; a hyprland upgrade can no longer re-add it"
  fi
  # pacman upkeep, declared once in system/maintenance.sh: package-list +
  # Proton Pass sandbox hooks, paccache/reflector/arch-audit timers
  # (every PKGBUILD reviewed, no SudoLoop). Idempotent; docs/platforms/arch/hooks.md.
  if [ "$ASSUME" = 1 ] || ask "Run system/maintenance.sh (pacman hooks, timers, pacman.conf options)?"; then
    run "sudo bash '$REPO/system/maintenance.sh'" || warn "maintenance.sh reported problems — re-run it after the first 'dram update'"
  fi
fi

# ---------------------------------------------------------------- phase 5 ----
if phase_wanted 5 && [ "$PLATFORM" != wsl ]; then
  say "5) Plymouth boot splash (vendor-correct early KMS)"
  warn "This edits /etc/mkinitcpio.conf and the bootloader's kernel parameters."
  warn "It is boot-critical. Backups are written with a .bak-<timestamp> suffix."
  # Every detected GPU contributes its early-KMS modules (hybrid boxes get both).
  KMS_MODULES=""
  KMS_CMDLINE=""
  DROP_KMS_HOOK=0
  for g in $GPUS; do
    case "$g" in
      nvidia)
        KMS_MODULES="$KMS_MODULES nvidia nvidia_modeset nvidia_uvm nvidia_drm"
        KMS_CMDLINE="nvidia_drm.modeset=1"
        # Arch wiki, NVIDIA#Early_loading: with the proprietary driver the
        # `kms` hook must go, or it pulls nouveau into the initramfs too.
        DROP_KMS_HOOK=1
        ;;
      intel) KMS_MODULES="$KMS_MODULES i915" ;;
      amd) KMS_MODULES="$KMS_MODULES amdgpu" ;;
    esac
  done
  KMS_MODULES="${KMS_MODULES# }"
  info "early-KMS MODULES for this GPU: ${KMS_MODULES:-<none>}"
  [ -n "$KMS_CMDLINE" ] && info "extra kernel parameter: $KMS_CMDLINE"
  [ "$DROP_KMS_HOOK" = 1 ] && info "the 'kms' mkinitcpio hook will be removed (NVIDIA: it would pull nouveau in)"
  info "system/plymouth-setup.sh reads KMS_MODULES / KMS_CMDLINE / DROP_KMS_HOOK from"
  info "the environment, so it is vendor-correct for every GPU above."
  if [ "$BOOTLOADER" = systemd-boot ]; then
    # every installed kernel gets a UKI preset first (a kernel the roles added, like
    # cabin's linux-lts, came with mkinitcpio's /boot template); idempotent
    run "sudo bash '$REPO/system/uki-presets.sh'" || warn "uki-presets.sh failed (its last line says why): a kernel may have no boot entry — dram doctor --boot"
    # UKI machines: early KMS goes into a mkinitcpio drop-in and /etc/kernel/cmdline,
    # then the UKIs are rebuilt. The splash itself comes later with dram apply
    # (system/system-dram.sh -> plymouth-setup.sh), after Secure Boot is set up.
    if [ "$ASSUME" = 1 ] || ask "Write early KMS for this GPU (mkinitcpio drop-in + kernel cmdline) and rebuild the UKIs?"; then
      [ -n "$KMS_MODULES" ] && run "echo 'MODULES=($KMS_MODULES)' | sudo tee /etc/mkinitcpio.conf.d/10-kms.conf >/dev/null"
      [ "$DROP_KMS_HOOK" = 1 ] && run "sudo sed -i 's/ kms / /' /etc/mkinitcpio.conf.d/dram.conf"
      if [ -n "$KMS_CMDLINE" ] && ! grep -qw "$KMS_CMDLINE" /etc/kernel/cmdline 2>/dev/null; then
        run "sudo sed -i 's/\$/ $KMS_CMDLINE/' /etc/kernel/cmdline"
      fi
      run "sudo mkinitcpio -P" || die "mkinitcpio -P failed — the previous UKIs are still on /efi"
    fi
  else
    warn "this host does not boot UKIs: no splash step for it (decisions/0011)"
  fi
fi

# ---------------------------------------------------------------- phase 6 ----
if phase_wanted 6 && [ "$PLATFORM" != wsl ]; then
  say "6) Hardening (OPTIONAL — read this before you say yes)"
  warn "system/harden.sh installs system/nftables.conf: input policy DROP, with SSH"
  warn "allowed ONLY from this host's LAN, which it writes to /etc/dram/lan.nft once:"
  warn "the subnet of the default route's interface (or DRAM_LAN=<cidr>). Run it on the"
  warn "home network, or SSH from home is LOCKED OUT at the next boot."
  if ask "Run harden.sh?"; then
    run "sudo bash '$REPO/system/harden.sh'"
  fi
fi

say "Done"
if [ "$PLATFORM" = wsl ]; then
  info "Restart the distro so /etc/wsl.conf and linger apply: from Windows,"
  info "wsl.exe --terminate $(host_wsl "$REPO" "$HOST" distro), then open it again and run dram doctor (docs/platforms/wsl/README.md)."
else
  info "Reboot before you rely on the machine — a kernel or initramfs change means"
  info "the running kernel's modules may already be gone from disk."
fi
[ "$DRY" = 1 ] && info "(dry run: nothing was changed)"
exit 0
