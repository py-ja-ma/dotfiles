# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
{ config, lib, ... }:

# sops-nix: off until a host sets `dram.secrets.enable = true`, so a new machine can
# `dram switch` before it has an age key. Runbook: docs/security/identity/secrets.md,
# driven by system/secrets-bootstrap.sh (keygen, register, init-borg, verify).
#
# needs:  sops-nix's Home Manager module (flake input), secrets/pj.yaml, the option
#         dram.secrets.enable (modules/options.nix)
# alone:  yes in any Home Manager config with sops-nix: point defaultSopsFile at yours
# here:   imported on every host by modules/default.nix; modules/backup.nix reads the
#         Borg passphrase from it when the flag is on
#
# What the sops-nix Home Manager module does with this (verified at the locked
# rev, modules/home-manager/sops.nix):
#   - a user unit `sops-nix.service` (oneshot, WantedBy default.target, also
#     restarted on every activation) runs sops-install-secrets with
#     sops.age.keyFile as the only key source;
#   - secrets land in $XDG_RUNTIME_DIR/secrets.d/<generation>/ (tmpfs), with
#     the stable symlink  ~/.config/sops-nix/secrets/<name>  =
#     config.sops.secrets.<name>.path  (sops.defaultSymlinkPath);
#   - `validateSopsFiles` (default true) runs `sops-install-secrets
#     -check-mode=sopsfile` in the checkPhase of the manifest derivation: the
#     file is copied to the store at evaluation (it must exist and be tracked),
#     and must parse and contain every declared key at BUILD time (every
#     `dram switch`); no decryption, no IFD — `nix flake check --no-build` is safe.
#
# Consumers read `config.sops.secrets.<name>.path` only behind the same flag
# (modules/backup.nix) — with the flag off, `sops.secrets` is {} and the
# attribute does not exist.
{
  config = lib.mkIf config.dram.secrets.enable {
    sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    sops.defaultSopsFile = ../secrets/pj.yaml;
    # mode is the sops-nix default (0400); stated so the doctor check and the
    # docs do not depend on an upstream default.
    sops.secrets.borg_passphrase = { mode = "0400"; };
  };
}
