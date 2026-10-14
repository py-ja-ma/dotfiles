# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
#
# Backups: borgmatic (Arch package) driven by a Home Manager config + user timer.
#
# Design (docs/operations/backups/README.md): each host backs up to the other host
# over SSH, and both already run sshd, so there is nothing to sign up for. The Mac
# pulls both repositories nightly (bin/pull-backups.sh); the Mac had no Time Machine
# destination when checked on 2026-10-07, so that copy is the third one.
# eva (backup-eva.sh) stays an optional offline copy.
#
# needs:  Home Manager's programs.borgmatic; pacman's borgmatic and borg; a peer host
#         with sshd and the pinned `borg serve` key
# alone:  yes, as a Home Manager module: replace the dram.* options with your own
# here:   imported by modules/default.nix for every host; off unless the host sets
#         dram.backup.enable (paused until the NAS, decisions/0014)
#
# Secrets that live outside this repo, per host:
#   ~/.config/borgmatic/passphrase  (0600; the same passphrase on every host,
#                                    also kept on the Mac in ~/backups/borg/)
#   ~/.ssh/id_ed25519               (the host key; its pubkey is pinned to
#                                    `borg serve` in the peer's authorized_keys)
#
# Shape: home-manager's borgmatic module (>= 2026-10) takes the native borgmatic
# YAML under `settings` — snake_case keys, one flat attrset per backup. The old
# location/storage/retention/consistency/hooks sections still work but only as
# deprecated aliases that forward into `settings` with a warning. The rendered
# ~/.config/borgmatic.d/main.yaml is `removeNullValues settings` + the
# `exclude_from` entry that excludeHomeManagerSymlinks appends.
{ config, lib, ... }:
let
  home = config.home.homeDirectory;
  host = config.dram.hostName;
  peer = config.dram.backupPeer;
  peerAddr = config.dram.backupPeerAddr;
  # Borg passphrase source. With dram.secrets.enable the sops-nix user unit
  # decrypts secrets/pj.yaml#borg_passphrase to a 0400 tmpfs file whose stable
  # symlink is config.sops.secrets.borg_passphrase.path; otherwise the
  # hand-placed file. `if` keeps config.sops.* unevaluated while the flag is
  # off (sops.secrets is {} then, so the attribute does not exist).
  secrets = config.dram.secrets.enable;
  passphraseFile =
    if secrets then config.sops.secrets.borg_passphrase.path
    else "${home}/.config/borgmatic/passphrase";
in
{
  # dram.hostName / backupPeer / backupPeerAddr / backup.enable / backup.extraSources are
  # declared in modules/options.nix. PAUSED until the NAS (decisions/0014): nothing here
  # is configured unless the host sets dram.backup.enable = true.
  config = lib.mkIf config.dram.backup.enable {
    assertions = [{
      assertion = peer != "" && peerAddr != "";
      message = "dram.backup.enable needs dram.backupPeer and dram.backupPeerAddr (modules/hosts/${host}.nix)";
    }];
    programs.borgmatic = {
      enable = true;
      package = null;   # pacman's borgmatic 2.1.x, so it uses pacman's borg 1.4 (ADR 0003)
      backups.main = {
        # Still a module option (not a borgmatic key): appends a generated
        # exclude_from file listing every Home Manager symlink.
        location.excludeHomeManagerSymlinks = true;
        settings = {
          # --- location ---------------------------------------------------
          source_directories = [
            "${home}/git"
            "${home}/.ssh"
            "${home}/documents"
            "${home}/pictures"
            "${home}/projects"
            "${home}/.config"     # includes ~/.config/sops/age (custody: docs/security/identity/secrets.md)
            "${home}/.librewolf"
            "${home}/.local/share/atuin"
            "${home}/.local/share/fonts"
            "${home}/.local/share/Steam/userdata"
          ] ++ config.dram.backup.extraSources;   # per host, modules/hosts/<h>.nix
          repositories = [ { path = "ssh://pj@${peerAddr}/./backups/borg/${host}"; label = peer; } ];
          source_directories_must_exist = false;
          one_file_system = true;
          exclude_caches = true;                 # honours CACHEDIR.TAG
          exclude_if_present = [ ".nobackup" ];
          exclude_patterns = [
            "${home}/.cache" "**/.cache" "**/Cache" "**/Cache_Data" "**/Code Cache" "**/GPUCache"
            "**/CachedData" "**/CachedExtensions" "**/Service Worker" "**/ShaderCache"
            "**/Crashpad" "**/cache2" "**/startupCache" "**/storage/default" "**/IndexedDB"
            "**/node_modules" "**/.pnpm-store" "**/result" "**/result-*" "**/*.tmp" "**/*.swp"
            "${home}/.config/discord" "${home}/.config/Code/logs" "${home}/.config/VSCodium/logs"
            "${home}/.runelite/cache" "${home}/.runelite/jagexcache" "${home}/.runelite/repository2" "${home}/.runelite/logs"
          ];
          compression = "zstd,6";

          # --- storage ----------------------------------------------------
          encryption_passcommand = "cat ${passphraseFile}";
          ssh_command = "ssh -i ${home}/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=10";
          retries = 2;
          retry_wait = 120;
          lock_wait = 120; # the Mac's pull stages this repo under `borg with-lock` (bin/pull-backups.sh); wait it out instead of failing
          # The peer's DHCP address has drifted at least once (lantern's 2026-10-06
          # archive went to .13, the config now says .11); without this the nightly
          # unit would stop on borg's "repository moved" prompt.
          relocated_repo_access_is_ok = true;

          # --- retention --------------------------------------------------
          keep_daily = 7;
          keep_weekly = 4;
          keep_monthly = 6;

          # --- consistency ------------------------------------------------
          checks = [
            { name = "repository"; frequency = "2 weeks"; }
            { name = "archives";   frequency = "2 weeks"; }
            { name = "extract";    frequency = "1 month"; }
          ];

          # --- hooks ------------------------------------------------------
          # exit 75 = borgmatic "soft failure": skip quietly when the peer is off/asleep.
          # Scope matters: borgmatic 2.1.x does NOT honour 75 from `before: everything`
          # (CRITICAL + exit 1: both hosts' units failed that way on 2026-10-07);
          # `before: repository` is retried first (retries above); `before: configuration`
          # is honoured immediately with exit 0.
          commands = [
            { before = "configuration";
              run = [ "ping -q -c1 -W3 ${peerAddr} >/dev/null 2>&1 || { echo 'backup peer ${peer} unreachable, skipping'; exit 75; }" ]; }
          ];
        };
      };
    };

    systemd.user.services.borgmatic = {
      # With secrets on, pull in sops-nix.service first: it is a oneshot without
      # RemainAfterExit, so each timer run re-decrypts (idempotent) before borg.
      # (No network-online.target here: the user manager has no such unit, so the
      # dependency was a silent no-op; the ping hook above is the reachability gate.)
      Unit = {
        Description = "borgmatic backup to ${peer}";
        Wants = lib.optional secrets "sops-nix.service";
        After = lib.optional secrets "sops-nix.service";
      };
      Service = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
        ExecStart = "/usr/bin/borgmatic --verbosity -1 --syslog-verbosity 1";
      };
    };
    systemd.user.timers.borgmatic = {
      Unit.Description = "Daily borgmatic backup";
      Timer = { OnCalendar = "*-*-* 03:00"; RandomizedDelaySec = "1h"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
