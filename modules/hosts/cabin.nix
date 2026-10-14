{ ... }:

# cabin: the bench, an AMD/NVIDIA desktop with every role (hosts/cabin/README.md).
#   CPU: AMD Ryzen 9 5950X (16C)   GPU: NVIDIA GA102 RTX 3080 Ti (nvidia-open, prebuilt)
#   Disks (one OS per disk, decisions/0017-cabin-bench-layout.md):
#     NVMe 1 2 TB  Arch: ESP, system pool 512 GiB, data pool (games, emulation, recordings)
#     NVMe 2 2 TB  Arch's work pool (VMs, ML, containers, scratch)
#     SATA 2 TB    the test bench: Debian, Fedora, NixOS + a spare slot (system/bench-disk.sh)
#     SATA 1 TB    Windows 11 alone
#   Boot: UEFI -> rEFInd -> a signed UKI (systemd-boot behind it: the fallback and snapshot
#         entries) -> Plymouth -> ly@tty2 -> Hyprland; Windows by its own firmware entry,
#         every other OS by `dram boot-to <os>` or the firmware boot menu
#   Kernels: linux + linux-lts (prebuilt nvidia-open-lts)
#   No battery, no lid switch, no panel backlight.
#
# Everything this host needs follows from the flags below (modules/options.nix):
#   isLaptop = false  -> no lid.sh, waybar without the battery module (modules/laptop.nix)
#   gpu = "nvidia"    -> NVIDIA Wayland env, 10 GB shader cache, gamemode.ini (modules/gpu.nix)
{
  dram = {
    hostName = "cabin";
    user = "pj";
    roles = [ "desktop" "gaming" "emulation" "dump-kit" "creator" "recording" "re-lab" "sysadmin" "dev" "docker" "ml" "college" "office" "telephony" "builder" ];   # one line: install/lib/roles.sh reads it with grep (decisions/0009)
    address = "cabin";   # the Mac's ssh name for it (the LAN's DNS or ~/.ssh/config): bin/release.sh, bin/push-host.sh pj@cabin
    # sops-nix off until this install's age key is in .sops.yaml (docs/security/identity/secrets.md)
    secrets.enable = false;
    isLaptop = false;
    gpu = "nvidia";
  };
}
